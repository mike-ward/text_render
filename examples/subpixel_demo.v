module main

import vglyph
import gg
import sokol.sapp

const subpixel_win_width = 800
const subpixel_win_height = 600

struct App {
mut:
	ctx         &gg.Context      = unsafe { nil }
	text_system &vglyph.Context  = unsafe { nil }
	renderer    &vglyph.Renderer = unsafe { nil }
}

fn main() {
	mut app := &App{}
	app.ctx = gg.new_context(
		bg_color:     gg.white
		width:        subpixel_win_width
		height:       subpixel_win_height
		window_title: 'Subpixel LCD AA Test'
		frame_fn:     frame
		init_fn:      init
		user_data:    app
	)
	app.ctx.run()
}

fn init(mut app App) {
	scale := sapp.dpi_scale()
	// Initialize vglyph context
	app.text_system = vglyph.new_context(scale) or { panic(err) }
	// Initialize renderer
	app.renderer = vglyph.new_renderer(mut app.ctx, scale)
}

fn frame(mut app App) {
	app.ctx.begin()
	app.draw()
	app.ctx.end()
	app.renderer.commit()
}

fn (mut app App) draw() {
	// Draw various sizes to inspect subpixel rendering quality
	sizes := [10, 11, 12, 14, 16, 18, 24, 32, 48]
	mut y_pos := 20.0
	x_pos := 20.0

	for size in sizes {
		text := 'Subpixel AA Test: The quick brown fox jumps over the lazy dog (${size}px)'
		cfg := vglyph.TextConfig{
			font_name: 'Sans ${size}'
			color:     gg.black
		}

		layout := app.text_system.layout_text(text, cfg) or { panic(err) }
		app.renderer.draw_layout(layout, f32(x_pos), f32(y_pos))

		height := app.renderer.max_visual_height(layout)
		y_pos += height + 10.0
	}

	// Draw some colored text to check blending behavior with the "Average Alpha" hack
	y_pos += 20.0
	colors := [gg.red, gg.blue, gg.green, gg.Color{
		r: 128
		g: 0
		b: 128
		a: 255
	}]

	for i, col in colors {
		text := 'Colored Text Test (${colors[i]})'
		cfg := vglyph.TextConfig{
			font_name: 'Sans 16'
			color:     col
		}
		layout := app.text_system.layout_text(text, cfg) or { panic(err) }
		app.renderer.draw_layout(layout, f32(x_pos), f32(y_pos))

		height := app.renderer.max_visual_height(layout)
		y_pos += height + 5.0
	}
}
