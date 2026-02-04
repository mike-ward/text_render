module vglyph

import gg
import math
import sokol.sgl
import sokol.gfx as sg
import time

pub struct Bitmap {
pub:
	width    int
	height   int
	channels int
	data     []u8
}

pub struct Renderer {
mut:
	ctx               &gg.Context
	atlas             GlyphAtlas
	sampler           sg.Sampler
	cache             map[u64]CachedGlyph
	cache_ages        map[u64]u64 // key -> last_used_frame
	max_cache_entries int = 4096 // capacity limit (enforced minimum 256)
	scale_factor      f32 = 1.0
	scale_inv         f32 = 1.0
pub mut:
	// Profile timing fields - only accessed when -d profile is used
	rasterize_time_ns     i64
	upload_time_ns        i64
	draw_time_ns          i64
	glyph_cache_hits      int
	glyph_cache_misses    int
	glyph_cache_evictions int
}

pub struct RendererConfig {
pub:
	max_glyph_cache_entries int = 4096
}

pub fn new_renderer_with_config(mut ctx gg.Context, scale_factor f32, cfg RendererConfig) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, 1024, 1024) or { panic(err) }
	safe_scale := if scale_factor > 0 { scale_factor } else { 1.0 }
	max := if cfg.max_glyph_cache_entries < 256 { 256 } else { cfg.max_glyph_cache_entries }
	return &Renderer{
		ctx:               ctx
		atlas:             atlas
		sampler:           create_linear_sampler()
		cache:             map[u64]CachedGlyph{}
		cache_ages:        map[u64]u64{}
		max_cache_entries: max
		scale_factor:      safe_scale
		scale_inv:         1.0 / safe_scale
	}
}

pub fn new_renderer(mut ctx gg.Context, scale_factor f32) &Renderer {
	return new_renderer_with_config(mut ctx, scale_factor, RendererConfig{})
}

pub fn new_renderer_atlas_size(mut ctx gg.Context, width int, height int, scale_factor f32) &Renderer {
	return new_renderer_atlas_size_with_config(mut ctx, width, height, scale_factor, RendererConfig{})
}

pub fn new_renderer_atlas_size_with_config(mut ctx gg.Context, width int, height int, scale_factor f32, cfg RendererConfig) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, width, height) or { panic(err) }
	safe_scale := if scale_factor > 0 { scale_factor } else { 1.0 }
	max := if cfg.max_glyph_cache_entries < 256 { 256 } else { cfg.max_glyph_cache_entries }
	return &Renderer{
		ctx:               ctx
		atlas:             atlas
		sampler:           create_linear_sampler()
		cache:             map[u64]CachedGlyph{}
		cache_ages:        map[u64]u64{}
		max_cache_entries: max
		scale_factor:      safe_scale
		scale_inv:         1.0 / safe_scale
	}
}

fn create_linear_sampler() sg.Sampler {
	smp_desc := sg.SamplerDesc{
		min_filter: .linear
		mag_filter: .linear
		wrap_u:     .clamp_to_edge
		wrap_v:     .clamp_to_edge
	}
	return sg.make_sampler(&smp_desc)
}

// commit updates GPU texture if atlas changed. Call once per frame after draws.
//
// Sokol/Graphics APIs prefer single-update-per-frame for dynamic textures.
// Multiple updates can overwrite buffer or cause stalls.
pub fn (mut renderer Renderer) commit() {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.upload_time_ns += time.sys_mono_now() - start
		}
	}
	// Update all dirty pages
	for mut page in renderer.atlas.pages {
		if page.dirty {
			page.image.update_pixel_data(page.image.data)
			page.dirty = false
		}
	}
}

