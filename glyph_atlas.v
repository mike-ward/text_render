module vglyph

import gg
import sokol.gfx as sg
import log
import math
import time

// Pre-computed gamma lookup table for stem darkening
// gamma = 1.45, formula: val = (val/255)^(1/1.45) * 255
const gamma_table = init_gamma_table()

fn init_gamma_table() [256]u8 {
	mut table := [256]u8{}
	for i in 0 .. 256 {
		normalized := f64(i) / 255.0
		result := if normalized > 0 { math.pow(normalized, 1.0 / 1.45) } else { 0.0 }
		table[i] = u8(result * 255.0)
	}
	return table
}

const max_allocation_size = i64(1024 * 1024 * 1024) // 1GB

// Max glyph bitmap size (256x256 pixels). Prevents oversized emoji from consuming atlas.
const max_glyph_size = 256

// check_allocation_size validates width * height * channels won't overflow or exceed limits.
// Returns validated size or error with specific cause.
//
// Returns error if:
// - size <= 0 (invalid dimensions)
// - size > max_i32 (overflow)
// - size > 1GB (allocation limit)
fn check_allocation_size(w int, h int, channels int, location string) !i64 {
	size := i64(w) * i64(h) * i64(channels)
	if size <= 0 {
		return error('invalid allocation size in ${location}: ${w}x${h}x${channels}')
	}
	if size > max_i32 {
		return error('allocation overflow in ${location}: ${size} bytes exceeds max_i32')
	}
	if size > max_allocation_size {
		return error('allocation exceeds 1GB limit in ${location}: ${size} bytes')
	}
	return size
}

// AtlasPage represents a single texture page in a multi-page atlas.
struct AtlasPage {
mut:
	image         gg.Image
	width         int
	height        int
	shelves       []Shelf
	dirty         bool
	age           u64 // Frame counter when last used
	used_pixels   i64
	staging_front []u8 // GPU upload source
	staging_back  []u8 // CPU rasterization target
}

pub struct GlyphAtlas {
pub mut:
	ctx           &gg.Context
	pages         []AtlasPage
	max_pages     int = 4
	current_page  int
	frame_counter u64
	max_height    int = 4096
	garbage       []int
	last_frame    u64
	async_uploads bool = true // Kill switch: false = sync fallback
	// Profile fields - only accessed when -d profile is used
	atlas_inserts       int
	atlas_grows         int
	atlas_resets        int
	current_atlas_bytes i64
	peak_atlas_bytes    i64
}

pub struct CachedGlyph {
pub:
	x      int
	y      int
	width  int
	height int
	left   int
	top    int
	page   int // Which atlas page this glyph is on
	// Secondary key for collision detection (debug builds)
	font_face    voidptr
	glyph_index  u32
	subpixel_bin u8
}

struct Shelf {
mut:
	y        int // Vertical position of shelf top
	height   int // Shelf height (fixed at creation)
	cursor_x int // Next free x position
	width    int // Shelf width (page width)
}

// new_atlas_page creates a new atlas page with the given dimensions.
// Allocation limits:
// - Uses check_allocation_size() with 1GB max
// - Individual page typically 4096x4096x4 = 64MB max
// - Total atlas memory: 4 pages * 64MB = 256MB max
//
// Returns error if:
// - dimensions are non-positive
// - allocation size exceeds limits (1GB max)
// - memory allocation fails
fn new_atlas_page(mut ctx gg.Context, w int, h int) !AtlasPage {
	// Validate dimensions
	if w <= 0 || h <= 0 {
		return error('atlas page dimensions must be positive: ${w}x${h}')
	}

	// Check allocation size with consistent 1GB limit
	size := check_allocation_size(w, h, 4, 'new_atlas_page')!

	mut img := gg.Image{
		width:       w
		height:      h
		nr_channels: 4
	}

	// Create a dynamic Sokol image
	desc := sg.ImageDesc{
		width:        w
		height:       h
		pixel_format: .rgba8
		usage:        .dynamic
	}

	img.simg = sg.make_image(&desc)
	img.simg_ok = true
	img.id = ctx.cache_image(img)
	img.data = unsafe { vcalloc(int(size)) } // Zero-init to avoid visual artifacts
	if img.data == unsafe { nil } {
		return error('failed to allocate atlas page memory: ${size} bytes')
	}

	// Allocate staging buffers upfront
	staging_front := []u8{len: int(size), init: 0}
	staging_back := []u8{len: int(size), init: 0}

	return AtlasPage{
		image:         img
		width:         w
		height:        h
		shelves:       []Shelf{}
		age:           0
		used_pixels:   0
		staging_front: staging_front
		staging_back:  staging_back
	}
}

