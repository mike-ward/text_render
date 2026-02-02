module main

import gg
import vglyph

const window_width = 800
const window_height = 600

struct EditorApp {
mut:
	gg &gg.Context
	ts &vglyph.TextSystem

	text   string
	cfg    vglyph.TextConfig
	layout vglyph.Layout

	cursor_idx   int
	select_start int
	is_dragging  bool
	preferred_x  f32 // Remembered x position for up/down navigation
}

fn main() {
	mut app := &EditorApp{
		gg:           unsafe { nil }
		ts:           unsafe { nil }
		text:         'Hello VGlyph Editor!\n\n' +
			'This is a demo of cursor positioning and keyboard navigation.\n\n' +
			'Try arrow keys (Cmd+Arrow for words, Home/End for line).\n\n' +
			'Grapheme tests: flag: 🇺🇸 family: 👨‍👩‍👧 rainbow: 🌈\n' +
			'Arabic: مرحبا  Hebrew: שלום\n' + 'Combined: e + combining accent: é'
		select_start: -1
		preferred_x:  -1
	}

	app.gg = gg.new_context(
		bg_color:     gg.white
		width:        window_width
		height:       window_height
		window_title: 'VGlyph Editor Demo'
		init_fn:      init
		frame_fn:     frame
		event_fn:     event
		user_data:    app
	)

	app.gg.run()
}

fn init(mut app EditorApp) {
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }

	app.cfg = vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 16'
			color:     gg.black
		}
		block: vglyph.BlockStyle{
			width: 600
			wrap:  .word
		}
	}

	// Perform initial layout
	// We access the context directly to get the layout object for logical operations
	// In a real app, you might cache this
	app.layout = app.ts.layout_text(app.text, app.cfg) or { panic(err) }
}

fn event(e &gg.Event, mut app EditorApp) {
	// Offset for rendering (x=50, y=50)
	offset_x := f32(50)
	offset_y := f32(50)

	match e.typ {
		.mouse_down {
			mx := e.mouse_x - offset_x
			my := e.mouse_y - offset_y

			// Get index closest to click
			idx := app.layout.get_closest_offset(mx, my)
			app.cursor_idx = idx
			app.select_start = idx
			app.is_dragging = true
			app.preferred_x = -1
		}
		.mouse_up {
			app.is_dragging = false
		}
		.mouse_move {
			if app.is_dragging {
				mx := e.mouse_x - offset_x
				my := e.mouse_y - offset_y
				idx := app.layout.get_closest_offset(mx, my)
				app.cursor_idx = idx
			}
		}
		.key_down {
			// Handle navigation keys
			// Modifier.super = 8 (1<<3)
			cmd_held := (e.modifiers & u32(gg.Modifier.super)) != 0

			match e.key_code {
				.left {
					if cmd_held {
						app.cursor_idx = app.layout.move_cursor_word_left(app.cursor_idx)
					} else {
						app.cursor_idx = app.layout.move_cursor_left(app.cursor_idx)
					}
					app.preferred_x = -1 // Reset preferred x on horizontal movement
				}
				.right {
					if cmd_held {
						app.cursor_idx = app.layout.move_cursor_word_right(app.cursor_idx)
					} else {
						app.cursor_idx = app.layout.move_cursor_right(app.cursor_idx)
					}
					app.preferred_x = -1
				}
				.up {
					if app.preferred_x < 0 {
						if pos := app.layout.get_cursor_pos(app.cursor_idx) {
							app.preferred_x = pos.x
						}
					}
					app.cursor_idx = app.layout.move_cursor_up(app.cursor_idx, app.preferred_x)
				}
				.down {
					if app.preferred_x < 0 {
						if pos := app.layout.get_cursor_pos(app.cursor_idx) {
							app.preferred_x = pos.x
						}
					}
					app.cursor_idx = app.layout.move_cursor_down(app.cursor_idx, app.preferred_x)
				}
				.home {
					app.cursor_idx = app.layout.move_cursor_line_start(app.cursor_idx)
					app.preferred_x = -1
				}
				.end {
					app.cursor_idx = app.layout.move_cursor_line_end(app.cursor_idx)
					app.preferred_x = -1
				}
				else {}
			}
			// Clear selection on navigation (unless shift held - future feature)
			app.select_start = -1
		}
		else {}
	}
}

fn frame(mut app EditorApp) {
	app.gg.begin()

	// Draw Text
	offset_x := f32(50)
	offset_y := f32(50)

	// Draw Selection Backgrounds
	if app.select_start != -1 && app.cursor_idx != app.select_start {
		start := if app.select_start < app.cursor_idx { app.select_start } else { app.cursor_idx }
		end := if app.select_start < app.cursor_idx { app.cursor_idx } else { app.select_start }

		rects := app.layout.get_selection_rects(start, end)
		for r in rects {
			app.gg.draw_rect_filled(offset_x + r.x, offset_y + r.y, r.width, r.height,
				gg.Color{50, 50, 200, 100})
		}
	}

	// Render the text using the system
	app.ts.draw_text(offset_x, offset_y, app.text, app.cfg) or { println(err) }

	// Draw Cursor using get_cursor_pos API
	if pos := app.layout.get_cursor_pos(app.cursor_idx) {
		app.gg.draw_rect_filled(offset_x + pos.x, offset_y + pos.y, 2, pos.height, gg.red)
	}

	app.gg.end()
	app.ts.commit()
}