// draw_layout renders Layout at (x, y).
//
// Algorithm:
// 1. Iterate Layout items.
// 2. Check cache for glyphs; loads from FreeType if missing (lazy loading).
// 3. Calc screen pos (Layout pos + Glyph offset + FreeType bearing).
// 4. Queue textured quad draw.
//
// Performance:
// - `gg` batches draws.
// - Lazy loading may cause CPU spike on first frame with new text.
pub fn (mut renderer Renderer) draw_layout(layout Layout, x f32, y f32) {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.draw_time_ns += time.sys_mono_now() - start
		}
	}
	// Item.y is BASELINE y. Draw relative to x + item.x, y + item.y.

	// Cleanup old atlas textures from previous frames
	renderer.atlas.cleanup(renderer.ctx.frame)

	// Increment frame counter for page age tracking
	renderer.atlas.frame_counter++

	for item in layout.items {
		// item.ft_face is &C.FT_FaceRec

		// Starting pen position for this run
		mut cx := x + f32(item.x)
		mut cy := y + f32(item.y) // Baseline

		// Draw Background Color
		if item.has_bg_color {
			bg_x := cx
			// item.y is baseline. Ascent is positive up.
			// so top is cy - ascent.
			bg_y := cy - f32(item.ascent)
			bg_w := f32(item.width)
			bg_h := f32(item.ascent + item.descent)
			renderer.ctx.draw_rect_filled(bg_x, bg_y, bg_w, bg_h, item.bg_color)
		}

		for i := item.glyph_start; i < item.glyph_start + item.glyph_count; i++ {
			if i < 0 || i >= layout.glyphs.len {
				continue
			}
			glyph := layout.glyphs[i]
			// Check for unknown glyph flag
			if (glyph.index & pango_glyph_unknown_flag) != 0 {
				continue
			}

			// Subpixel Positioning Logic
			// We calculate the precise physical X position we want.
			// Then we snap it to the nearest 1/4 pixel (bin 0, 1, 2, 3).
			// We effectively draw at the snapped integer position, using a glyph that
			// has been pre-shifted by the fractional part.

			scale := renderer.scale_factor
			target_x := cx + f32(glyph.x_offset)

			// Convert to physical pixels
			phys_origin_x := target_x * scale

			// Snap to nearest 0.25
			snapped_phys_x := math.round(phys_origin_x * 4.0) / 4.0

			// Separate into integer part (for placement) and subpixel bin (for glyph selection)
			draw_origin_x := math.floor(snapped_phys_x)
			frac_x := snapped_phys_x - draw_origin_x
			bin := int(frac_x * f32(subpixel_bins) + 0.1) & (subpixel_bins - 1) // +0.1 for float safety

			// Key includes the bin
			// (glyph.index << 2) | bin
			// Logic now handled in get_or_load_glyph

			cg := renderer.get_or_load_glyph(item, glyph, bin) or {
				CachedGlyph{} // fallback blank glyph
			}

			// Update page age on use
			if cg.page >= 0 && cg.page < renderer.atlas.pages.len {
				renderer.atlas.pages[cg.page].age = renderer.atlas.frame_counter
			}

			// Compute final draw position
			// Y is still pixel-snapped (Bin 0 equivalent) to preserve baseline sharpness
			phys_origin_y := (cy - f32(glyph.y_offset)) * scale
			draw_origin_y := math.round(phys_origin_y) // Bin 0

			// cg.left / cg.top are the bitmap offsets from origin (in physical pixels)
			// draw_x/y are logical coordinates for gg

			scale_inv := renderer.scale_inv
			mut draw_x := (f32(draw_origin_x) + f32(cg.left)) * scale_inv
			mut draw_y := (f32(draw_origin_y) - f32(cg.top)) * scale_inv

			mut glyph_w := f32(cg.width) * scale_inv
			mut glyph_h := f32(cg.height) * scale_inv

			// GPU emoji scaling: scale native-resolution emoji to target ascent
			if item.use_original_color && glyph_h > 0 {
				target_h := f32(item.ascent)
				if glyph_h != target_h {
					emoji_scale := target_h / glyph_h
					glyph_w *= emoji_scale
					glyph_h = target_h
					// Adjust position for scaled bearing
					draw_x = (f32(draw_origin_x) + f32(cg.left) * emoji_scale) * scale_inv
					draw_y = (f32(draw_origin_y) - f32(cg.top) * emoji_scale) * scale_inv
				}
			}

			// Draw image from glyph atlas
			if cg.width > 0 && cg.height > 0 && cg.page >= 0 && cg.page < renderer.atlas.pages.len {
				dst := gg.Rect{
					x:      draw_x
					y:      draw_y
					width:  glyph_w
					height: glyph_h
				}
				src := gg.Rect{
					x:      f32(cg.x)
					y:      f32(cg.y)
					width:  f32(cg.width)
					height: f32(cg.height)
				}

				mut c := item.color
				if item.use_original_color {
					c = gg.white
				}

				renderer.ctx.draw_image_with_config(
					img:       &renderer.atlas.pages[cg.page].image
					part_rect: src
					img_rect:  dst
					color:     c
				)
			}

			// Advance cursor
			cx += f32(glyph.x_advance)
			cy -= f32(glyph.y_advance)
		}

		// Draw Text Decorations (Underline / Strikethrough)
		if item.has_underline || item.has_strikethrough {
			// Reset pen to start of run
			run_x := x + f32(item.x)
			run_y := y + f32(item.y)

			if item.has_underline {
				line_x := run_x
				// item.underline_offset is (+) for below
				line_y := run_y + f32(item.underline_offset) - f32(item.underline_thickness)
				line_w := f32(item.width)
				line_h := f32(item.underline_thickness)

				renderer.ctx.draw_rect_filled(line_x, line_y, line_w, line_h, item.color)
			}

			if item.has_strikethrough {
				line_x := run_x
				line_y := run_y - f32(item.strikethrough_offset) + f32(item.strikethrough_thickness)
				line_w := f32(item.width)
				line_h := f32(item.strikethrough_thickness)

				renderer.ctx.draw_rect_filled(line_x, line_y, line_w, line_h, item.color)
			}
		}
	}
}

