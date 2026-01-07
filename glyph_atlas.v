module vglyph

import gg
import sokol.gfx as sg
import log
import math

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
	x      int
	y      int
	width  int
	height int
	left   int
	top    int
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

fn (mut renderer Renderer) load_glyph(ft_face &C.FT_FaceRec, index u32) !CachedGlyph {
	// FT_LOAD_TARGET_LIGHT forces auto-hinting with a lighter touch,
	// which usually looks better on screens than FULL hinting (too distorted)
	// or NO hinting (too blurry).
	//
	// Use V constant for FT_LOAD_TARGET_LIGHT because the C macro is complex
	// and not automatically exposed by V's C-interop.
	flags := C.FT_LOAD_RENDER | C.FT_LOAD_COLOR | ft_load_target_light

	if C.FT_Load_Glyph(ft_face, index, flags) != 0 {
		if index != 0xfffffff {
			log.error('${@FILE_LINE}: FT_Load_Glyph failed 0x${index:x}')
		}
		return error('FT_Load_Glyph failed')
	}

	glyph := ft_face.glyph
	ft_bitmap := glyph.bitmap

	if ft_bitmap.buffer == 0 || ft_bitmap.width == 0 || ft_bitmap.rows == 0 {
		return CachedGlyph{} // space or empty glyph
	}

	bitmap := ft_bitmap_to_bitmap(&ft_bitmap, ft_face)!

	return match int(ft_bitmap.pixel_mode) {
		C.FT_PIXEL_MODE_BGRA { renderer.atlas.insert_bitmap(bitmap, 0, bitmap.height) }
		else { renderer.atlas.insert_bitmap(bitmap, int(glyph.bitmap_left), int(glyph.bitmap_top)) }
	}
}

// ft_bitmap_to_bitmap converts a raw FreeType bitmap (GRAY, MONO, or BGRA) into
// a uniform 32-bit RGBA `Bitmap`.
//
// Supported Modes:
// - **GRAY (Grayscale)**: Common for anti-aliased text. Sets RGB=White (255)
//   and Alpha=GrayLevel, allowing tinting via vertex color.
// - **MONO (1-bit)**: Used for pixel fonts or non-AA rendering. Expands 1 bit
//   to full integer 0 or 255 alpha.
// - **BGRA (Color Bitmap)**: Used for Emoji fonts (e.g., Apple Color Image).
//   Preserves colors exactly.
//   Important: Scales bitmap if size doesn't match target PPEM (size).
pub fn ft_bitmap_to_bitmap(bmp &C.FT_Bitmap, ft_face &C.FT_FaceRec) !Bitmap {
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
					// Gamma Correction
					// Linear blending of non-linear alpha values results in "spindly" text (too light).
					// Standard monitors are ~2.2 gamma.
					// Correct the alpha: alpha' = pow(alpha, 1.0/2.2)
					alpha_norm := f64(v) / 255.0 // Normalize 0-255 to 0.0-1.0
					// Apply Gamma 1.0/2.2 ~ 0.4545
					// 0.6545 looks better to me - mrw
					corrected_alpha := math.pow(alpha_norm, 0.6545)
					val := u8(corrected_alpha * 255.0)

					i := (y * width + x) * 4
					data[i + 0] = 255
					data[i + 1] = 255
					data[i + 2] = 255
					data[i + 3] = val
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

			// Calculate target size (in pixels)
			// Use the font's ascender height if available. This ensures that static bitmaps (like emojis)
			// are scaled to match the visual cap-height/ascender of the text, rather than the full
			// line height (which includes descenders and gap).
			y_ppem := int(ft_face.size.metrics.y_ppem)
			ascender := int(ft_face.size.metrics.ascender) >> 6 // 26.6 fixed point to pixels

			target_size := if ascender > 0 && ascender < y_ppem {
				ascender
			} else {
				y_ppem
			}
			needs_scaling := bmp.rows != target_size
			if needs_scaling && target_size > 0 {
				scale := f32(target_size) / f32(height)
				new_w := int(f32(width) * scale)
				new_h := int(f32(height) * scale)

				data = scale_bitmap_nn(data, width, height, new_w, new_h)
				width = new_w
				height = new_h
			}
		}
		else {
			log.error('${@FILE_LINE}: Unsupported FT pixel mode: ${bmp.pixel_mode}')
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

// insert_bitmap places a bitmap into the atlas using a simple specialized
// shelf-packing algorithm.
//
// Algorithm:
// - Fills rows from left to right.
// - When a row is full, moves to the next row based on current row height.
// - Does not rotate or optimize heavily; glyphs are generally uniform height.
//
// Returns the UV coordinates and bearing info for the cached glyph.
pub fn (mut atlas GlyphAtlas) insert_bitmap(bmp Bitmap, left int, top int) !CachedGlyph {
	glyph_w := bmp.width
	glyph_h := bmp.height

	// Move to next row if needed
	if atlas.cursor_x + glyph_w > atlas.width {
		atlas.cursor_x = 0
		atlas.cursor_y += atlas.row_height
		atlas.row_height = 0
	}

	if atlas.cursor_y + glyph_h > atlas.height {
		// Linear doubling of height
		new_height := if atlas.height == 0 { 1024 } else { atlas.height * 2 }
		atlas.grow(new_height)
	}

	copy_bitmap_to_atlas(mut atlas, bmp, atlas.cursor_x, atlas.cursor_y)
	atlas.dirty = true

	// Compute UVs
	cached := CachedGlyph{
		x:      atlas.cursor_x
		y:      atlas.cursor_y
		width:  glyph_w
		height: glyph_h
		left:   left
		top:    top
	}

	// Advance cursor
	atlas.cursor_x += glyph_w
	if glyph_h > atlas.row_height {
		atlas.row_height = glyph_h
	}

	return cached
}

pub fn (mut atlas GlyphAtlas) grow(new_height int) {
	if new_height <= atlas.height {
		return
	}
	log.info('Growing glyph atlas from ${atlas.height} to ${new_height}')

	old_size := atlas.width * atlas.height * 4
	new_size := atlas.width * new_height * 4

	mut new_data := unsafe { malloc(new_size) }

	// Copy old data
	unsafe {
		vmemcpy(new_data, atlas.image.data, old_size)
		// Zero out the new part (optional, but good for debugging)
		// Pointer arithmetic must be done carefully
		dest_ptr := &u8(new_data) + old_size
		vmemset(dest_ptr, 0, new_size - old_size)
		free(atlas.image.data)
	}
	atlas.image.data = new_data
	atlas.height = new_height
	atlas.image.height = new_height

	// Re-create Sokol image with new size
	// Note: We're replacing the underlying sokol image entirely.
	// This might be expensive, but it happens rarely.
	sg.destroy_image(atlas.image.simg)

	desc := sg.ImageDesc{
		width:        atlas.width
		height:       new_height
		pixel_format: .rgba8
		usage:        .dynamic
	}
	atlas.image.simg = sg.make_image(&desc)
	atlas.dirty = true // Force upload
}

fn copy_bitmap_to_atlas(mut atlas GlyphAtlas, bmp Bitmap, x int, y int) {
	row_bytes := usize(bmp.width * 4)
	for row in 0 .. bmp.height {
		unsafe {
			src_ptr := &u8(bmp.data.data) + (row * bmp.width * 4)
			dst_ptr := &u8(atlas.image.data) + ((y + row) * atlas.width + x) * 4
			vmemcpy(dst_ptr, src_ptr, row_bytes)
		}
	}
}
