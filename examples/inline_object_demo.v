module main

import gg
import vglyph

struct AppInline {
mut:
	gg     &gg.Context
	ts     &vglyph.TextSystem
	layout vglyph.Layout
}

fn init(mut app AppInline) {
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }

	// Use a default font or system font
	// For demo purposes, we rely on Pango finding a default.
	app.ts.add_font_file('assets/RobotoFlex.ttf')

	// Create Rich Text with Inline Object
	rt := vglyph.RichText{
		runs: [
			vglyph.StyleRun{
				text:  'Hello, this is a '
				style: vglyph.TextStyle{
					font_name: 'Sans'
					size:      20
					color:     gg.black
				}
			},
			vglyph.StyleRun{
				text:  'OBJECT' // Placeholder text
				style: vglyph.TextStyle{
					size:   20
					object: vglyph.InlineObject{
						id:     'my_blue_rect'
						width:  50
						height: 30
						offset: 5 // Lift it up a bit? or 0
					}
				}
			},
			vglyph.StyleRun{
				text:  ' inline object world!'
				style: vglyph.TextStyle{
					font_name: 'Sans'
					size:      20
					color:     gg.black
				}
			},
		]
	}

	cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			size: 20
		}
		block: vglyph.BlockStyle{
			width: 400
			wrap:  .word
		}
	}

	resolved := app.ts.resolve_font_name('Roboto Flex')
	println('Resolved "Roboto Flex" to: "${resolved}"')

	app.layout = app.ts.layout_rich_text(rt, cfg) or { panic(err) }
}

fn frame(mut app AppInline) {
	app.gg.begin()

	app.ts.draw_layout(app.layout, 50, 50)

	// Manual Object Drawing
	for item in app.layout.items {
		if item.is_object {
			if item.object_id == 'my_blue_rect' {
				// item.y is baseline. item.ascent is distance from baseline to top.
				// We want to draw the rect where the layout reserved space.
				// The logical rect we set was y = -height - offset.
				// So the allocated space top is at baseline - height - offset.
				// Wait, item.x/y are absolute run positions.
				// Let's visualize the item bounds.

				// item.y is the baseline Y position of the run relative to layout origin.
				// But the visual rect might be different?
				// Actually, `process_run` calculates `run_y` as baseline.
				// And `run_ascent` based on logical rect.

				// Let's try drawing at (x + item.x, y + item.y - item.ascent)
				// item.ascent should capture the height we reserved?
				// In `process_run`: `ascent_pango = baseline - logical_rect.y`.
				// Our logical_rect.y was `-h - offset`.
				// So `ascent_pango = 0 - (-h - offset) = h + offset`.
				// So `item.ascent` should be `h + offset`.

				// Draw Rect
				// Top-Left:
				x := 50 + f32(item.x)
				y := 50 + f32(item.y) - f32(item.ascent)

				// Let's verify width/height from item?
				// item.width is the advance width.
				// We don't have item.height directly stored? Item has ascent/descent.

				h := f32(item.ascent + item.descent)
				w := f32(item.width)

				app.gg.draw_rect_filled(x, y, w, h, gg.blue)
			}
		}
	}

	app.gg.end()
	app.ts.commit()
}

fn main() {
	mut app := &AppInline{
		gg: unsafe { nil }
		ts: unsafe { nil }
	}
	app.gg = gg.new_context(
		bg_color:      gg.white
		width:         600
		height:        400
		create_window: true
		window_title:  'Inline Object Demo'
		frame_fn:      frame
		user_data:     app
		init_fn:       init
	)
	app.gg.run()
}
