module main

import gg
import vglyph

const window_width = 800
const window_height = 600

struct TypographyApp {
mut:
	gg &gg.Context
	ts &vglyph.TextSystem

	text_code string
	cfg_code  vglyph.TextConfig

	text_lig string
	cfg_lig  vglyph.TextConfig

	debug_info string
}

fn main() {
	mut app := &TypographyApp{
		gg:         unsafe { nil }
		ts:         unsafe { nil }
		text_code:  'Item\tPrice\tQty\tTotal\nApple\t$1.50\t10\t$15.00\nBanana\t$0.80\t20\t$16.00\nOrange\t$1.20\t15\t$18.00'
		text_lig:   'Scientific: H2O != H3O+  |  Arrows: -> <-> => ==>  |  Fractions: 1/2 1/4 3/4'
		debug_info: 'Click text to inspect font...'
	}

	app.gg = gg.new_context(
		bg_color:     gg.white
		width:        window_width
		height:       window_height
		window_title: 'VGlyph Typography Demo'
		init_fn:      init
		frame_fn:     frame
		event_fn:     event
		user_data:    app
	)

	app.gg.run()
}

fn init(mut app TypographyApp) {
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }

	// Add a monospaced font if possible, or use default system mono
	// app.ts.add_font_file('assets/FiraCode-Regular.ttf') // Example

	app.cfg_code = vglyph.TextConfig{
		font_name: 'Mono 16'
		color:     gg.black
		tabs:      [100, 300, 400, 500] // Pixel offsets
	}

	mut features := map[string]int{}
	features['dlig'] = 1 // Discretionary ligatures
	features['calt'] = 1 // Contextual alternates
	features['frac'] = 1 // Fractions

	app.cfg_lig = vglyph.TextConfig{
		font_name:         'Sans 20' // System sans usually has some ligatures, or load FiraCode/Inter
		color:             gg.hex(0x333333)
		opentype_features: features
	}
}

fn event(e &gg.Event, mut app TypographyApp) {
	if e.typ == .mouse_down {
		// Detection logic
		mx := e.mouse_x - 50.0
		my_lig := e.mouse_y - 300.0 // Offset for second block

		// Check Ligature Block
		if my_lig > 0 && my_lig < 100 { // Approx height
			l := app.ts.layout_text(app.text_lig, app.cfg_lig) or { return }
			idx := l.get_closest_offset(f32(mx), f32(my_lig))
			font_name := l.get_font_name_at_index(idx)
			app.debug_info = 'Index: ${idx}, Font: ${font_name}'
		}
	}
}

fn frame(mut app TypographyApp) {
	app.gg.begin()

	// Draw Code Block (Tabs)
	app.ts.draw_text(50, 50, 'Tabular Data (Custom Tab Stops):', vglyph.TextConfig{
		font_name: 'Sans Bold 14'
		color:     gg.gray
	}) or {}
	app.ts.draw_text(50, 80, app.text_code, app.cfg_code) or { println(err) }

	// Draw Ligature Block
	app.ts.draw_text(50, 270, 'OpenType Features (Ligatures/Fractions):', vglyph.TextConfig{
		font_name: 'Sans Bold 14'
		color:     gg.gray
	}) or {}
	app.ts.draw_text(50, 300, app.text_lig, app.cfg_lig) or { println(err) }

	// Draw Debug Info
	app.gg.draw_text(50, 550, app.debug_info, gg.TextCfg{ color: gg.blue, size: 16 })

	app.gg.end()
	app.ts.commit()
}
