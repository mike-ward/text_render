// gradient_text.v demonstrates gradient text rendering.
//
// Features shown:
// - Horizontal gradient with 4 color stops
// - Vertical gradient with 4 color stops
// - Gradient applied via TextConfig (draw_text API)
// - Gradient applied via draw_layout_with_gradient
//
// Run: v run examples/gradient_text.v
module main

import gg
import vglyph

struct GradientApp {
mut:
	gg &gg.Context        = unsafe { nil }
	ts &vglyph.TextSystem = unsafe { nil }
}

const gradient_4stop = &vglyph.GradientConfig{
	stops: [
		vglyph.GradientStop{
			color:    gg.Color{255, 0, 0, 255}
			position: 0.0
		},
		vglyph.GradientStop{
			color:    gg.Color{255, 200, 0, 255}
			position: 0.33
		},
		vglyph.GradientStop{
			color:    gg.Color{0, 180, 255, 255}
			position: 0.66
		},
		vglyph.GradientStop{
			color:    gg.Color{180, 0, 255, 255}
			position: 1.0
		},
	]
}

const gradient_vertical = &vglyph.GradientConfig{
	stops:     [
		vglyph.GradientStop{
			color:    gg.Color{0, 255, 128, 255}
			position: 0.0
		},
		vglyph.GradientStop{
			color:    gg.Color{0, 180, 255, 255}
			position: 0.33
		},
		vglyph.GradientStop{
			color:    gg.Color{200, 80, 255, 255}
			position: 0.66
		},
		vglyph.GradientStop{
			color:    gg.Color{255, 60, 120, 255}
			position: 1.0
		},
	]
	direction: .vertical
}

fn main() {
	mut app := &GradientApp{}
	app.gg = gg.new_context(
		bg_color:     gg.rgb(22, 22, 26)
		width:        900
		height:       500
		window_title: 'VGlyph Gradient Text Demo'
		init_fn:      init
		frame_fn:     frame
		user_data:    app
	)
	app.gg.run()
}

fn init(mut app GradientApp) {
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }
}

fn frame(mut app GradientApp) {
	app.gg.begin()

	// Label
	app.ts.draw_text(30, 20, 'Horizontal gradient (4 stops)', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 16'
			color:     gg.rgb(160, 160, 170)
		}
	}) or {}

	// Horizontal gradient via TextConfig
	app.ts.draw_text(30, 55, 'Gradient Text Rendering', vglyph.TextConfig{
		style:    vglyph.TextStyle{
			font_name: 'Sans Bold 52'
		}
		gradient: gradient_4stop
	}) or {}

	// Label
	app.ts.draw_text(30, 140, 'Vertical gradient (4 stops)', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 16'
			color:     gg.rgb(160, 160, 170)
		}
	}) or {}

	// Vertical gradient via TextConfig
	app.ts.draw_text(30, 175, 'Top to Bottom Flow', vglyph.TextConfig{
		style:    vglyph.TextStyle{
			font_name: 'Sans Bold 52'
		}
		gradient: gradient_vertical
	}) or {}

	// Label
	app.ts.draw_text(30, 260, 'draw_layout_with_gradient API', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 16'
			color:     gg.rgb(160, 160, 170)
		}
	}) or {}

	// Gradient via layout API
	layout := app.ts.layout_text('Layout + Gradient', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans Bold 52'
		}
	}) or { return }
	app.ts.draw_layout_with_gradient(layout, 30, 295, gradient_4stop)

	// Label
	app.ts.draw_text(30, 380, 'Wrapped paragraph with gradient', vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 16'
			color:     gg.rgb(160, 160, 170)
		}
	}) or {}

	// Wrapped text with gradient
	app.ts.draw_text(30, 410, 'Gradient colors interpolate smoothly across the full layout width, spanning multiple lines of wrapped text.',
		vglyph.TextConfig{
		style:    vglyph.TextStyle{
			font_name: 'Sans 22'
		}
		block:    vglyph.BlockStyle{
			width: 840
		}
		gradient: gradient_4stop
	}) or {}

	app.gg.end()
	app.ts.commit()
}
