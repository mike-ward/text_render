module vglyph

import math

const transform_epsilon = f32(0.0001)

fn near(a f32, b f32) bool {
	return f32(math.abs(a - b)) < transform_epsilon
}

fn test_affine_identity() {
	t := affine_identity()
	assert t.xx == 1.0
	assert t.xy == 0.0
	assert t.yx == 0.0
	assert t.yy == 1.0
	assert t.x0 == 0.0
	assert t.y0 == 0.0

	x, y := t.apply(3.5, -2.0)
	assert near(x, 3.5)
	assert near(y, -2.0)
}

fn test_affine_rotation_quarter_turn() {
	t := affine_rotation(f32(math.pi) * 0.5)
	x, y := t.apply(1.0, 0.0)
	assert near(x, 0.0)
	assert near(y, 1.0)
}

fn test_affine_translation() {
	t := affine_translation(5.0, -2.0)
	x, y := t.apply(3.0, 4.0)
	assert near(x, 8.0)
	assert near(y, 2.0)
}

fn test_affine_skew() {
	t := affine_skew(0.5, -0.25)
	x, y := t.apply(4.0, 2.0)
	assert near(x, 5.0)
	assert near(y, 1.0)
}
