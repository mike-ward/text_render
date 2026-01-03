module text_render

import gg

pub struct Bitmap {
pub:
	width    int
	height   int
	channels int
	data     []u8
}

pub struct Renderer {
mut:
	ctx   &gg.Context
	atlas GlyphAtlas
	cache map[u64]CachedGlyph
}

pub fn new_renderer(mut ctx gg.Context) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, 1024, 1024) // 1024x1024 default atlas
	return &Renderer{
		ctx:   ctx
		atlas: atlas
		cache: map[u64]CachedGlyph{}
	}
}

pub fn new_renderer_atlas_size(mut ctx gg.Context, width int, height int) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, width, height)
	return &Renderer{
		ctx:   ctx
		atlas: atlas
		cache: map[u64]CachedGlyph{}
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

		for glyph in item.glyphs {
			key := font_id ^ (u64(glyph.index) << 32)

			cg := renderer.cache[key] or {
				cached_glyph := renderer.load_glyph(item.ft_face, glyph.index) or {
					CachedGlyph{} // fallback blank glyph
				}
				renderer.cache[key] = cached_glyph
				cached_glyph
			}

			// Compute draw position (relative to pen position)
			// cg.left is bitmap_left
			// cg.top is bitmap_top
			draw_x := cx + f32(glyph.x_offset) + f32(cg.left)
			draw_y := cy - f32(glyph.y_offset) - f32(cg.top)

			glyph_w := f32((cg.u1 - cg.u0) * f32(renderer.atlas.width))
			glyph_h := f32((cg.v1 - cg.v0) * f32(renderer.atlas.height))

			// Draw image from glyph atlas
			if cg.u0 != cg.u1 && cg.v0 != cg.v1 {
				dst := gg.Rect{
					x:      draw_x
					y:      draw_y
					width:  glyph_w
					height: glyph_h
				}
				src := gg.Rect{
					x:      cg.u0 * f32(renderer.atlas.width)
					y:      cg.v0 * f32(renderer.atlas.height)
					width:  (cg.u1 - cg.u0) * f32(renderer.atlas.width)
					height: (cg.v1 - cg.v0) * f32(renderer.atlas.height)
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
				line_y := run_y + f32(item.underline_offset) // item.underline_offset is (+) for below
				line_w := f32(item.width)
				line_h := f32(item.underline_thickness)

				renderer.ctx.draw_rect_filled(line_x, line_y, line_w, line_h, item.color)
			}

			if item.has_strikethrough {
				line_x := run_x
				line_y := run_y - f32(item.strikethrough_offset)
				line_w := f32(item.width)
				line_h := f32(item.strikethrough_thickness)

				renderer.ctx.draw_rect_filled(line_x, line_y, line_w, line_h, item.color)
			}
		}
	}
}

// max_visual_height calculates total vertical space from rendered glyphs
// (Ink extents). Use for tight stacking. Pango provides logical height (`line_height * num_lines`).
// Captures true visual bottom for Emojis/script fonts extending beyond line height.
//
// Algorithm:
// Iterates glyphs, computes bottom Y (baseline + y_bearing + height), returns max.
pub fn (mut renderer Renderer) max_visual_height(layout Layout) f32 {
	// Pango sets layout height based on content.
	// But we can also compute the bounding box of glyphs to be sure.
	// However, since we now have multi-line, "max visual height" is essentially the total height.
	// Iterate to find max Y bottom.

	mut max_y := f32(0)
	mut min_y := f32(0) // Usually 0 or negative if something sticks out top?

	for item in layout.items {
		// item.y is baseline.
		// approximate top/bottom from font height?
		// Better: check glyphs.
		font_id := u64(voidptr(item.ft_face))
		base_y := f32(item.y)

		for glyph in item.glyphs {
			// Resolve cache to get bitmap size
			key := font_id ^ (u64(glyph.index) << 32)
			// We can skip loading if not cached, just estimating?
			// But for accurate height we might needs metrics.
			// Let's rely on cache if present, otherwise ignore?
			// Actually, let's just use what's loaded or maybe return pango logical height if we had it.
			// For now, let's compute based on what we find.
			if key in renderer.cache {
				cg := renderer.cache[key]

				// Draw Y top = base_y - y_offset - bitmap_top
				// Draw Y bottom = Draw Y top + height

				glyph_top := base_y - f32(glyph.y_offset) - f32(cg.top)
				glyph_h := (cg.v1 - cg.v0) * f32(renderer.atlas.height)
				glyph_bottom := glyph_top + glyph_h

				if glyph_bottom > max_y {
					max_y = glyph_bottom
				}
			}
		}
	}

	// If no glyphs loaded yet, might result in small height, but that's okay for transient frames.
	// This function is mostly for stacking layouts.
	return max_y - min_y
}
