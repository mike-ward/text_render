// stress_demo.v demonstrates performance stress testing with 6000 glyphs.
//
// This is a development tool for atlas performance testing.
//
// Features shown:
// - Large glyph count rendering (6000 characters)
// - Viewport culling optimization
// - Scrolling performance measurement
//
// Run: v run examples/stress_demo.v
module main

import gg
import vglyph

struct AppStress {
mut:
	ctx         &gg.Context        = unsafe { nil }
	ts          &vglyph.TextSystem = unsafe { nil }
	scroll_y    f32
	max_scroll  f32
	frame_count int
}

fn frame(mut app AppStress) {
	app.ctx.begin()
	app.ctx.draw_rect_filled(0, 0, app.ctx.width, app.ctx.height, gg.white)

	// Apply scroll
	app.ctx.draw_rect_empty(0, 0, 0, 0, gg.white) // Dummy call to reset state if needed? Not really needed in gg usually.

	cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 20'
			color:     gg.black
		}
	}

	cols := 20
	total_chars := 6000
	start_code := 0x21 // Start from '!'

	col_width := f32(40.0)
	row_height := f32(30.0)

	rows := (total_chars + cols - 1) / cols
	content_height := rows * row_height
	app.max_scroll = if content_height > app.ctx.height {
		content_height - app.ctx.height + 50
	} else {
		0
	}

	// Viewport culling: only render visible rows
	start_y := f32(50) - app.scroll_y
	view_top := f32(0)
	view_bottom := f32(app.ctx.height)

	// Calculate visible row range
	first_visible_row := int((view_top - start_y) / row_height) - 1
	last_visible_row := int((view_bottom - start_y) / row_height) + 1

	// Clamp to valid range
	row_start := if first_visible_row < 0 { 0 } else { first_visible_row }
	row_end := if last_visible_row > rows { rows } else { last_visible_row }

	for r in row_start .. row_end {
		y := start_y + r * row_height

		for c in 0 .. cols {
			i := r * cols + c
			if i >= total_chars {
				break
			}

			code := start_code + i
			text := rune(code).str()
			x := 50 + c * col_width

			app.ts.draw_text(x, y, text, cfg) or { continue }
		}
	}

	// Performance info
	app.ts.draw_text(10, 10, 'FPS: ${app.ctx.frame}', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 20'
			color:     gg.red
		}
	}) or {}

	visible_rows := row_end - row_start
	app.ts.draw_text(10, 40, 'Rows: ${visible_rows}/${rows} | Scroll: ${int(app.scroll_y)}',
		vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 20'
			color:     gg.blue
		}
	}) or {}

	app.ts.commit()
	app.ctx.end()

	// Automated scroll stress mode
	$if diag ? {
		app.frame_count++
		if app.frame_count % 10 == 0 {
			app.scroll_y = if app.scroll_y < app.max_scroll / 2 {
				app.max_scroll
			} else {
				f32(0)
			}
		}
	}
}

fn init(mut app AppStress) {
	app.ts = vglyph.new_text_system(mut app.ctx) or { panic(err) }
	// Kill switch: force sync upload path to isolate Phase 27
	$if diag_sync ? {
		app.ts.set_async_uploads_diag(false)
	}
}

fn on_event(e &gg.Event, mut app AppStress) {
	if e.typ == .mouse_scroll {
		app.scroll_y -= e.scroll_y * 20
		if app.scroll_y < 0 {
			app.scroll_y = 0
		}
		if app.scroll_y > app.max_scroll {
			app.scroll_y = app.max_scroll
		}
	}
}

fn main() {
	mut app := &AppStress{}
	app.ctx = gg.new_context(
		width:         900
		height:        700
		window_title:  'Stress Test: 6000 Characters'
		create_window: true
		bg_color:      gg.white
		ui_mode:       true
		user_data:     app
		frame_fn:      frame
		init_fn:       init
		event_fn:      on_event
	)

	app.ctx.run()
}
