// transform_text.v demonstrates affine matrix text transforms.
//
// Features shown:
// - Combined rotation + skew + local translation using matrix parameters
// - draw_layout_transformed API on TextSystem
//
// Run: v run examples/transform_text.v
module main

import gg
import math
import vglyph

struct TransformApp {
mut:
	gg     &gg.Context        = unsafe { nil }
	ts     &vglyph.TextSystem = unsafe { nil }
	layout vglyph.Layout
	angle  f32
}

fn main() {
	mut app := &TransformApp{}
	app.gg = gg.new_context(
		bg_color:     gg.rgb(22, 22, 26)
		width:        900
		height:       520
		window_title: 'VGlyph Matrix Transform Demo'
		init_fn:      init
		frame_fn:     frame
		user_data:    app
	)
	app.gg.run()
}

fn init(mut app TransformApp) {
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }
	app.layout = app.ts.layout_text('Matrix Transform Text', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans Bold 44'
			color:     gg.white
		}
	}) or { panic(err) }
}

fn frame(mut app TransformApp) {
	app.gg.begin()

	app.angle += 0.018
	if app.angle > math.pi * 2 {
		app.angle -= math.pi * 2
	}

	c := f32(math.cos(app.angle))
	s := f32(math.sin(app.angle))
	skew_x := f32(math.sin(app.angle * 0.55)) * 0.35
	skew_y := f32(math.cos(app.angle * 0.37)) * 0.15

	transform := vglyph.AffineTransform{
		xx: c
		xy: -s + skew_x
		yx: s + skew_y
		yy: c
		x0: f32(math.sin(app.angle * 0.9)) * 45
		y0: f32(math.cos(app.angle * 0.6)) * 18
	}

	app.ts.draw_layout_transformed(app.layout, 240, 260, transform)
	app.ts.draw_text(20, 20, 'draw_layout_transformed(layout, x, y, matrix)', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 18'
			color:     gg.rgb(190, 190, 200)
		}
	}) or {}

	app.gg.end()
	app.ts.commit()
}
