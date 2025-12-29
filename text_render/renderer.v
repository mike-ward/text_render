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

pub fn (mut renderer Renderer) draw_layout(layout Layout, x f32, y f32) {
	// If atlas has new glyphs, update GPU once
	if renderer.atlas.dirty {
		renderer.atlas.image.update_pixel_data(renderer.atlas.image.data)
		renderer.atlas.dirty = false
	}

	mut cx := x
	mut cy := y

	for item in layout.items {
		font_id := u64(voidptr(item.font.ft_face))

		for glyph in item.glyphs {
			key := font_id ^ (u64(glyph.index) << 32)

			cg := renderer.cache[key] or {
				lg := renderer.load_glyph(item.font, glyph.index) or {
					CachedGlyph{} // fallback blank glyph
				}
				renderer.cache[key] = lg
				lg
			}

			// Compute draw position
			draw_x := cx + f32(glyph.x_offset) + f32(cg.left)
			draw_y := cy - f32(glyph.y_offset) - f32(cg.top)

			glyph_w := f32((cg.u1 - cg.u0) * f32(renderer.atlas.width))
			glyph_h := f32((cg.v1 - cg.v0) * f32(renderer.atlas.height))

			// Destination and source rects
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

			if cg.u0 != cg.u1 && cg.v0 != cg.v1 {
				renderer.ctx.draw_image_part(dst, src, &renderer.atlas.image)
			}

			// Advance cursor
			cx += f32(glyph.x_advance)
			cy -= f32(glyph.y_advance)
		}

		// r.ctx.draw_image(10, 100, 1024, 1024, r.atlas.image)
	}
}