// new_glyph_atlas creates a new glyph atlas with initial page dimensions.
//
// Returns error if:
// - initial page creation fails (see new_atlas_page)
fn new_glyph_atlas(mut ctx gg.Context, w int, h int) !GlyphAtlas {
	// Create first page (lazy allocation - start with 1 page)
	first_page := new_atlas_page(mut ctx, w, h)!
	initial_size := i64(w) * i64(h) * 4

	atlas := GlyphAtlas{
		ctx:                 ctx
		pages:               [first_page]
		max_pages:           4
		current_page:        0
		frame_counter:       0
		max_height:          4096
		current_atlas_bytes: initial_size
		peak_atlas_bytes:    initial_size
	}
	return atlas
}

pub struct LoadGlyphConfig {
pub:
	// FT_Face borrowed from Pango (pango_ft2_font_get_face), do not free.
	// Pango owns the face lifetime; it's valid for the duration of the PangoFont.
	face          &C.FT_FaceRec
	index         u32
	target_height int
	subpixel_bin  int
}

// load_glyph rasterizes a glyph and inserts it into the atlas.
//
// Returns error if:
// - FT_Load_Glyph fails (invalid glyph index)
// - FT_Render_Glyph fails and fallback fails
// - bitmap conversion fails (unsupported pixel mode, size overflow)
// - atlas insertion fails (glyph too large)
fn (mut renderer Renderer) load_glyph(cfg LoadGlyphConfig) !CachedGlyph {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.rasterize_time_ns += time.sys_mono_now() - start
		}
	}
	// FT_LOAD_TARGET_LIGHT forces auto-hinting with a lighter touch,
	// which usually looks better on screens than FULL hinting (too distorted)
	// or NO hinting (too blurry).
	//
	// Hybrid Strategy:
	// - High DPI (>= 2.0): User prefers LCD Subpixel look.
	// - Low DPI (< 2.0): User prefers Grayscale with Gamma Correction.

	is_high_dpi := renderer.scale_factor >= 2.0
	target_flag := if is_high_dpi {
		ft_load_target_lcd
	} else {
		ft_load_target_light
	}

	// Subpixel Positioning:
	// If we are shifting (bin > 0), we must load the outline, translate it, then render.
	// We cannot use FT_LOAD_RENDER directly because it renders the unshifted glyph.
	should_shift := cfg.subpixel_bin > 0

	// Base flags: Load color (for emojis) and target mode.
	mut flags := C.FT_LOAD_COLOR | target_flag

	if !should_shift {
		// Standard path: Render immediately
		flags |= C.FT_LOAD_RENDER
	} else {
		// Shifting path: Load outline only (no bitmap yet)
		flags |= C.FT_LOAD_NO_BITMAP
	}

	// State: load_glyph entry
	// Requires: valid face (from Pango), valid glyph index
	// Produces: glyph slot populated with outline or bitmap
	if C.FT_Load_Glyph(cfg.face, cfg.index, flags) != 0 {
		if cfg.index != 0xfffffff {
			log.error('${@FILE_LINE}: FT_Load_Glyph failed 0x${cfg.index:x}')
		}
		return error('FT_Load_Glyph failed')
	}

	mut glyph := cfg.face.glyph

	// If we intended to shift, perform the translation and rendering
	if should_shift {
		// Check if we actually have an outline to shift (FT_GLYPH_FORMAT_OUTLINE)
		// We use the magic constant for 'outl' which is the format for outline glyphs.
		// If it's a bitmap font (e.g. Emoji), it won't be outline.
		// In that case, we can't subpixel shift, so we fallback to the loaded bitmap (if any) or reload.

		// Note: V doesn't have easy access to the FT_GLYPH_FORMAT constants without binding them.
		// However, if we used FT_LOAD_NO_BITMAP and got no error, and the format is NOT bitmap,
		// we likely have an outline.
		// But if the font IS bitmap-only, FT_Load_Glyph might have loaded bitmap anyway?
		// Or it returns an error?
		// Standard FreeType behavior: "If the font contains a bitmap... it is loaded...
		// unless NO_BITMAP is set... in which case the function returns an error if no outline."
		// So if we are here, and `flags` had NO_BITMAP, and no error, we have an outline!

		// Shift amount in 26.6 fixed point
		// bin 0..3 corresponds to 0, 0.25, 0.5, 0.75 pixels.
		shift := i64(cfg.subpixel_bin * ft_subpixel_unit)

		// State: outline loaded (NO_BITMAP flag used, no FT_LOAD_RENDER)
		// Requires: glyph.outline valid with n_points > 0
		// Produces: outline shifted by subpixel amount
		$if debug {
			if glyph.outline.n_points == 0 {
				panic('FT_Outline_Translate requires loaded outline, got empty. Check FT_Load_Glyph flags.')
			}
		}
		C.FT_Outline_Translate(&glyph.outline, shift, 0)

		// Now Render
		render_mode := if is_high_dpi {
			ft_render_mode_lcd
		} else {
			ft_render_mode_normal
		}
		// We use the integer values directly or we should add them to c_bindings.v

		// State: outline loaded and translated
		// Requires: glyph slot contains outline data
		// Produces: glyph.bitmap populated
		$if debug {
			if glyph == unsafe { nil } {
				panic('FT_Render_Glyph requires glyph slot. FT_Load_Glyph must succeed first.')
			}
		}
		if C.FT_Render_Glyph(glyph, render_mode) != 0 {
			// Fallback path: FT_Render_Glyph failed
			// This occurs for bitmap fonts where FT_LOAD_NO_BITMAP still loads bitmap data
			// but outline.n_points == 0, making render fail.
			//
			// Valid state sequence: reload with FT_LOAD_RENDER
			// - Resets glyph slot to fresh state
			// - Produces bitmap directly (no translate/render step needed)
			// - Same validity requirements as normal load: face + index valid
			if C.FT_Load_Glyph(cfg.face, cfg.index, C.FT_LOAD_RENDER | C.FT_LOAD_COLOR | target_flag) != 0 {
				return error('FT_Render_Glyph failed and fallback load failed')
			}
			// glyph now has bitmap directly via FT_LOAD_RENDER
		}
	}

	ft_bitmap := glyph.bitmap

	if ft_bitmap.buffer == 0 || ft_bitmap.width == 0 || ft_bitmap.rows == 0 {
		return CachedGlyph{} // space or empty glyph
	}

	bitmap := ft_bitmap_to_bitmap(&ft_bitmap, cfg.face, cfg.target_height)!

	cached, reset, reset_page := match int(ft_bitmap.pixel_mode) {
		C.FT_PIXEL_MODE_BGRA { renderer.atlas.insert_bitmap(bitmap, 0, bitmap.height)! }
		else { renderer.atlas.insert_bitmap(bitmap, int(glyph.bitmap_left), int(glyph.bitmap_top))! }
	}

	if reset {
		// Only invalidate entries on the reset page
		for key, c in renderer.cache {
			if c.page == reset_page {
				renderer.cache.delete(key)
			}
		}
	}

	return cached
}

