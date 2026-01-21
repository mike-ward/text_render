module vglyph

import gg
import sokol.gfx as sg
import log
import math

pub struct GlyphAtlas {
pub mut:
	image      gg.Image
	width      int
	height     int
	cursor_x   int
	cursor_y   int
	row_height int
	dirty      bool
	garbage    []int
	last_frame u64
	ctx        &gg.Context
	max_height int = 4096
}

pub struct CachedGlyph {
pub:
	x      int
	y      int
	width  int
	height int
	left   int
	top    int
}

fn new_glyph_atlas(mut ctx gg.Context, w int, h int) GlyphAtlas {
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
	img.data = unsafe { malloc(w * h * 4) }

	return GlyphAtlas{
		image:      img
		width:      w
		height:     h
		ctx:        ctx
		max_height: 4096
	}
}

pub struct LoadGlyphConfig {
pub:
	face          &C.FT_FaceRec
	index         u32
	target_height int
	subpixel_bin  int
}

fn (mut renderer Renderer) load_glyph(cfg LoadGlyphConfig) !CachedGlyph {
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
		// But if the font IS bitmap-only, FT_Load_Glyph might have loaded the bitmap anyway despite NO_BITMAP?
		// Or it returns an error?
		// Standard FreeType behavior: "If the font contains a bitmap... it is loaded... unless NO_BITMAP is set... in which case the function returns an error if there is no outline."
		// So if we are here, and `flags` had NO_BITMAP, and no error, we have an outline!

		// Shift amount in 26.6 fixed point
		// bin 0..3 corresponds to 0, 0.25, 0.5, 0.75 pixels.
		// 1 pixel = 64 units. 0.25 pixels = 16 units.
		shift := i64(cfg.subpixel_bin * 16)

		C.FT_Outline_Translate(&glyph.outline, shift, 0)

		// Now Render
		// 3 is LCD, 0 is NORMAL
		render_mode := if is_high_dpi {
			3 // FT_RENDER_MODE_LCD
		} else {
			0 // FT_RENDER_MODE_NORMAL
		}
		// We use the integer values directly or we should add them to c_bindings.v

		if C.FT_Render_Glyph(glyph, render_mode) != 0 {
			// If rendering failed (e.g. maybe it wasn't an outline?), try reloading with default render
			if C.FT_Load_Glyph(cfg.face, cfg.index, C.FT_LOAD_RENDER | C.FT_LOAD_COLOR | target_flag) != 0 {
				return error('FT_Render_Glyph failed and fallback load failed')
			}
		}
	}

	ft_bitmap := glyph.bitmap

	if ft_bitmap.buffer == 0 || ft_bitmap.width == 0 || ft_bitmap.rows == 0 {
		return CachedGlyph{} // space or empty glyph
	}

	bitmap := ft_bitmap_to_bitmap(&ft_bitmap, cfg.face, cfg.target_height)!

	cached, reset := match int(ft_bitmap.pixel_mode) {
		C.FT_PIXEL_MODE_BGRA { renderer.atlas.insert_bitmap(bitmap, 0, bitmap.height)! }
		else { renderer.atlas.insert_bitmap(bitmap, int(glyph.bitmap_left), int(glyph.bitmap_top))! }
	}

	if reset {
		renderer.cache.clear()
	}

	return cached
}

