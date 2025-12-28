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
	mut cx := x
	mut cy := y

	if r.atlas.dirty {
		r.atlas.image.update_pixel_data(r.atlas.image.data)
		r.atlas.dirty = false
	}

	for item in layout.items {
		font_id := u64(voidptr(item.font.ft_face))

		for glyph in item.glyphs {
			key := font_id ^ (u64(glyph.index) << 32)

			// Load glyph into atlas if not cached
			if key !in r.cache {
				cg := r.load_glyph(item.font, glyph.index) or { continue }
				r.cache[key] = cg
			}

			cg := r.cache[key] or { continue }

			// Compute position
			draw_x := cx + f32(glyph.x_offset) + f32(cg.left)
			draw_y := cy - f32(glyph.y_offset) - f32(cg.top)

			glyph_w := f32((cg.u1 - cg.u0) * f32(r.atlas.width))
			glyph_h := f32((cg.v1 - cg.v0) * f32(r.atlas.height))

			// Draw from atlas using UVs
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

			r.ctx.draw_rect_empty(dst.x, dst.y, dst.width, dst.height, gg.blue)

			if cg.u0 != cg.u1 && cg.v0 != cg.v1 {
				r.ctx.draw_image_part(dst, src, &r.atlas.image)
			}

			// Advance cursor
			cx += f32(glyph.x_advance)
			cy -= f32(glyph.y_advance)
		}
	}
}

// Load a glyph, render to bitmap, insert into atlas, and return UVs
fn (mut r Renderer) load_glyph(font &Font, index u32) !CachedGlyph {
	if C.FT_Load_Glyph(font.ft_face, index, 0) != 0 {
		return CachedGlyph{}
	}

	if font.ft_face.glyph.bitmap.width == 0 || font.ft_face.glyph.bitmap.rows == 0 {
		// No bitmap, but still a valid glyph (space, tabs, etc.)
		return CachedGlyph{
			u0:   0
			v0:   0
			u1:   0
			v1:   0
			left: int(font.ft_face.glyph.bitmap_left)
			top:  int(font.ft_face.glyph.bitmap_top)
		}
	}

	C.FT_Render_Glyph(font.ft_face.glyph, C.ft_render_mode_normal)

	bitmap := font.ft_face.glyph.bitmap
	ft_bmp := ft_bitmap_to_bitmap(&bitmap)!

	cached := r.atlas.insert_bitmap(ft_bmp, int(font.ft_face.glyph.bitmap_left), int(font.ft_face.glyph.bitmap_top))
	return cached
}

// Convert FreeType FT_Bitmap → RGBA bitmap
pub fn ft_bitmap_to_bitmap(bmp &C.FT_Bitmap) !Bitmap {
	if bmp.buffer == 0 || bmp.width == 0 || bmp.rows == 0 {
		return error('Empty bitmap')
	}

	width := int(bmp.width)
	height := int(bmp.rows)
	channels := 4
	mut data := []u8{len: width * height * channels, init: 0}

	match bmp.pixel_mode {
		u8(C.FT_PIXEL_MODE_GRAY) {
			for y in 0 .. height {
				row := if bmp.pitch >= 0 {
					unsafe { bmp.buffer + y * bmp.pitch }
				} else {
					unsafe { bmp.buffer + (height - 1 - y) * (-bmp.pitch) }
				}
				for x in 0 .. width {
					v := unsafe { row[x] }
					i := (y * width + x) * 4
					data[i + 0] = 255
					data[i + 1] = 255
					data[i + 2] = 255
					data[i + 3] = v
				}
			}
		}
		u8(C.FT_PIXEL_MODE_MONO) {
			for y in 0 .. height {
				row := if bmp.pitch >= 0 {
					unsafe { bmp.buffer + y * bmp.pitch }
				} else {
					unsafe { bmp.buffer + (height - 1 - y) * (-bmp.pitch) }
				}
				for x in 0 .. width {
					byte := unsafe { row[x >> 3] }
					bit := 7 - (x & 7)
					on := (byte >> bit) & 1
					val := if on == 1 { u8(255) } else { u8(0) }

					i := (y * width + x) * 4
					data[i + 0] = val
					data[i + 1] = val
					data[i + 2] = val
					data[i + 3] = 255
				}
			}
		}
		else {
			// fallback for unsupported formats
			println('Warning: unsupported pixel_mode=${bmp.pixel_mode}, using blank glyph')
			return Bitmap{
				width:    width
				height:   height
				channels: channels
				data:     data
			}
		}
	}

	return Bitmap{
		width:    width
		height:   height
		channels: channels
		data:     data
	}
}
