module text_render

import gg
import sokol.gfx as sg

// ---------------- Glyph Atlas ----------------

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
	img.id = ctx.cache_image(img) // must pass mut img

	// Allocate CPU-side buffer
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

	// Copy pixels into CPU buffer
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
	for row in 0 .. bmp.height {
		for col in 0 .. bmp.width {
			src_idx := (row * bmp.width + col) * 4
			dst_idx := ((y + row) * atlas.width + (x + col)) * 4
			unsafe {
				&u8(atlas.image.data)[dst_idx + 0] = bmp.data[src_idx + 0]
				&u8(atlas.image.data)[dst_idx + 1] = bmp.data[src_idx + 1]
				&u8(atlas.image.data)[dst_idx + 2] = bmp.data[src_idx + 2]
				&u8(atlas.image.data)[dst_idx + 3] = bmp.data[src_idx + 3]
			}
		}
	}
}