// ft_bitmap_to_bitmap converts a raw FreeType bitmap (GRAY, MONO, or BGRA) into
// a uniform 32-bit RGBA `Bitmap`.
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
pub fn ft_bitmap_to_bitmap(bmp &C.FT_Bitmap, ft_face &C.FT_FaceRec, target_height int) !Bitmap {
	if bmp.buffer == 0 || bmp.width == 0 || bmp.rows == 0 {
		return error('Empty bitmap')
	}

	mut width := int(bmp.width)
	mut height := int(bmp.rows)
	channels := 4
	length := width * height * channels
	mut data := unsafe { bmp.buffer.vbytes(length).clone() }

	match bmp.pixel_mode {
		u8(C.FT_PIXEL_MODE_GRAY) {
			// Gamma Correction (Enhance stem darkness)
			// Standard monitor gamma is ~2.2. FreeType renders linearly (coverage).
			// To make text "heavier" (like macOS), we apply a gamma correction.
			// Formula: val = val ^ (1.0 / gamma)
			// Gamma 1.8 is a good middle ground for "Darkening".

			for y in 0 .. height {
				row := match bmp.pitch >= 0 {
					true { unsafe { bmp.buffer + y * bmp.pitch } }
					else { unsafe { bmp.buffer + (height - 1 - y) * (-bmp.pitch) } }
				}
				for x in 0 .. width {
					val := unsafe { row[x] }

					// Apply simple stem darkening map or calculation
					// Using integer approximation for speed if possible,
					// but floating point pow is safer for correctness first.
					// Let's use a simple lookup-table approach if we could,
					// but here we'll calc it for clarity and simplicity first.
					// Actually, let's just use a simple boost:
					// val = 255 * (val / 255.0) ^ (1.0 / 1.5)
					// Using 1.4ish for noticeable darkening.

					mut a := f64(val) / 255.0
					a = math.pow(a, 1.0 / 1.45) // 1.45 gamma factor for darkening
					final_val := u8(a * 255.0)

					i := (y * width + x) * 4
					data[i + 0] = 255
					data[i + 1] = 255
					data[i + 2] = 255
					data[i + 3] = final_val
				}
			}
		}
		u8(C.FT_PIXEL_MODE_MONO) {
			for y in 0 .. height {
				row := match bmp.pitch >= 0 {
					true { unsafe { bmp.buffer + y * bmp.pitch } }
					else { unsafe { bmp.buffer + (height - 1 - y) * (-bmp.pitch) } }
				}
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
			logical_width := width / 3

			// Re-allocate data for correct logical dimensions
			new_len := logical_width * height * 4
			data = []u8{len: new_len}

			for y in 0 .. height {
				row := match bmp.pitch >= 0 {
					true { unsafe { bmp.buffer + y * bmp.pitch } }
					else { unsafe { bmp.buffer + (height - 1 - y) * (-bmp.pitch) } }
				}
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
			for y in 0 .. height {
				row := match bmp.pitch >= 0 {
					true { unsafe { bmp.buffer + y * bmp.pitch } }
					else { unsafe { bmp.buffer + (height - 1 - y) * (-bmp.pitch) } }
				}
				for x in 0 .. width {
					src := unsafe { row + x * 4 }
					i := (y * width + x) * 4
					data[i + 0] = unsafe { src[2] } // R
					data[i + 1] = unsafe { src[1] } // G
					data[i + 2] = unsafe { src[0] } // B
					data[i + 3] = unsafe { src[3] } // A
				}
			}

			// Calculate target size (in pixels)
			// Use explicitly requested target_height if available.
			// Otherwise use metrics (though metrics are often untrustworthy
			// for bitmap fonts like Noto Color Emoji which report native size).

			y_ppem := int(ft_face.size.metrics.y_ppem)
			ascender := int(ft_face.size.metrics.ascender) >> 6 // 26.6 fixed point to pixels

			target_size := if target_height > 0 {
				target_height
			} else if ascender > 0 && ascender < y_ppem {
				ascender
			} else {
				y_ppem
			}
			needs_scaling := bmp.rows != target_size
			if needs_scaling && target_size > 0 {
				scale := f32(target_size) / f32(height)
				new_w := int(f32(width) * scale)
				new_h := int(f32(height) * scale)

				data = scale_bitmap_bicubic(data, width, height, new_w, new_h)
				width = new_w
				height = new_h
			}
		}
		else {
			log.error('${@FILE_LINE}: Unsupported FT pixel mode: ${bmp.pixel_mode}')
			return error('Unsupported FT pixel mode: ${bmp.pixel_mode}')
		}
	}

	return Bitmap{
		width:    width
		height:   height
		channels: channels
		data:     data
	}
}

// insert_bitmap places a bitmap into the atlas using a simple specialized
// shelf-packing algorithm.
//
// Algorithm:
// - Fills rows from left to right.
// - When a row is full, moves to the next row based on current row height.
// - Does not rotate or optimize heavily; glyphs are generally uniform height.
//
// Returns the UV coordinates and bearing info for the cached glyph, and a bool indicating if reset occurred.
pub fn (mut atlas GlyphAtlas) insert_bitmap(bmp Bitmap, left int, top int) !(CachedGlyph, bool) {
	glyph_w := bmp.width
	glyph_h := bmp.height

	// Move to next row if needed
	if atlas.cursor_x + glyph_w > atlas.width {
		atlas.cursor_x = 0
		atlas.cursor_y += atlas.row_height
		atlas.row_height = 0
	}

	mut reset_occurred := false

	if atlas.cursor_y + glyph_h > atlas.height {
		if atlas.height >= atlas.max_height {
			// Atlas full. Reset.
			// Warn: This invalidate all existing UVs in this frame.
			// Ideally we should flush or use multiple pages, but reset is simple and caps memory.
			atlas.cursor_x = 0
			atlas.cursor_y = 0
			atlas.row_height = 0
			reset_occurred = true

			// Zero out data to avoid visual artifacts from old glyphs?
			// Doing so is safer but slower. Let's do it.
			size := atlas.width * atlas.height * 4
			unsafe { vmemset(atlas.image.data, 0, size) }
		} else {
			// Linear doubling of height
			new_height := if atlas.height == 0 { 1024 } else { atlas.height * 2 }
			atlas.grow(new_height)
		}
	}

	// Double check reset consistency (if glyph is HUGE, it might still fail, but we assume glyph < 4096)
	if atlas.cursor_y + glyph_h > atlas.height {
		return error('Glyph too large for atlas')
	}

	copy_bitmap_to_atlas(mut atlas, bmp, atlas.cursor_x, atlas.cursor_y)
	atlas.dirty = true

	// Compute UVs
	cached := CachedGlyph{
		x:      atlas.cursor_x
		y:      atlas.cursor_y
		width:  glyph_w
		height: glyph_h
		left:   left
		top:    top
	}

	// Advance cursor
	atlas.cursor_x += glyph_w
	if glyph_h > atlas.row_height {
		atlas.row_height = glyph_h
	}

	return cached, reset_occurred
}

pub fn (mut atlas GlyphAtlas) grow(new_height int) {
	if new_height <= atlas.height {
		return
	}
	log.info('Growing glyph atlas from ${atlas.height} to ${new_height}')

	old_size := atlas.width * atlas.height * 4
	new_size := atlas.width * new_height * 4

	mut new_data := unsafe { vcalloc(new_size) } // Allocate memory for the texture data (zero-initialized)
	// Using vcalloc is critical to avoid "black rectangle" artifacts from uninitialized memory.

	// Copy old data
	unsafe {
		vmemcpy(new_data, atlas.image.data, old_size)
		// Zero out the new part (optional, but good for debugging)
		// Pointer arithmetic must be done carefully
		dest_ptr := &u8(new_data) + old_size
		vmemset(dest_ptr, 0, new_size - old_size)
		free(atlas.image.data)
	}
	atlas.image.data = new_data
	atlas.height = new_height
	atlas.image.height = new_height

	// Re-create Sokol image with new size
	// Note: We're replacing the underlying sokol image entirely.
	// We MUST defer destruction because the image might still be bound in the current frame's batch.
	atlas.garbage << atlas.image.id

	desc := sg.ImageDesc{
		width:        atlas.width
		height:       new_height
		pixel_format: .rgba8
		usage:        .dynamic
	}
	atlas.image.simg = sg.make_image(&desc)
	atlas.image.id = atlas.ctx.cache_image(atlas.image)
	atlas.dirty = true // Force upload
}

fn copy_bitmap_to_atlas(mut atlas GlyphAtlas, bmp Bitmap, x int, y int) {
	row_bytes := usize(bmp.width * 4)
	for row in 0 .. bmp.height {
		unsafe {
			src_ptr := &u8(bmp.data.data) + (row * bmp.width * 4)
			dst_ptr := &u8(atlas.image.data) + ((y + row) * atlas.width + x) * 4
			vmemcpy(dst_ptr, src_ptr, row_bytes)
		}
	}
}

pub fn (mut atlas GlyphAtlas) cleanup(frame u64) {
	if frame > atlas.last_frame {
		for id in atlas.garbage {
			atlas.ctx.remove_cached_image_by_idx(id)
		}
		atlas.garbage.clear()
		atlas.last_frame = frame
	}
}
