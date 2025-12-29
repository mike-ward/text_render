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

pub fn (mut r Renderer) draw_layout(layout Layout, x f32, y f32) {
	// If atlas has new glyphs, update GPU once
	if r.atlas.dirty {
		r.atlas.image.update_pixel_data(r.atlas.image.data)
		r.atlas.dirty = false
	}

	mut cx := x
	mut cy := y

	for item in layout.items {
		font_id := u64(voidptr(item.font.ft_face))

		for glyph in item.glyphs {
			key := font_id ^ (u64(glyph.index) << 32)

			// Load glyph into atlas if not cached
			if key !in r.cache {
				cg := r.load_glyph(item.font, glyph.index) or {
					// fallback blank glyph
					CachedGlyph{
						u0:   0
						v0:   0
						u1:   0
						v1:   0
						left: 0
						top:  0
					}
				}
				r.cache[key] = cg
			}

			cg := r.cache[key] or { continue }

			// Compute draw position
			draw_x := cx + f32(glyph.x_offset) + f32(cg.left)
			draw_y := cy - f32(glyph.y_offset) - f32(cg.top)

			glyph_w := f32((cg.u1 - cg.u0) * f32(r.atlas.width))
			glyph_h := f32((cg.v1 - cg.v0) * f32(r.atlas.height))

			// Destination and source rects
			dst := gg.Rect{
				x:      draw_x
				y:      draw_y
				width:  glyph_w
				height: glyph_h
			}
			src := gg.Rect{
				x:      cg.u0 * f32(r.atlas.width)
				y:      cg.v0 * f32(r.atlas.height)
				width:  (cg.u1 - cg.u0) * f32(r.atlas.width)
				height: (cg.v1 - cg.v0) * f32(r.atlas.height)
			}

			if cg.u0 != cg.u1 && cg.v0 != cg.v1 {
				r.ctx.draw_image_part(dst, src, &r.atlas.image)
			}

			// Advance cursor
			cx += f32(glyph.x_advance)
			cy -= f32(glyph.y_advance)
		}

		// r.ctx.draw_image(10, 100, 1024, 1024, r.atlas.image)
	}
}