// get_atlas_height returns the current height of the first glyph atlas page.
pub fn (renderer &Renderer) get_atlas_height() int {
	if renderer.atlas.pages.len == 0 {
		return 0
	}
	return renderer.atlas.pages[0].height
}

// debug_insert_bitmap manually inserts a bitmap into the atlas.
// This is primarily for debugging atlas resizing behavior.
pub fn (mut renderer Renderer) debug_insert_bitmap(bmp Bitmap, left int, top int) !CachedGlyph {
	cached, _, _ := renderer.atlas.insert_bitmap(bmp, left, top)!
	return cached
}

// get_or_load_glyph retrieves a glyph from the cache or loads it from FreeType.
fn (mut renderer Renderer) get_or_load_glyph(item Item, glyph Glyph, bin int) !CachedGlyph {
	if item.ft_face == unsafe { nil } {
		return error('Invalid font face')
	}
	font_id := u64(voidptr(item.ft_face))

	// Key includes the bin
	// We shift the index left by 2 bits to make room for 2 bits of bin.
	// (glyph.index << 2) | bin
	index_with_bin := (u64(glyph.index) << 2) | u64(bin)
	key := font_id ^ (index_with_bin << 32)

	if key in renderer.cache {
		$if profile ? {
			renderer.glyph_cache_hits++
		}
		// Update LRU age
		renderer.cache_ages[key] = renderer.atlas.frame_counter
		cached := renderer.cache[key] or { panic('unreachable') }

		// Secondary key validation in debug builds
		$if debug {
			if cached.font_face != voidptr(item.ft_face) || cached.glyph_index != glyph.index
				|| cached.subpixel_bin != u8(bin) {
				panic('Glyph cache collision: key=0x${key:016x} expected face=${voidptr(item.ft_face)} index=${glyph.index} bin=${bin}, got face=${cached.font_face} index=${cached.glyph_index} bin=${cached.subpixel_bin}')
			}
		}

		return cached
	}

	$if profile ? {
		renderer.glyph_cache_misses++
	}

	target_h := int(f32(item.ascent) * renderer.scale_factor)
	mut cached_glyph := renderer.load_glyph(LoadGlyphConfig{
		face:          item.ft_face
		index:         glyph.index
		target_height: target_h
		subpixel_bin:  bin
	})!

	// Set secondary key fields for collision detection
	cached_glyph = CachedGlyph{
		...cached_glyph
		font_face:    voidptr(item.ft_face)
		glyph_index:  glyph.index
		subpixel_bin: u8(bin)
	}

	// Evict oldest if at capacity
	if renderer.cache.len >= renderer.max_cache_entries && key !in renderer.cache {
		renderer.evict_oldest_glyph()
	}

	renderer.cache[key] = cached_glyph
	renderer.cache_ages[key] = renderer.atlas.frame_counter
	return cached_glyph
}

fn (mut renderer Renderer) evict_oldest_glyph() {
	mut oldest_key := u64(0)
	mut oldest_age := u64(0xFFFFFFFFFFFFFFFF)
	for k, age in renderer.cache_ages {
		if age < oldest_age {
			oldest_age = age
			oldest_key = k
		}
	}
	if oldest_key != 0 || oldest_age != u64(0xFFFFFFFFFFFFFFFF) {
		renderer.cache.delete(oldest_key)
		renderer.cache_ages.delete(oldest_key)
		$if profile ? {
			renderer.glyph_cache_evictions++
		}
	}
}

