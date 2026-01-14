module main

import gg
import vglyph

const window_width = 600
const window_height = 800

struct ListApp {
mut:
	ts           &vglyph.TextSystem = unsafe { nil }
	gg           &gg.Context        = unsafe { nil }
	text_layout  vglyph.Layout
	list_layouts []vglyph.Layout
}

fn main() {
	mut app := &ListApp{}
	app.gg = gg.new_context(
		width:         window_width
		height:        window_height
		create_window: true
		window_title:  'vglyph List Demo'
		user_data:     app
		bg_color:      gg.white
		frame_fn:      frame
		init_fn:       init
	)
	app.gg.run()
}

fn init(mut app ListApp) {
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }

	// Create list items
	// 1. Unordered List
	bullet_items := [
		'First item with enough text to wrap to the next line so we can verify the hanging indent behavior works correctly.',
		'Second item is shorter.',
		'Third item also has some length to it, specifically to check the wrapping implementation of the hanging indent feature in vglyph.',
	]

	// 2. Ordered List
	ordered_items := [
		'Step one is to initialize the context.',
		'Step two involves setting up the text configuration with the correct indentation values.',
		'Step three is rendering the text to the screen.',
	]

	base_style := vglyph.TextStyle{
		font_name: 'Roboto 16'
		color:     gg.black
	}

	indent_width := 34 // Pixels

	// Prepare Layouts

	// Header
	app.text_layout = app.ts.layout_text('Unordered List', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Roboto Bold 20'
			color:     gg.black
		}
	}) or { panic(err) }

	for item in bullet_items {
		// Bullet behavior:
		// Text: "•\t" + content
		// Indent: -indent_width (hangs the bullet)
		// Tabs: [indent_width] (aligns content)

		text := '•\t${item}'
		layout := app.ts.layout_text(text, vglyph.TextConfig{
			style: base_style
			block: vglyph.BlockStyle{
				width:  400 // Limit width to force wrap
				wrap:   .word
				indent: -f32(indent_width) // Negative for hanging indent
				tabs:   [indent_width]
			}
		}) or { panic(err) }
		app.list_layouts << layout
	}

	// Spacer
	// Add a dummy layout or just handle in draw

	// Ordered List Header
	// We'll just render it in the loop or separate logic

	for i, item in ordered_items {
		// Ordered behavior:
		// Text: "1.\t" + content
		// Indent: -indent_width
		// Tabs: [indent_width]

		text := '${i + 1}.\t${item}'
		layout := app.ts.layout_text(text, vglyph.TextConfig{
			style: base_style
			block: vglyph.BlockStyle{
				width:  400
				wrap:   .word
				indent: -f32(indent_width)
				tabs:   [indent_width]
			}
		}) or { panic(err) }
		app.list_layouts << layout
	}
}

fn frame(mut app ListApp) {
	app.gg.begin()

	mut y := f32(50)
	x := f32(50)

	// Draw Header
	app.ts.draw_layout(app.text_layout, x, y)
	app.ts.update_accessibility(app.text_layout, x, y)
	y += app.text_layout.height + 20

	// Draw Unordered List (first 3 items)
	for i in 0 .. 3 {
		// The layout origin is at the indented position
		// Because indent is negative, the first line starts at x + indent
		// So we should shift the draw position by the indent width to align the bullet at 'x'
		// actually, if indent is -20, line 1 starts at -20 relative to layout origin.
		// So if we draw at x + 20, line 1 starts at x. Lines 2+ start at x+20.

		draw_x := x + 24 // shift right by indent amount

		app.ts.draw_layout(app.list_layouts[i], draw_x, y)
		app.ts.update_accessibility(app.list_layouts[i], draw_x, y)
		y += app.list_layouts[i].height + 10
	}

	y += 30
	// Draw Header for Ordered List manually
	app.ts.draw_text(x, y, 'Ordered List', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Roboto Bold 20'
			color:     gg.black
		}
	}) or { panic(err) }
	y += 30

	// Draw Ordered List
	for i in 3 .. 6 {
		draw_x := x + 24
		app.ts.draw_layout(app.list_layouts[i], draw_x, y)
		app.ts.update_accessibility(app.list_layouts[i], draw_x, y)
		y += app.list_layouts[i].height + 10
	}

	app.ts.commit() // Important for texture upload
	app.gg.end()
}
