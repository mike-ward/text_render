module main

import gg
import text_render

struct App {
mut:
	ctx      &gg.Context
	tr_ctx   &text_render.Context
	renderer &text_render.Renderer
	layouts  []text_render.Layout
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
	app.tr_ctx.free()
}

fn init(mut app App) {
	app.tr_ctx = text_render.new_context() or { panic(err) }

	// Pango handles font fallback automatically.
	// We just ask for a base font and size.
	// Ensure you have fonts installed that cover these scripts (e.g. Noto Sans).
	text := 'Hello السلام Verden 🌍 9局て脂済事つまきな政98院 Здравей'
	app.layouts << app.tr_ctx.layout_text(text, text_render.TextConfig{ font_name: 'Sans 30' }) or {
		panic(err.msg())
	}

	french := "Voix ambiguë d'un cœur qui, au zéphyr, préfère les jattes de kiwis."
	app.layouts << app.tr_ctx.layout_text(french, text_render.TextConfig{ font_name: 'Serif 30' }) or {
		panic(err.msg())
	}

	korean := '오늘 외출할 거예요. 일요일 아홉시 반 아침이에요. 지금 막 일어났어요.'
	app.layouts << app.tr_ctx.layout_text(korean, text_render.TextConfig{ font_name: 'Sans 30' }) or {
		panic(err.msg())
	}

	// Demonstrate wrapping
	long_text :=
		'This is a long paragraph that should wrap automatically when it reaches the specified width. ' +
		'Pango handles the line breaking, and we can also align the text to the center or right. ' +
		'This ensures that our UI elements rendered with this engine can accommodate variable length content gracefully.'

	app.layouts << app.tr_ctx.layout_text(long_text, text_render.TextConfig{
		font_name: 'Sans 20'
		width:     400
		align:     .pango_align_left
	}) or { panic(err.msg()) }

	app.renderer = text_render.new_renderer(mut app.ctx)
}

fn frame(mut app App) {
	app.ctx.begin()

	if unsafe { app.renderer != 0 } {
		mut y := f32(10)
		for layout in app.layouts {
			app.renderer.draw_layout(layout, 10, y)
			y += app.renderer.max_visual_height(layout) + 20
		}
	}

	app.ctx.end()
}
