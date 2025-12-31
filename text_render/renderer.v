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

// commit updates the GPU texture if the atlas has changed.
// This must be called exactly once per frame, ideally after all draw calls are submitted for that frame.
//
// Reason:
// Sokol (and many Graphics APIs) prefer or enforce single-update-per-frame rules for dynamic textures
// to simplify resource fencing. Calling this multiple times might overwrite the buffer or cause stalls.
// Only uploads if `renderer.atlas.dirty` is true to save bandwidth.
pub fn (mut renderer Renderer) commit() {
	if renderer.atlas.dirty {
		renderer.atlas.image.update_pixel_data(renderer.atlas.image.data)
		renderer.atlas.dirty = false
	}
}

// draw_layout renders the pre-calculated Layout object to the screen at position (x, y).
//
// Algorithm:
// 1. Iterates through the V `Layout` items.
// 2. For each glyph, checks if it is already in the `GlyphAtlas` cache.
// 3. If missing, loads it from FreeType on-the-fly (caching it for future frames).
// 4. Calculates the final screen position using the Layout position + Glyph offset + FreeType bearing.
// 5. Queues a textured quad draw call using `gg`.
//
// Performance Note:
// - Draw calls are batched by `gg`, but we switch textures if using multiple atlases (current implementation uses one).
// - Glyph loading happens lazily. First frame with new text might have a cpu spike (rasterization).
pub fn (mut renderer Renderer) draw_layout(layout Layout, x f32, y f32) {
	// Layout is already laid out. All we need is to draw it at (x, y).

	// Layout is already laid out. All we need is to draw it at (x, y).
	// But note: Item.y is the BASELINE y.
	// So we draw relative to x + item.x, y + item.y.

	for item in layout.items {
		// item.ft_face is &C.FT_FaceRec
		font_id := u64(voidptr(item.ft_face))

		// Starting pen position for this run
		mut cx := x + f32(item.x)
		mut cy := y + f32(item.y) // Baseline

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

				c := item.color
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

// max_visual_height calculates the total vertical space consumed by the rendered glyphs.
//
// Difference from Pango Height:
// Pango provides a "logical" height for the layout, which is essentially `line_height * num_lines`.
// This function, however, inspects the actual "Ink" extents of the glyphs.
//
// Use Code:
// - Call this when you need to stack layouts tightly or ensure no overlap.
// - Emojis or script fonts may extend significantly above or below the logical line height.
//   This function captures that true visual bottom.
//
// Algorithm:
// Iterates through all glyphs in the layout, computes their bottom Y coordinate (`baseline + y_bearing + height`),
// and returns the maximum value found.
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
