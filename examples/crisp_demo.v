module main

import vglyph
import gg

const crisp_win_width = 600
const crisp_win_height = 400

struct CrispApp {
mut:
	ctx         &gg.Context      = unsafe { nil }
	text_system &vglyph.Context  = unsafe { nil }
	renderer    &vglyph.Renderer = unsafe { nil }
}

fn main() {
	mut app := &CrispApp{}
	app.ctx = gg.new_context(
		bg_color:     gg.white
		width:        crisp_win_width
		height:       crisp_win_height
		window_title: 'Crisp Text Verification'
		frame_fn:     frame
		init_fn:      init
		user_data:    app
	)
	app.ctx.run()
}

fn init(mut app CrispApp) {
	app.text_system = vglyph.new_context() or { panic(err) }
	app.renderer = vglyph.new_renderer(mut app.ctx)
}

fn frame(mut app CrispApp) {
	app.ctx.begin()
	app.draw()
	app.ctx.end()
	app.renderer.commit()
}

fn (mut app CrispApp) draw() {
	// Draw a range of small sizes to check for sharpness
	sizes := [10, 11, 12, 13, 14, 16, 18, 24]
	mut y_pos := 20.0

	// Standard Text
	for size in sizes {
		text := 'The quick brown fox jumps over the lazy dog (${size}px) - Standard'
		// Size is passed in font_name string for Pango
		cfg := vglyph.TextConfig{
			font_name: 'Arial ${size}'
			color:     gg.black
		}

		layout := app.text_system.layout_text(text, cfg) or { panic(err) }
		app.renderer.draw_layout(layout, 20.0, f32(y_pos))

		// Calculate height
		height := app.renderer.max_visual_height(layout)
		y_pos += height + 5.0
	}
}