// load_stroked_glyph rasterizes a stroked (outline-only) glyph via FT_Stroker
// and inserts it into the atlas.
//
// Returns error if:
// - FT_Load_Glyph fails
// - FT_Get_Glyph / FT_Glyph_Stroke / FT_Glyph_To_Bitmap fails
// - bitmap conversion or atlas insertion fails
fn (mut renderer Renderer) load_stroked_glyph(cfg LoadGlyphConfig,
	stroke_radius i64) !CachedGlyph {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.rasterize_time_ns += time.sys_mono_now() - start
		}
	}

	is_high_dpi := renderer.scale_factor >= 2.0
	target_flag := if is_high_dpi {
		ft_load_target_lcd
	} else {
		ft_load_target_light
	}

	// Load outline only (no bitmap, no render)
	flags := ft_load_no_bitmap | target_flag
	if C.FT_Load_Glyph(cfg.face, cfg.index, flags) != 0 {
		return error('FT_Load_Glyph failed for stroked glyph')
	}

	glyph_slot := cfg.face.glyph

	// Get independent glyph copy from slot
	mut ft_glyph := &C.FT_GlyphRec(unsafe { nil })
	if C.FT_Get_Glyph(glyph_slot, &ft_glyph) != 0 {
		return error('FT_Get_Glyph failed')
	}

	// Apply stroke
	if C.FT_Glyph_Stroke(&ft_glyph, renderer.ft_stroker, 1) != 0 {
		C.FT_Done_Glyph(ft_glyph)
		return error('FT_Glyph_Stroke failed')
	}

	// Convert to bitmap
	render_mode := if is_high_dpi {
		ft_render_mode_lcd
	} else {
		ft_render_mode_normal
	}
	if C.FT_Glyph_To_Bitmap(&ft_glyph, render_mode, unsafe { nil }, 1) != 0 {
		C.FT_Done_Glyph(ft_glyph)
		return error('FT_Glyph_To_Bitmap failed')
	}

	// Cast to BitmapGlyph
	bmp_glyph := &C.FT_BitmapGlyphRec(ft_glyph)
	ft_bitmap := &bmp_glyph.bitmap

	if ft_bitmap.buffer == 0 || ft_bitmap.width == 0 || ft_bitmap.rows == 0 {
		C.FT_Done_Glyph(ft_glyph)
		return CachedGlyph{} // empty glyph
	}

	bitmap := ft_bitmap_to_bitmap(ft_bitmap, cfg.face, cfg.target_height)!

	cached, reset, reset_page := renderer.atlas.insert_bitmap(bitmap, int(bmp_glyph.left),
		int(bmp_glyph.top))!

	if reset {
		for key, c in renderer.cache {
			if c.page == reset_page {
				renderer.cache.delete(key)
			}
		}
	}

	C.FT_Done_Glyph(ft_glyph)
	return cached
}

