module main

import gg
import text_render

struct App {
mut:
	ctx      &gg.Context
	tr_ctx   &text_render.Context
	renderer &text_render.Renderer
	layouts  []text_render.Layout
	mouse_x  f32
	mouse_y  f32
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
		event_fn:      on_event
		user_data:     app
		init_fn:       init
		ui_mode:       true
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
		align:     .pango_align_center
	}) or { panic(err.msg()) }

	// Demonstrate Rich Text (Markup)
	markup_text := '<span foreground="blue" size="x-large">Blue text</span> <u>underline</u> <b>bold text</b> <i>italics</i> <s>strikethrough</s> <span overline="single">overline</span>'
	app.layouts << app.tr_ctx.layout_text(markup_text, text_render.TextConfig{
		font_name:  'Sans 30'
		use_markup: true
		width:      600
		align:      .pango_align_left
	}) or { panic(err.msg()) }

	app.renderer = text_render.new_renderer(mut app.ctx)
}

fn frame(mut app App) {
	app.ctx.begin()

	if unsafe { app.renderer != 0 } {
		mut y := f32(10)
		for layout in app.layouts {
			app.renderer.draw_layout(layout, 10, y)

			// Hit Testing Demo
			// Check if mouse is within this layout's vertical bounds first for efficiency (optional)
			// Adjust mouse coordinates to be relative to the layout
			local_x := app.mouse_x - 10
			local_y := app.mouse_y - y

			hit_index := layout.hit_test(local_x, local_y)
			if hit_index != -1 {
				// Find the rect for this index to draw a cursor
				for cr in layout.char_rects {
					if cr.index == hit_index {
						// Draw cursor rect
						app.ctx.draw_rect_empty(10 + cr.rect.x, y + cr.rect.y, cr.rect.width,
							cr.rect.height, gg.yellow)
						break
					}
				}
			}

			y += app.renderer.max_visual_height(layout) + 20
		}
		app.renderer.commit()
	}
	app.ctx.end()
}

fn on_event(e &gg.Event, mut app App) {
	if e.typ == .mouse_move {
		app.mouse_x = e.mouse_x
		app.mouse_y = e.mouse_y
	}
}
