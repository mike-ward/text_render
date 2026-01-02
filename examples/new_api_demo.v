module main

import gg
import text_render

struct AppApi {
mut:
	ctx &gg.Context
	ts  &text_render.TextSystem
}

fn main() {
	mut app := &AppApi{
		ctx: unsafe { nil }
		ts:  unsafe { nil }
	}

	app.ctx = gg.new_context(
		width:         800
		height:        600
		bg_color:      gg.light_gray
		create_window: true
		window_title:  'Text System API Demo'
		frame_fn:      frame
		user_data:     app
		init_fn:       init
	)

	app.ctx.run()
}

fn init(mut app AppApi) {
	// Initialize the new Text System
	// casting app.ctx to mutable for the API
	app.ts = text_render.new_text_system(mut app.ctx) or { panic(err) }
}

fn frame(mut app AppApi) {
	app.ctx.begin()

	// 1. Simple text drawing
	cfg := text_render.TextConfig{
		font_name: 'Sans 24'
		width:     0 // no wrapping
	}
	app.ts.draw_text(50, 50, 'Hello, New API!', cfg) or { panic(err) }

	// 2. Text with wrapping and measurement
	long_text := 'This usage pattern is much cleaner. The system handles layout caching internally.'
	wrap_cfg := text_render.TextConfig{
		font_name: 'Impact 20'
		width:     300
		wrap:      .word
		align:     .left
	}

	app.ts.draw_text(50, 100, long_text, wrap_cfg) or { panic(err) }

	// Measure it to draw a border
	w := app.ts.text_width(long_text, wrap_cfg) or { 0.0 }
	h := app.ts.text_height(long_text, wrap_cfg) or { 0.0 }
	app.ctx.draw_rect_empty(50, 100, w, h, gg.blue)

	// 3. Colored/Markup text
	markup := '<span foreground="red">Red</span> and <span foreground="blue">Blue</span> text mixed together.'
	markup_cfg := text_render.TextConfig{
		font_name:  'Monospace 18'
		use_markup: true
	}
	app.ts.draw_text(50, 300, markup, markup_cfg) or { panic(err) }

	app.ts.commit()
	app.ctx.end()
}
