// accessibility_check.v verifies the accessibility implementation.
// It includes a static label and a focusable text field.
module main

import vglyph
import vglyph.accessibility
import gg

const window_width = 800
const window_height = 600

struct App {
mut:
	ts            &vglyph.TextSystem = unsafe { nil }
	gg            &gg.Context        = unsafe { nil }
	field_value   string = 'Type here...'
	has_focus     bool
}

fn main() {
	mut app := &App{}
	app.gg = gg.new_context(
		width:         window_width
		height:        window_height
		create_window: true
		window_title:  'Accessibility Check'
		user_data:     app
		bg_color:      gg.white
		frame_fn:      frame
		init_fn:       init
		keydown_fn:    keydown
	)
	app.gg.run()
}

fn init(mut app App) {
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }
	// Enable automatic accessibility updates for draw_text
	app.ts.enable_accessibility(true)
}

fn keydown(key gg.KeyCode, mod gg.Modifier, mut app App) {
	if key == .tab {
		app.has_focus = !app.has_focus
		println('Focus changed: ${app.has_focus}')
	}
}

fn frame(mut app App) {
	app.gg.begin()

	// 1. Static Label (Automatic via vglyph)
	app.ts.draw_text(50, 50, 'Hello Accessibility', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'System 24'
			color:     gg.black
		}
	}) or { panic(err) }

	// 2. Simulated Text Field (Manual via AccessibilityManager)
	field_rect := gg.Rect{50, 100, 300, 40}
	app.gg.draw_rect_empty(field_rect.x, field_rect.y, field_rect.width, field_rect.height, gg.black)

	if app.has_focus {
		app.gg.draw_rect_empty(field_rect.x - 2, field_rect.y - 2, field_rect.width + 4, field_rect.height + 4, gg.blue)
	}

	app.ts.draw_text(55, 110, app.field_value, vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'System 18'
			color:     gg.black
		}
	}) or { panic(err) }

	// Manual accessibility registration for the text field
	mut am := app.ts.accessibility_manager()
	field_id := am.create_text_field_node(field_rect)
	am.update_text_field(field_id, app.field_value, accessibility.Range{0, app.field_value.len}, 0)

	if app.has_focus {
		am.set_focus(field_id)
	}

	// 3. Commit (pushes accessibility tree to OS)
	app.ts.commit()

	app.gg.end()
}
