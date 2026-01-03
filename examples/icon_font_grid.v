module main

import gg
import text_render

struct AppIconGrid {
mut:
	ctx &gg.Context             = unsafe { nil }
	ts  &text_render.TextSystem = unsafe { nil }
}

fn frame(mut app AppIconGrid) {
	app.ctx.begin()
	app.ctx.draw_rect_filled(0, 0, 800, 600, gg.white)

	cfg := text_render.TextConfig{
		font_name: 'feathericon 24'
		color:     gg.black
	}

	// Draw a grid of icons from the PUA range
	// feather icons usually start around 0xE900
	rows := 16
	cols := 16
	start_code := 0xF100

	for r in 0 .. rows {
		for c in 0 .. cols {
			code := start_code + r * cols + c
			text := rune(code).str()

			x := 50 + c * 40
			y := 50 + r * 30

			app.ts.draw_text(x, y, text, cfg) or { continue }
		}
	}

	app.ts.commit()
	app.ctx.end()
}

fn init(mut app AppIconGrid) {
	app.ts = text_render.new_text_system(mut app.ctx) or { panic(err) }

	// Load the icon font
	// Assume running from project root
	if !app.ts.add_font_file('assets/feathericon.ttf') {
		println('Failed to load font file: assets/feathericon.ttf')
	} else {
		println('Successfully loaded assets/feathericon.ttf')
	}
}

fn main() {
	mut app := &AppIconGrid{}
	app.ctx = gg.new_context(
		width:        800
		height:       600
		window_title: 'Icon Font Grid'
		user_data:    app
		frame_fn:     frame
		init_fn:      init
	)

	app.ctx.run()
}