// ft_bitmap_to_bitmap converts a raw FreeType bitmap (GRAY, MONO, or BGRA) into
// a uniform 32-bit RGBA `Bitmap`.
// Note: ft_face is borrowed from Pango (do not free). Used only for family_name check.
//
// Supported Modes:
// - **GRAY (Grayscale)**: Common for anti-aliased text. Sets RGB=White (255)
//   and Alpha=GrayLevel, allowing tinting via vertex color.
// - **MONO (1-bit)**: Used for pixel fonts or non-AA rendering. Expands 1 bit
//   to full integer 0 or 255 alpha.
// - **BGRA (Color Bitmap)**: Used for Emoji fonts (e.g., Apple Color Image).
//   Preserves colors exactly.
// - **LCD (Subpixel)**: Flattens 3x width subpixel bitmap to RGBA by averaging
//   subpixels for alpha. Used for high-DPI rendering.
//   Important: Scales bitmap if size doesn't match target PPEM (size).
//
// Returns error if:
// - bitmap is empty (null buffer, zero dimensions)
// - bitmap size overflow (width * height * 4 > max_i32)
// - unsupported pixel mode
// - emoji bitmap exceeds max glyph size (256x256)
// - LCD bitmap width < 3
pub fn ft_bitmap_to_bitmap(bmp &C.FT_Bitmap, ft_face &C.FT_FaceRec, target_height int) !Bitmap {
	if bmp.buffer == 0 || bmp.width == 0 || bmp.rows == 0 {
		return error('empty bitmap')
	}

	mut width := int(bmp.width)
	mut height := int(bmp.rows)
	channels := 4

	// Calculate output buffer size (always RGBA)
	out_length := i64(width) * i64(height) * i64(channels)
	if out_length > max_i32 || out_length <= 0 {
		return error('bitmap size overflow: ${width}x${height}')
	}

	// Allocate output buffer - don't clone from input as FT buffer layout varies by pixel mode
	mut data := []u8{len: int(out_length)}

	// Hoist pitch direction check outside loops
	pitch_positive := bmp.pitch >= 0
	abs_pitch := if pitch_positive { bmp.pitch } else { -bmp.pitch }

	match bmp.pixel_mode {
		u8(C.FT_PIXEL_MODE_GRAY) {
			// Gamma correction using pre-computed lookup table
			for y in 0 .. height {
				src_y := if pitch_positive { y } else { height - 1 - y }
				row := unsafe { bmp.buffer + src_y * abs_pitch }
				for x in 0 .. width {
					val := unsafe { row[x] }
					i := (y * width + x) * 4
					data[i + 0] = 255
					data[i + 1] = 255
					data[i + 2] = 255
					data[i + 3] = gamma_table[val]
				}
			}
		}
		u8(C.FT_PIXEL_MODE_MONO) {
			for y in 0 .. height {
				src_y := if pitch_positive { y } else { height - 1 - y }
				row := unsafe { bmp.buffer + src_y * abs_pitch }
				for x in 0 .. width {
					byte := unsafe { row[x >> 3] }
					bit := 7 - (x & 7)
					val := if ((byte >> bit) & 1) != 0 { u8(255) } else { u8(0) }

					i := (y * width + x) * 4
					data[i + 0] = 255
					data[i + 1] = 255
					data[i + 2] = 255
					data[i + 3] = val
				}
			}
		}
		u8(C.FT_PIXEL_MODE_LCD) {
			// FreeType LCD bitmaps are 3x wider (physical subpixels)
			if width < 3 {
				return error('invalid LCD bitmap width: ${width}')
			}
			logical_width := width / 3

			// Re-allocate data for correct logical dimensions
			new_len := logical_width * height * 4
			data = []u8{len: new_len}

			for y in 0 .. height {
				src_y := if pitch_positive { y } else { height - 1 - y }
				row := unsafe { bmp.buffer + src_y * abs_pitch }
				for x in 0 .. logical_width {
					// Fetch subpixels (R, G, B)
					r := unsafe { row[x * 3 + 0] }
					g := unsafe { row[x * 3 + 1] }
					b := unsafe { row[x * 3 + 2] }

					// Simple average for alpha (approximation for standard blending)
					// This allows subpixel AA to work with standard alpha blending
					avg := (int(r) + int(g) + int(b)) / 3

					i := (y * logical_width + x) * 4
					data[i + 0] = r
					data[i + 1] = g
					data[i + 2] = b
					data[i + 3] = u8(avg)
				}
			}
			// Update width to logical width for the returned Bitmap struct
			width = logical_width
		}
		u8(C.FT_PIXEL_MODE_BGRA) {
			// Clamp to max glyph size per CONTEXT.md decision
			if width > max_glyph_size || height > max_glyph_size {
				max_sz := max_glyph_size
				return error('emoji bitmap exceeds max size ${max_sz}x${max_sz}: ${width}x${height}')
			}

			// Copy BGRA to RGBA without scaling
			// GPU handles scaling via destination rect (GL_LINEAR sampler)
			for y in 0 .. height {
				src_y := if pitch_positive { y } else { height - 1 - y }
				row := unsafe { bmp.buffer + src_y * abs_pitch }
				for x in 0 .. width {
					src := unsafe { row + x * 4 }
					i := (y * width + x) * 4
					data[i + 0] = unsafe { src[2] } // R
					data[i + 1] = unsafe { src[1] } // G
					data[i + 2] = unsafe { src[0] } // B
					data[i + 3] = unsafe { src[3] } // A
				}
			}
			// Native resolution stored, GPU handles scaling via destination rect
		}
		else {
			log.error('${@FILE_LINE}: unsupported FT pixel mode: ${bmp.pixel_mode}')
			return error('unsupported FT pixel mode: ${bmp.pixel_mode}')
		}
	}

	return Bitmap{
		width:    width
		height:   height
		channels: channels
		data:     data
	}
}