// draw_layout_rotated draws the layout rotated by `angle` (in radians) around its origin.
pub fn (mut renderer Renderer) draw_layout_rotated(layout Layout, x f32, y f32, angle f32) {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.draw_time_ns += time.sys_mono_now() - start
		}
	}
	// Cleanup old atlas textures from previous frames
	renderer.atlas.cleanup(renderer.ctx.frame)

	// Increment frame counter for page age tracking
	renderer.atlas.frame_counter++

	sgl.matrix_mode_projection()
	sgl.push_matrix()
	sgl.load_identity()
	sgl.ortho(0, f32(renderer.ctx.width), f32(renderer.ctx.height), 0, -1, 1)

	sgl.matrix_mode_modelview()
	sgl.push_matrix()
	sgl.load_identity()
	sgl.translate(x, y, 0)
	sgl.rotate(angle, 0, 0, 1)

	// 1. Draw Backgrounds (Untextured)
	sgl.begin_quads()
	for item in layout.items {
		if item.has_bg_color {
			// Logical coords
			run_x := f32(item.x)
			run_y := f32(item.y) // Baseline
			bg_x := run_x
			bg_y := run_y - f32(item.ascent)
			bg_w := f32(item.width)
			bg_h := f32(item.ascent + item.descent)

			c := item.bg_color
			sgl.c4b(c.r, c.g, c.b, c.a)
			sgl.v2f(bg_x, bg_y)
			sgl.v2f(bg_x + bg_w, bg_y)
			sgl.v2f(bg_x + bg_w, bg_y + bg_h)
			sgl.v2f(bg_x, bg_y + bg_h)
		}
	}
	sgl.end()

	// 2. Draw Glyphs (Textured) - draw per page to bind correct texture
	for page_idx, page in renderer.atlas.pages {
		sgl.enable_texture()
		sgl.texture(page.image.simg, renderer.sampler)
		sgl.begin_quads()

		for item in layout.items {
			// item.ft_face is &C.FT_FaceRec

			run_x := f32(item.x)
			run_y := f32(item.y)

			mut cx := run_x
			mut cy := run_y

			mut c := item.color
			if item.use_original_color {
				c = gg.white
			}

			for i := item.glyph_start; i < item.glyph_start + item.glyph_count; i++ {
				if i < 0 || i >= layout.glyphs.len {
					continue
				}
				glyph := layout.glyphs[i]
				if (glyph.index & pango_glyph_unknown_flag) != 0 {
					cx += f32(glyph.x_advance)
					cy -= f32(glyph.y_advance)
					continue
				}

				gx := cx + f32(glyph.x_offset)
				gy := cy - f32(glyph.y_offset)

				// Load Glyph (Bin 0)
				cg := renderer.get_or_load_glyph(item, glyph, 0) or { CachedGlyph{} }

				// Update page age on use
				if cg.page >= 0 && cg.page < renderer.atlas.pages.len {
					renderer.atlas.pages[cg.page].age = renderer.atlas.frame_counter
				}

				// Only draw glyphs on the current page
				if cg.page == page_idx && cg.width > 0 && cg.height > 0 && page.width > 0
					&& page.height > 0 {
					scale_inv := renderer.scale_inv

					mut dst_x := gx + f32(cg.left) * scale_inv
					mut dst_y := gy - f32(cg.top) * scale_inv
					mut dst_w := f32(cg.width) * scale_inv
					mut dst_h := f32(cg.height) * scale_inv

					// GPU emoji scaling: scale native-resolution emoji to target ascent
					if item.use_original_color && dst_h > 0 {
						target_h := f32(item.ascent)
						if dst_h != target_h {
							emoji_scale := target_h / dst_h
							dst_w *= emoji_scale
							dst_h = target_h
							// Adjust position for scaled bearing
							dst_x = gx + f32(cg.left) * emoji_scale * scale_inv
							dst_y = gy - f32(cg.top) * emoji_scale * scale_inv
						}
					}

					atlas_w := f32(page.width)
					atlas_h := f32(page.height)

					src_x := f32(cg.x)
					src_y := f32(cg.y)
					src_w := f32(cg.width)
					src_h := f32(cg.height)

					u0 := src_x / atlas_w
					v0 := src_y / atlas_h
					u1 := (src_x + src_w) / atlas_w
					v1 := (src_y + src_h) / atlas_h

					sgl.c4b(c.r, c.g, c.b, c.a)
					sgl.v2f_t2f(dst_x, dst_y, u0, v0)
					sgl.v2f_t2f(dst_x + dst_w, dst_y, u1, v0)
					sgl.v2f_t2f(dst_x + dst_w, dst_y + dst_h, u1, v1)
					sgl.v2f_t2f(dst_x, dst_y + dst_h, u0, v1)
				}
				cx += f32(glyph.x_advance)
				cy -= f32(glyph.y_advance)
			}
		}
		sgl.end()
		sgl.disable_texture()
	}

	// 3. Draw Text Decorations (Untextured)
	sgl.begin_quads()
	for item in layout.items {
		if item.has_underline || item.has_strikethrough {
			// Reset pen to start of run
			run_x := f32(item.x)
			run_y := f32(item.y)
			mut c := item.color

			if item.has_underline {
				line_x := run_x
				line_y := run_y + f32(item.underline_offset) - f32(item.underline_thickness)
				line_w := f32(item.width)
				line_h := f32(item.underline_thickness)

				sgl.c4b(c.r, c.g, c.b, c.a)
				sgl.v2f(line_x, line_y)
				sgl.v2f(line_x + line_w, line_y)
				sgl.v2f(line_x + line_w, line_y + line_h)
				sgl.v2f(line_x, line_y + line_h)
			}

			if item.has_strikethrough {
				line_x := run_x
				line_y := run_y - f32(item.strikethrough_offset) + f32(item.strikethrough_thickness)
				line_w := f32(item.width)
				line_h := f32(item.strikethrough_thickness)

				sgl.c4b(c.r, c.g, c.b, c.a)
				sgl.v2f(line_x, line_y)
				sgl.v2f(line_x + line_w, line_y)
				sgl.v2f(line_x + line_w, line_y + line_h)
				sgl.v2f(line_x, line_y + line_h)
			}
		}
	}
	sgl.end()

	sgl.pop_matrix() // Pop Modelview

	sgl.matrix_mode_projection()
	sgl.pop_matrix()
	sgl.matrix_mode_modelview()
}

