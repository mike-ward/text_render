module main

import gg
import text_render

struct AppStyleDemo {
mut:
	ctx         &gg.Context             = unsafe { nil }
	text_system &text_render.TextSystem = unsafe { nil }
}

fn main() {
	mut app := &AppStyleDemo{}
	app.ctx = gg.new_context(
		bg_color:      gg.white
		width:         800
		height:        600
		create_window: true
		window_title:  'Text Styles Demo'
		init_fn:       init
		frame_fn:      frame
		user_data:     app
	)
	app.ctx.run()
}

fn init(mut app AppStyleDemo) {
	app.text_system = text_render.new_text_system(mut app.ctx) or { panic(err) }
}

fn frame(mut app AppStyleDemo) {
	app.ctx.begin()

	// Normal Text
	app.text_system.draw_text(50, 50, 'Defaut Style (Black)', text_render.TextConfig{
		font_name: 'Sans 20'
	}) or { panic(err) }

	// Color Red
	app.text_system.draw_text(50, 100, 'Red Foreground', text_render.TextConfig{
		font_name: 'Sans 20'
		color:     gg.red
	}) or { panic(err) }

	// Background Blue (White text)
	app.text_system.draw_text(50, 150, 'Blue Background', text_render.TextConfig{
		font_name: 'Sans 20'
		color:     gg.white
		bg_color:  gg.blue
	}) or { panic(err) }

	// Underline
	app.text_system.draw_text(50, 200, 'Underlined Text', text_render.TextConfig{
		font_name: 'Sans 20'
		underline: true
	}) or { panic(err) }

	// Strikethrough
	app.text_system.draw_text(50, 250, 'Strikethrough Text', text_render.TextConfig{
		font_name:     'Sans 20'
		strikethrough: true
	}) or { panic(err) }

	// Combined
	app.text_system.draw_text(50, 300, 'Combined: Red, BG Yellow, Underline, Strike',
		text_render.TextConfig{
		font_name:     'Sans 20'
		color:         gg.red
		bg_color:      gg.yellow
		underline:     true
		strikethrough: true
	}) or { panic(err) }

	app.text_system.commit()
	app.ctx.end()
}