// find_best_shelf returns index of shelf with minimum vertical waste for glyph_h.
// Returns -1 if no suitable shelf found (none fit or all would waste > threshold).
fn (page &AtlasPage) find_best_shelf(glyph_w int, glyph_h int) int {
	mut best_idx := -1
	mut best_waste := max_i32

	for i, shelf in page.shelves {
		// Glyph must fit vertically
		if glyph_h > shelf.height {
			continue
		}
		// Glyph must fit horizontally
		if shelf.cursor_x + glyph_w > shelf.width {
			continue
		}

		waste := shelf.height - glyph_h
		if waste < best_waste {
			best_waste = waste
			best_idx = i
		}
	}

	// Create new shelf if wasting > 50% of glyph height
	if best_idx >= 0 && best_waste > glyph_h / 2 {
		return -1 // Signal to create new shelf
	}

	return best_idx
}

// get_next_shelf_y returns Y position for next shelf (bottom of last shelf).
fn (page &AtlasPage) get_next_shelf_y() int {
	if page.shelves.len == 0 {
		return 0
	}
	last := page.shelves[page.shelves.len - 1]
	return last.y + last.height
}

// calculate_shelf_used_pixels returns total used pixels across all shelves.
fn (page &AtlasPage) calculate_shelf_used_pixels() i64 {
	mut used := i64(0)
	for shelf in page.shelves {
		used += i64(shelf.cursor_x) * i64(shelf.height)
	}
	return used
}

