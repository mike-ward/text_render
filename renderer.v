module vglyph

import gg
import math

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
	cache        map[u64]CachedGlyph
	scale_factor f32 = 1.0
	scale_inv    f32 = 1.0
}

pub fn new_renderer(mut ctx gg.Context, scale_factor f32) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, 1024, 1024) // 1024x1024 default atlas
	return &Renderer{
		ctx:          ctx
		atlas:        atlas
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
		cache:        map[u64]CachedGlyph{}
		scale_factor: scale_factor
		scale_inv:    1.0 / scale_factor
	}
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
		font_id := u64(voidptr(item.ft_face))

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
			// We shift the index left by 2 bits to make room for 2 bits of bin.
			// (glyph.index << 2) | bin
			index_with_bin := (u64(glyph.index) << 2) | u64(bin)
			key := font_id ^ (index_with_bin << 32)

			cg := renderer.cache[key] or {
				// Calculate target height for this glyph run
				target_h := int(f32(item.ascent) * renderer.scale_factor)
				cached_glyph := renderer.load_glyph(LoadGlyphConfig{
					face:          item.ft_face
					index:         glyph.index
					target_height: target_h
					subpixel_bin:  bin
				}) or {
					CachedGlyph{} // fallback blank glyph
				}
				renderer.cache[key] = cached_glyph
				cached_glyph
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