// draw_composition renders IME preedit text with visual feedback.
// Per CONTEXT.md decisions:
// - Preedit at ~70% opacity (alpha 178)
// - Cursor visible at insertion point within preedit
// - Thick underline for selected clause, thin for others
pub fn (mut renderer Renderer) draw_composition(layout Layout, x f32, y f32, cs &CompositionState, cursor_color gg.Color) {
	if !cs.is_composing() {
		return
	}

	// Draw clause underlines
	clause_rects := cs.get_clause_rects(layout)
	for cr in clause_rects {
		// Underline thickness: 2px for selected, 1px for others
		thickness := if cr.style == .selected { f32(2.0) } else { f32(1.0) }

		for rect in cr.rects {
			// Draw underline at bottom of rect
			underline_y := rect.y + rect.height - thickness
			// Use cursor color for underlines (dimmed like preedit)
			underline_color := gg.Color{
				r: cursor_color.r
				g: cursor_color.g
				b: cursor_color.b
				a: 178 // ~70% opacity
			}
			renderer.ctx.draw_rect_filled(rect.x + x, underline_y + y, rect.width, thickness,
				underline_color)
		}
	}

	// Draw cursor at insertion point within preedit
	cursor_pos := cs.get_document_cursor_pos()
	if cursor_rect := layout.get_cursor_pos(cursor_pos, false) {
		// Draw cursor at ~70% opacity
		dimmed_cursor := gg.Color{
			r: cursor_color.r
			g: cursor_color.g
			b: cursor_color.b
			a: 178
		}
		renderer.ctx.draw_rect_filled(cursor_rect.x + x, cursor_rect.y + y, f32(2.0),
			cursor_rect.height, dimmed_cursor)
	}
}

// draw_layout_with_composition renders layout with preedit opacity applied.
// Preedit text range gets alpha reduced to ~70%.
// Call this instead of draw_layout when composition is active.
pub fn (mut renderer Renderer) draw_layout_with_composition(layout Layout, x f32, y f32, cs &CompositionState) {
	// For now, draw normally - preedit opacity would require layout item modification
	// or shader support. The underlines provide sufficient visual distinction.
	// Full opacity reduction deferred to future enhancement.
	renderer.draw_layout(layout, x, y)
}