// insert_bitmap places a bitmap into the atlas using shelf-based best-height-fit
// algorithm with multi-page support.
//
// Algorithm:
// - Searches for shelf with minimum vertical waste (best-height-fit)
// - Creates new shelf only when waste > 50% of glyph height
// - When page is full: add new page (up to max_pages), or reset oldest page.
//
// Returns the UV coordinates and bearing info for the cached glyph,
// a bool indicating if reset occurred, and the reset page index.
//
// Returns error if:
// - glyph dimensions exceed max atlas size
// - glyph too large after page grow/add/reset
// - page grow fails (allocation error)
// - new page creation fails
// - bitmap copy fails (out of bounds)
pub fn (mut atlas GlyphAtlas) insert_bitmap(bmp Bitmap, left int,
	top int) !(CachedGlyph, bool, int) {
	$if profile ? {
		atlas.atlas_inserts++
	}

	glyph_w := bmp.width
	glyph_h := bmp.height

	// Validate glyph dimensions don't exceed atlas max size
	if glyph_w > atlas.max_height || glyph_h > atlas.max_height {
		max_h := atlas.max_height
		return error('glyph dimensions (${glyph_w}x${glyph_h}) exceed max atlas size (${max_h})')
	}
	if glyph_w <= 0 || glyph_h <= 0 {
		return CachedGlyph{}, false, 0 // Empty glyph, nothing to insert
	}

	mut page := &atlas.pages[atlas.current_page]
	mut reset_occurred := false
	mut reset_page_idx := 0

	// Find best existing shelf or create new
	mut shelf_idx := page.find_best_shelf(glyph_w, glyph_h)

	if shelf_idx < 0 {
		// Need new shelf - check if it fits
		mut new_y := page.get_next_shelf_y()
		if new_y + glyph_h > page.height {
			// Page full - try grow/add/reset
			if page.height < atlas.max_height {
				new_height := if page.height == 0 { 1024 } else { page.height * 2 }
				atlas.grow_page(atlas.current_page, new_height)!
				page = &atlas.pages[atlas.current_page] // Refresh pointer
			} else if atlas.pages.len < atlas.max_pages {
				// Add new page
				new_page := new_atlas_page(mut atlas.ctx, page.width, 1024)!
				atlas.pages << new_page
				atlas.current_page = atlas.pages.len - 1
				page = &atlas.pages[atlas.current_page]

				// Update memory tracking
				new_size := i64(page.width) * i64(page.height) * 4
				atlas.current_atlas_bytes += new_size
				if atlas.current_atlas_bytes > atlas.peak_atlas_bytes {
					atlas.peak_atlas_bytes = atlas.current_atlas_bytes
				}
			} else {
				// All pages full: reset oldest page
				oldest_idx := atlas.find_oldest_page()
				atlas.reset_page(oldest_idx)
				atlas.current_page = oldest_idx
				page = &atlas.pages[atlas.current_page]
				reset_occurred = true
				reset_page_idx = oldest_idx
			}
			// Refresh and retry
			page = &atlas.pages[atlas.current_page]
			shelf_idx = page.find_best_shelf(glyph_w, glyph_h)
		}

		// Create new shelf if still needed
		if shelf_idx < 0 {
			new_y = page.get_next_shelf_y()
			if new_y + glyph_h > page.height {
				return error('glyph too large for atlas page')
			}
			page.shelves << Shelf{
				y:        new_y
				height:   glyph_h
				cursor_x: 0
				width:    page.width
			}
			shelf_idx = page.shelves.len - 1
		}
	}

	// Allocate from chosen shelf
	mut shelf := &page.shelves[shelf_idx]
	x := shelf.cursor_x
	y := shelf.y
	shelf.cursor_x += glyph_w

	// Copy bitmap
	copy_bitmap_to_page(mut page, bmp, x, y)!
	page.dirty = true

	// Build CachedGlyph
	cached := CachedGlyph{
		x:      x
		y:      y
		width:  glyph_w
		height: glyph_h
		left:   left
		top:    top
		page:   atlas.current_page
	}

	// Update used_pixels: sum of (cursor_x * height) for all shelves
	page.used_pixels = page.calculate_shelf_used_pixels()

	return cached, reset_occurred, reset_page_idx
}

