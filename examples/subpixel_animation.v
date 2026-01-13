module main

import vglyph
import gg
import sokol.sapp
import math

const win_width = 800
const win_height = 400

struct SubpixelApp {
mut:
	ctx         &gg.Context      = unsafe { nil }
	text_system &vglyph.Context  = unsafe { nil }
	renderer    &vglyph.Renderer = unsafe { nil }
	x_pos       f32
}

fn main() {
	mut app := &SubpixelApp{}
	app.ctx = gg.new_context(
		bg_color:     gg.white
		width:        win_width
		height:       win_height
		window_title: 'Subpixel Positioning Animation'
		frame_fn:     frame
		init_fn:      init
		user_data:    app
	)
	app.ctx.run()
}

fn init(mut app SubpixelApp) {
	scale := sapp.dpi_scale()
	app.text_system = vglyph.new_context(scale) or { panic(err) }
	app.renderer = vglyph.new_renderer(mut app.ctx, scale)
}

fn frame(mut app SubpixelApp) {
	app.ctx.begin()
	app.draw()
	app.ctx.end()
	app.renderer.commit()

	// Animate slowly (0.2 pixels per frame)
	app.x_pos += 0.02
	if app.x_pos > 100.0 {
		app.x_pos = 0.0
	}
}

fn (mut app SubpixelApp) draw() {
	start_x := 50.0 + app.x_pos

	// 1. Subpixel Positioned (Smooth)
	cfg := vglyph.TextConfig{
		font_name: 'Sans 24'
		color:     gg.black
	}
	text := 'Smooth Subpixel Motion'
	layout := app.text_system.layout_text(text, cfg) or { panic(err) }

	app.renderer.draw_layout(layout, f32(start_x), 100.0)

	// 2. Integer Snapped (Jittery / Old Behavior)
	// We manually round the position to simulate the old renderer behavior
	snapped_x := math.round(start_x)
	layout2 := app.text_system.layout_text('Integer Snapped Motion', cfg) or { panic(err) }

	app.renderer.draw_layout(layout2, f32(snapped_x), 200.0)

	// Instructions
	info_cfg := vglyph.TextConfig{
		font_name: 'Sans 14'
		color:     gg.gray
	}
	info_layout := app.text_system.layout_text('Top: Subpixel (Should be smooth). Bottom: Integer (Should jitter).',
		info_cfg) or { panic(err) }
	app.renderer.draw_layout(info_layout, 20.0, 350.0)
}
