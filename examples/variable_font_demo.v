module main

import vglyph
import gg
import sokol.sapp
import math

struct VariableFontApp {
mut:
	ctx         &gg.Context      = unsafe { nil }
	text_system &vglyph.Context  = unsafe { nil }
	renderer    &vglyph.Renderer = unsafe { nil }
	time        f64
}

fn main() {
	mut app := &VariableFontApp{}
	app.ctx = gg.new_context(
		bg_color:     gg.white
		width:        800
		height:       600
		window_title: 'Variable Font Demo'
		frame_fn:     frame
		init_fn:      init
		user_data:    app
	)
	app.ctx.run()
}

fn init(mut app VariableFontApp) {
	scale := sapp.dpi_scale()
	app.text_system = vglyph.new_context(scale) or { panic(err) }
	app.renderer = vglyph.new_renderer(mut app.ctx, scale)
}

fn frame(mut app VariableFontApp) {
	app.ctx.begin()
	app.draw()
	app.ctx.end()
	app.renderer.commit()
	app.time += 0.02
}

fn (mut app VariableFontApp) draw() {
	// Animate weight from 100 to 900
	weight := 400.0 + 300.0 * math.sin(app.time)
	// Animate width from 75 to 100 (if supported)
	width := 100.0 + 25.0 * math.cos(app.time * 0.7)

	// Round to nicely formatted number for display
	weight_disp := int(weight)
	width_disp := int(width)

	// Title
	title_cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: '24'
			color:     gg.black
		}
	}
	title_layout := app.text_system.layout_text('Variable Font Support', title_cfg) or {
		panic(err)
	}
	app.renderer.draw_layout(title_layout, 50.0, 50.0)

	// Load Variable Font from file if available, otherwise fallback to system "Sans"
	// User can download Roboto Flex from Google Fonts.
	font_path := 'assets/RobotoFlex.ttf'
	app.text_system.add_font_file(font_path)

	// Variable Text
	var_cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Roboto Flex 60'
			color:     gg.black
			features:  &vglyph.FontFeatures{
				variation_axes: {
					'wght': f32(weight)
					'wdth': f32(width)
				}
			}
		}
		block: vglyph.BlockStyle{
			align: .center
			width: 700
		}
	}

	text := 'Variable\nTypography'
	layout := app.text_system.layout_text(text, var_cfg) or { panic(err) }

	// Draw centered in window (roughly)
	app.renderer.draw_layout(layout, 50.0, 150.0)

	// Info Text
	info_cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Mono 16'
			color:     gg.gray
		}
	}
	info_text := 'Axis Values:\nwght: ${weight_disp}\nwdth: ${width_disp}'
	info_layout := app.text_system.layout_text(info_text, info_cfg) or { panic(err) }
	app.renderer.draw_layout(info_layout, 50.0, 450.0)
}
