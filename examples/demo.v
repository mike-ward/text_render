module main

import gg
import os
import text_render

struct App {
mut:
	ctx      &gg.Context
	tr_ctx   &text_render.Context
	renderer &text_render.Renderer
	layout   text_render.Layout
}

struct FontDef {
	name string
	path string
	size int
}

fn main() {
	mut app := &App{
		ctx:      unsafe { nil }
		tr_ctx:   unsafe { nil }
		renderer: unsafe { nil }
	}

	app.ctx = gg.new_context(
		width:         800
		height:        600
		bg_color:      gg.gray
		create_window: true
		window_title:  'V Text Render Atlas Demo'
		frame_fn:      frame
		user_data:     app
		init_fn:       init
	)

	app.ctx.run()
}

fn init(mut app App) {
	app.tr_ctx = text_render.new_context() or { panic(err) }

	// Locate fonts
	wd := os.getwd()
	base_path := if os.exists(os.join_path(wd, 'assets/fonts')) {
		wd
	} else if os.exists(os.join_path(wd, '../assets/fonts')) {
		os.join_path(wd, '..')
	} else {
		wd
	}

	fonts := [
		FontDef{'arial', os.join_path(base_path, 'assets/fonts/NotoSans-Regular.ttf'), 30},
		FontDef{'arabic', os.join_path(base_path, 'assets/fonts/NotoSansArabic-Regular.ttf'), 30},
		FontDef{'japanese', os.join_path(base_path, 'assets/fonts/NotoSansCJKjp-Regular.otf'), 30},
		FontDef{'emoji-color', os.join_path(base_path, 'assets/fonts/NotoColorEmoji.ttf'), 30},
		FontDef{'emoji', os.join_path(base_path, 'assets/fonts/NotoSansSymbols2-Regular.ttf'), 30},
	]

	mut loaded_names := []string{}

	for f in fonts {
		if os.exists(f.path) {
			println('Loading ${f.name} from ${f.path}')
			app.tr_ctx.load_font(f.name, f.path, f.size) or {
				println('Failed to load ${f.name}')
				continue
			}
			loaded_names << f.name
		} else {
			println('Font not found: ${f.path}')
		}
	}

	text := 'Hello السلام Verden 🌍9局て脂済事つまきな政98院'
	app.layout = app.tr_ctx.layout_text(text, loaded_names)

	app.renderer = text_render.new_renderer(mut app.ctx)
}

fn frame(mut app App) {
	app.ctx.begin()

	if unsafe { app.renderer != 0 } {
		// Draw the layout at x=10, y=75
		app.renderer.draw_layout(app.layout, 10, 75)
	}

	app.ctx.end()
}
