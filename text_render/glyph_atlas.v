module text_render

import gg
import sokol.gfx as sg

pub struct GlyphAtlas {
pub mut:
	image      gg.Image
	width      int
	height     int
	cursor_x   int
	cursor_y   int
	row_height int
	dirty      bool
}

pub struct CachedGlyph {
pub:
	u0   f32
	v0   f32
	u1   f32
	v1   f32
	left int
	top  int
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
		image:  img
		width:  w
		height: h
	}
}

// Insert a bitmap into the atlas and return its UVs
pub fn (mut atlas GlyphAtlas) insert_bitmap(bmp Bitmap, left int, top int) CachedGlyph {
	glyph_w := bmp.width
	glyph_h := bmp.height

	// Move to next row if needed
	if atlas.cursor_x + glyph_w > atlas.width {
		atlas.cursor_x = 0
		atlas.cursor_y += atlas.row_height
		atlas.row_height = 0
	}

	if atlas.cursor_y + glyph_h > atlas.height {
		panic('GlyphAtlas full! Increase atlas size.')
	}

	copy_bitmap_to_atlas(mut atlas, bmp, atlas.cursor_x, atlas.cursor_y)
	atlas.dirty = true

	// Compute UVs
	u0 := f32(atlas.cursor_x) / f32(atlas.width)
	v0 := f32(atlas.cursor_y) / f32(atlas.height)
	u1 := f32(atlas.cursor_x + glyph_w) / f32(atlas.width)
	v1 := f32(atlas.cursor_y + glyph_h) / f32(atlas.height)

	cached := CachedGlyph{
		u0:   u0
		v0:   v0
		u1:   u1
		v1:   v1
		left: left
		top:  top
	}

	// Advance cursor
	atlas.cursor_x += glyph_w
	if glyph_h > atlas.row_height {
		atlas.row_height = glyph_h
	}

	return cached
}

fn copy_bitmap_to_atlas(mut atlas GlyphAtlas, bmp Bitmap, x int, y int) {
	row_bytes := usize(bmp.width * 4)
	unsafe {
		for row in 0 .. bmp.height {
			src_ptr := &u8(bmp.data.data) + (row * bmp.width * 4)
			dst_ptr := &u8(atlas.image.data) + ((y + row) * atlas.width + x) * 4
			vmemcpy(dst_ptr, src_ptr, row_bytes)
		}
	}
}

fn (mut renderer Renderer) load_glyph(font &Font, index u32) !CachedGlyph {
	flags := C.FT_LOAD_RENDER | C.FT_LOAD_COLOR

	if C.FT_Load_Glyph(font.ft_face, index, flags) != 0 {
		return error('FT_Load_Glyph failed')
	}

	bmp := font.ft_face.glyph.bitmap

	if bmp.buffer == 0 || bmp.width == 0 || bmp.rows == 0 {
		return CachedGlyph{} // space or empty glyph
	}

	bitmap := ft_bitmap_to_bitmap(&bmp, font)!

	return match bmp.pixel_mode == C.FT_PIXEL_MODE_BGRA {
		true {
			renderer.atlas.insert_bitmap(bitmap, 0, bitmap.height)
		}
		else {
			renderer.atlas.insert_bitmap(bitmap, int(font.ft_face.glyph.bitmap_left),
				int(font.ft_face.glyph.bitmap_top))
		}
	}
}

pub fn ft_bitmap_to_bitmap(bmp &C.FT_Bitmap, font &Font) !Bitmap {
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
			for y in 0 .. height {
				row := match bmp.pitch >= 0 {
					true { unsafe { bmp.buffer + y * bmp.pitch } }
					else { unsafe { bmp.buffer + (height - 1 - y) * (-bmp.pitch) } }
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
				row := match bmp.pitch >= 0 {
					true { unsafe { bmp.buffer + y * bmp.pitch } }
					else { unsafe { bmp.buffer + (height - 1 - y) * (-bmp.pitch) } }
				}
				for x in 0 .. width {
					byte := unsafe { row[x >> 3] }
					bit := 7 - (x & 7)
					val := if ((byte >> bit) & 1) != 0 { u8(255) } else { u8(0) }

					i := (y * width + x) * 4
					data[i + 0] = val
					data[i + 1] = val
					data[i + 2] = val
					data[i + 3] = 255
				}
			}
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
			needs_scaling := bmp.rows != font.size
			if needs_scaling {
				scale := f32(font.size) / f32(height)
				new_w := int(f32(width) * scale)
				new_h := int(f32(height) * scale)

				data = scale_bitmap_nn(data, width, height, new_w, new_h)
				width = new_w
				height = new_h
			}
		}
		else {
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

// Scale RGBA bitmap using nearest-neighbor
pub fn scale_bitmap_nn(src []u8, src_w int, src_h int, dst_w int, dst_h int) []u8 {
	mut dst := []u8{len: dst_w * dst_h * 4, init: 0}
	for y in 0 .. dst_h {
		for x in 0 .. dst_w {
			src_x := int(f32(x) * f32(src_w) / f32(dst_w))
			src_y := int(f32(y) * f32(src_h) / f32(dst_h))
			src_idx := (src_y * src_w + src_x) * 4
			dst_idx := (y * dst_w + x) * 4
			dst[dst_idx + 0] = src[src_idx + 0]
			dst[dst_idx + 1] = src[src_idx + 1]
			dst[dst_idx + 2] = src[src_idx + 2]
			dst[dst_idx + 3] = src[src_idx + 3]
		}
	}
	return dst
}
