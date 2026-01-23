module vglyph

import gg
import math
import sokol.sgl
import sokol.gfx as sg

pub struct Bitmap {
pub:
	width    int
	height   int
	channels int
	data     []u8
}

pub struct Renderer {
mut:
	ctx          &gg.Context
	atlas        GlyphAtlas
	sampler      sg.Sampler
	cache        map[u64]CachedGlyph
	scale_factor f32 = 1.0
	scale_inv    f32 = 1.0
}

pub fn new_renderer(mut ctx gg.Context, scale_factor f32) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, 1024, 1024) // 1024x1024 default atlas
	return &Renderer{
		ctx:          ctx
		atlas:        atlas
		sampler:      create_linear_sampler()
		cache:        map[u64]CachedGlyph{}
		scale_factor: scale_factor
		scale_inv:    1.0 / scale_factor
	}
}

pub fn new_renderer_atlas_size(mut ctx gg.Context, width int, height int, scale_factor f32) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, width, height)
	return &Renderer{
		ctx:          ctx
		atlas:        atlas
		sampler:      create_linear_sampler()
		cache:        map[u64]CachedGlyph{}
		scale_factor: scale_factor
		scale_inv:    1.0 / scale_factor
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
	if renderer.atlas.dirty {
		renderer.atlas.image.update_pixel_data(renderer.atlas.image.data)
		renderer.atlas.dirty = false
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
	// Item.y is BASELINE y. Draw relative to x + item.x, y + item.y.

	// Cleanup old atlas textures from previous frames
	renderer.atlas.cleanup(renderer.ctx.frame)

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
			bin := int(frac_x * 4.0 + 0.1) & 3 // +0.1 for float safety

			// Key includes the bin
			// (glyph.index << 2) | bin
			// Logic now handled in get_or_load_glyph

			cg := renderer.get_or_load_glyph(item, glyph, bin) or {
				CachedGlyph{} // fallback blank glyph
			}

			// Compute final draw position
			// Y is still pixel-snapped (Bin 0 equivalent) to preserve baseline sharpness
			phys_origin_y := (cy - f32(glyph.y_offset)) * scale
			draw_origin_y := math.round(phys_origin_y) // Bin 0

			// cg.left / cg.top are the bitmap offsets from origin (in physical pixels)
			// draw_x/y are logical coordinates for gg

			scale_inv := renderer.scale_inv
			draw_x := (f32(draw_origin_x) + f32(cg.left)) * scale_inv
			draw_y := (f32(draw_origin_y) - f32(cg.top)) * scale_inv

			glyph_w := f32(cg.width) * scale_inv
			glyph_h := f32(cg.height) * scale_inv

			// Draw image from glyph atlas
			if cg.width > 0 && cg.height > 0 {
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
					img:       &renderer.atlas.image
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

// get_atlas_height returns the current height of the internal glyph atlas.
pub fn (renderer &Renderer) get_atlas_height() int {
	return renderer.atlas.height
}

// debug_insert_bitmap manually inserts a bitmap into the atlas.
// This is primarily for debugging atlas resizing behavior.
pub fn (mut renderer Renderer) debug_insert_bitmap(bmp Bitmap, left int, top int) !CachedGlyph {
	cached, _ := renderer.atlas.insert_bitmap(bmp, left, top)!
	return cached
}

// get_or_load_glyph retrieves a glyph from the cache or loads it from FreeType.
fn (mut renderer Renderer) get_or_load_glyph(item Item, glyph Glyph, bin int) !CachedGlyph {
	font_id := u64(voidptr(item.ft_face))

	// Key includes the bin
	// We shift the index left by 2 bits to make room for 2 bits of bin.
	// (glyph.index << 2) | bin
	index_with_bin := (u64(glyph.index) << 2) | u64(bin)
	key := font_id ^ (index_with_bin << 32)

	if key in renderer.cache {
		return renderer.cache[key]
	}

	target_h := int(f32(item.ascent) * renderer.scale_factor)
	cached_glyph := renderer.load_glyph(LoadGlyphConfig{
		face:          item.ft_face
		index:         glyph.index
		target_height: target_h
		subpixel_bin:  bin
	})!

	renderer.cache[key] = cached_glyph
	return cached_glyph
}

// draw_layout_rotated draws the layout rotated by `angle` (in radians) around its origin.
pub fn (mut renderer Renderer) draw_layout_rotated(layout Layout, x f32, y f32, angle f32) {
	// Cleanup old atlas textures from previous frames
	renderer.atlas.cleanup(renderer.ctx.frame)

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

	// 2. Draw Glyphs (Textured)
	sgl.enable_texture()
	sgl.texture(renderer.atlas.image.simg, renderer.sampler)
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
			glyph := layout.glyphs[i]
			if (glyph.index & pango_glyph_unknown_flag) != 0 {
				continue
			}

			gx := cx + f32(glyph.x_offset)
			gy := cy - f32(glyph.y_offset)

			// Load Glyph (Bin 0)
			cg := renderer.get_or_load_glyph(item, glyph, 0) or { CachedGlyph{} }

			if cg.width > 0 && cg.height > 0 {
				scale_inv := renderer.scale_inv

				dst_x := gx + f32(cg.left) * scale_inv
				dst_y := gy - f32(cg.top) * scale_inv
				dst_w := f32(cg.width) * scale_inv
				dst_h := f32(cg.height) * scale_inv

				atlas_w := f32(renderer.atlas.width)
				atlas_h := f32(renderer.atlas.height)

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