// find_oldest_page returns the index of the page with the lowest age (least recently used).
fn (atlas &GlyphAtlas) find_oldest_page() int {
	mut oldest_idx := 0
	mut oldest_age := atlas.pages[0].age
	for i, page in atlas.pages {
		if page.age < oldest_age {
			oldest_age = page.age
			oldest_idx = i
		}
	}
	return oldest_idx
}

// reset_page clears a page's cursors and zeros its memory.
fn (mut atlas GlyphAtlas) reset_page(page_idx int) {
	$if profile ? {
		atlas.atlas_resets++
	}
	$if diag ? {
		mut page := &atlas.pages[page_idx]
		eprintln('[DIAG] RESET_PAGE: page=${page_idx} frame=${atlas.frame_counter} shelves=${page.shelves.len}')
	}
	mut page := &atlas.pages[page_idx]
	page.shelves.clear()
	page.used_pixels = 0
	page.age = atlas.frame_counter // Mark as most recently used (just reset)

	// Zero out data to avoid visual artifacts from old glyphs
	size := i64(page.width) * i64(page.height) * 4
	unsafe {
		vmemset(page.staging_back.data, 0, int(size))
		vmemset(page.staging_front.data, 0, int(size))
		vmemset(page.image.data, 0, int(size))
	}
	page.dirty = true
}

