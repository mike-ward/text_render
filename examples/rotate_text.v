module main

import gg
import vglyph
import math

struct RotateApp {
mut:
	ctx         &gg.Context     = unsafe { nil }
	vcontext    &vglyph.Context = unsafe { nil }
	layout_horz vglyph.Layout
	layout_vert vglyph.Layout
	renderer    &vglyph.Renderer = unsafe { nil }
	angle       f32
}

fn main() {
	mut app := &RotateApp{}
	app.ctx = gg.new_context(
		bg_color:     gg.rgb(30, 30, 30)
		width:        800
		height:       600
		window_title: 'Text Rotation & Vertical Text'
		init_fn:      init
		frame_fn:     frame
		user_data:    app
	)
	app.ctx.run()
}

fn init(mut app RotateApp) {
	// Init vglyph - must happen after gg.Context is running (Sokol initialized)
	app.vcontext = vglyph.new_context(app.ctx.scale) or { panic(err) }
	app.renderer = vglyph.new_renderer(mut app.ctx, app.ctx.scale)

	// Layout Horizontal
	cfg_h := vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 30'
			color:     gg.white
			underline: true
		}
	}
	app.layout_horz = app.vcontext.layout_text('Hello Rotated World!', cfg_h) or {
		println('Error layout horz: ${err}')
		return
	}

	// Layout Vertical (CJK)
	cfg_v := vglyph.TextConfig{
		style:       vglyph.TextStyle{
			font_name: 'Sans 30'
			color:     gg.yellow
		}
		orientation: .vertical
	}
	// Japanese: "Vertical Text" (Tategaki)
	app.layout_vert = app.vcontext.layout_text('縦書きテキスト', cfg_v) or {
		println('Error layout vert: ${err}')
		return
	}
}

fn frame(mut app RotateApp) {
	app.ctx.begin()

	app.angle += 0.02
	if app.angle > math.pi * 2 {
		app.angle -= math.pi * 2
	}

	app.renderer.draw_layout_rotated(app.layout_horz, 300, 300, app.angle)
	app.renderer.draw_layout(app.layout_vert, 600, 100)

	app.renderer.commit()
	app.ctx.end()
}
