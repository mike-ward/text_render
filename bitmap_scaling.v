module vglyph

import math

// cubic_hermite calculates the interpolated value using the Catmull-Rom spline.
// p1 is the value at t=0, p2 is the value at t=1.
// p0 and p3 are the surrounding points.
fn cubic_hermite(p0 f32, p1 f32, p2 f32, p3 f32, t f32) f32 {
	a := -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3
	b := p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3
	c := -0.5 * p0 + 0.5 * p2
	d := p1

	return a * t * t * t + b * t * t + c * t + d
}

// get_pixel_rgba_premul retrieves a pixel from the source bitmap and returns
// it as 4 floats (R, G, B, A) with the RGB channels multiplied by the Alpha.
// This is essential for correct interpolation of transparent edges.
fn get_pixel_rgba_premul(src []u8, w int, h int, x int, y int) (f32, f32, f32, f32) {
	if w <= 0 || h <= 0 {
		return 0, 0, 0, 0
	}
	cx := if x < 0 {
		0
	} else if x >= w {
		w - 1
	} else {
		x
	}
	cy := if y < 0 {
		0
	} else if y >= h {
		h - 1
	} else {
		y
	}
	idx := (cy * w + cx) * 4

	// Bounds check before array access
	if idx < 0 || idx + 3 >= src.len {
		return 0, 0, 0, 0
	}

	r := f32(src[idx + 0])
	g := f32(src[idx + 1])
	b := f32(src[idx + 2])
	a := f32(src[idx + 3])

	// Premultiply
	// Note: a is 0-255, so we divide by 255 to get the factor
	alpha_factor := a / 255.0
	return r * alpha_factor, g * alpha_factor, b * alpha_factor, a
}

// Scale RGBA bitmap using bicubic interpolation (Catmull-Rom spline)
// with premultiplied alpha to avoid edge artifacts.
pub fn scale_bitmap_bicubic(src []u8, src_w int, src_h int, dst_w int, dst_h int) []u8 {
	// Validate dimensions
	if dst_w <= 0 || dst_h <= 0 || src_w <= 0 || src_h <= 0 {
		return []u8{}
	}
	dst_size := i64(dst_w) * i64(dst_h) * 4
	if dst_size > max_i32 || dst_size <= 0 {
		return []u8{} // Size overflow
	}

	mut dst := []u8{len: int(dst_size), init: 0}

	x_scale := f32(src_w) / f32(dst_w)
	y_scale := f32(src_h) / f32(dst_h)

	for y in 0 .. dst_h {
		src_y := f32(y) * y_scale
		y0 := int(src_y)
		y_diff := src_y - f32(y0)

		for x in 0 .. dst_w {
			src_x := f32(x) * x_scale
			x0 := int(src_x)
			x_diff := src_x - f32(x0)

			dst_idx := (y * dst_w + x) * 4

			// Arrays to hold the 16 samples for each channel
			// Rows first, then reduce to 1 column
			mut col_r := [f32(0.0), 0.0, 0.0, 0.0]
			mut col_g := [f32(0.0), 0.0, 0.0, 0.0]
			mut col_b := [f32(0.0), 0.0, 0.0, 0.0]
			mut col_a := [f32(0.0), 0.0, 0.0, 0.0]

			// Interpolate horizontally for all 4 rows in the neighborhood
			for i in -1 .. 3 {
				row_y := y0 + i

				// Fetch 4 horizontal pixels
				r0, g0, b0, a0 := get_pixel_rgba_premul(src, src_w, src_h, x0 - 1, row_y)
				r1, g1, b1, a1 := get_pixel_rgba_premul(src, src_w, src_h, x0 + 0, row_y)
				r2, g2, b2, a2 := get_pixel_rgba_premul(src, src_w, src_h, x0 + 1, row_y)
				r3, g3, b3, a3 := get_pixel_rgba_premul(src, src_w, src_h, x0 + 2, row_y)

				col_r[i + 1] = cubic_hermite(r0, r1, r2, r3, x_diff)
				col_g[i + 1] = cubic_hermite(g0, g1, g2, g3, x_diff)
				col_b[i + 1] = cubic_hermite(b0, b1, b2, b3, x_diff)
				col_a[i + 1] = cubic_hermite(a0, a1, a2, a3, x_diff)
			}

			// Interpolate vertically
			mut final_r := cubic_hermite(col_r[0], col_r[1], col_r[2], col_r[3], y_diff)
			mut final_g := cubic_hermite(col_g[0], col_g[1], col_g[2], col_g[3], y_diff)
			mut final_b := cubic_hermite(col_b[0], col_b[1], col_b[2], col_b[3], y_diff)
			mut final_a := cubic_hermite(col_a[0], col_a[1], col_a[2], col_a[3], y_diff)

			// Clamp alpha first (branchless)
			final_a = f32(math.clamp(final_a, 0.0, 255.0))

			// Un-premultiply
			if final_a > 0.0 {
				alpha_factor := 255.0 / final_a
				final_r *= alpha_factor
				final_g *= alpha_factor
				final_b *= alpha_factor
			}

			// Clamp RGB (branchless)
			final_r = f32(math.clamp(final_r, 0.0, 255.0))
			final_g = f32(math.clamp(final_g, 0.0, 255.0))
			final_b = f32(math.clamp(final_b, 0.0, 255.0))

			dst[dst_idx + 0] = u8(final_r)
			dst[dst_idx + 1] = u8(final_g)
			dst[dst_idx + 2] = u8(final_b)
			dst[dst_idx + 3] = u8(final_a)
		}
	}
	return dst
}