// grow_page increases the height of a specific page.
//
// Returns error if:
// - new allocation size exceeds limits (1GB max)
// - memory allocation fails
pub fn (mut atlas GlyphAtlas) grow_page(page_idx int, new_height int) ! {
	mut page := &atlas.pages[page_idx]
	if new_height <= page.height {
		return
	}
	$if profile ? {
		atlas.atlas_grows++
	}
	log.info('Growing glyph atlas page ${page_idx} from ${page.height} to ${new_height}')

	old_size := i64(page.width) * i64(page.height) * 4
	new_size := check_allocation_size(page.width, new_height, 4, 'grow_page')!

	mut new_data := unsafe { vcalloc(int(new_size)) }
	if new_data == unsafe { nil } {
		return error('allocation failed in grow_page: ${new_size} bytes')
	}

	// Copy old data
	unsafe {
		vmemcpy(new_data, page.image.data, int(old_size))
		// Zero out the new part (optional, but good for debugging)
		dest_ptr := &u8(new_data) + old_size
		vmemset(dest_ptr, 0, int(new_size - old_size))
		free(page.image.data)
	}
	page.image.data = new_data

	// Reallocate staging buffers
	mut new_staging_front := []u8{len: int(new_size), init: 0}
	mut new_staging_back := []u8{len: int(new_size), init: 0}
	// Copy old staging_back to preserve in-progress rasterization
	unsafe {
		vmemcpy(new_staging_back.data, page.staging_back.data, int(old_size))
	}
	page.staging_front = new_staging_front
	page.staging_back = new_staging_back

	page.height = new_height
	page.image.height = new_height

	// Update memory tracking
	$if profile ? {
		atlas.current_atlas_bytes += (new_size - old_size)
		if atlas.current_atlas_bytes > atlas.peak_atlas_bytes {
			atlas.peak_atlas_bytes = atlas.current_atlas_bytes
		}
	}

	// Re-create Sokol image with new size
	// Note: We're replacing the underlying sokol image entirely.
	// We MUST defer destruction because the image might still be bound in the current frame's batch.
	atlas.garbage << page.image.id

	desc := sg.ImageDesc{
		width:        page.width
		height:       new_height
		pixel_format: .rgba8
		usage:        .dynamic
	}
	page.image.simg = sg.make_image(&desc)
	page.image.id = atlas.ctx.cache_image(page.image)
	page.dirty = true // Force upload
}

// swap_staging_buffers swaps front and back staging buffers.
fn (mut page AtlasPage) swap_staging_buffers() {
	$if diag ? {
		// Sample first 16 bytes pre-swap
		sample_len := if page.staging_front.len < 16 { page.staging_front.len } else { 16 }
		front_pre := page.staging_front[..sample_len]
		back_pre := page.staging_back[..sample_len]
		identical_pre := front_pre == back_pre
		eprintln('[DIAG] PRE-SWAP: front[0..16]=${front_pre} back[0..16]=${back_pre} identical=${identical_pre}')
	}
	tmp := page.staging_front
	page.staging_front = page.staging_back
	page.staging_back = tmp
	// Preserve accumulated glyph data for next frame's CPU writes
	unsafe {
		vmemcpy(page.staging_back.data, page.staging_front.data, page.staging_front.len)
	}
	$if diag ? {
		// Sample first 16 bytes post-swap
		sample_len := if page.staging_front.len < 16 { page.staging_front.len } else { 16 }
		front_post := page.staging_front[..sample_len]
		back_post := page.staging_back[..sample_len]
		identical_post := front_post == back_post
		eprintln('[DIAG] POST-SWAP: front[0..16]=${front_post} back[0..16]=${back_post} identical=${identical_post}')
		if identical_post {
			eprintln('[DIAG] POST-SWAP: Buffers identical after copy - expected behavior')
		}
	}
}

// copy_bitmap_to_page copies bitmap data to atlas page at (x, y).
//
// Returns error if:
// - coordinates are out of bounds
fn copy_bitmap_to_page(mut page AtlasPage, bmp Bitmap, x int, y int) ! {
	// Bounds validation
	if x < 0 || y < 0 || x + bmp.width > page.width || y + bmp.height > page.height {
		sz := '${bmp.width}x${bmp.height}'
		pg := '${page.width}x${page.height}'
		return error('bitmap copy out of bounds: pos(${x},${y}) size(${sz}) page(${pg})')
	}
	if bmp.width <= 0 || bmp.height <= 0 || bmp.data.len == 0 {
		return
	}

	row_bytes := usize(bmp.width * 4)
	for row in 0 .. bmp.height {
		unsafe {
			src_ptr := &u8(bmp.data.data) + (row * bmp.width * 4)
			dst_ptr := &u8(page.staging_back.data) + ((y + row) * page.width + x) * 4
			vmemcpy(dst_ptr, src_ptr, row_bytes)
		}
	}
}

// cleanup removes stale Sokol images from previous frames to prevent leaks.
pub fn (mut atlas GlyphAtlas) cleanup(frame u64) {
	if frame > atlas.last_frame {
		for id in atlas.garbage {
			atlas.ctx.remove_cached_image_by_idx(id)
		}
		atlas.garbage.clear()
		atlas.last_frame = frame
	}
}
