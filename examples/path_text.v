// path_text.v demonstrates text rendered along a circular arc.
//
// Features shown:
// - glyph_positions() to get per-glyph advances
// - draw_layout_placed() for per-glyph positioning
// - Circular arc placement with tangent rotation
//
// Run: v run examples/path_text.v
module main

import gg
import vglyph
import math

struct PathApp {
mut:
	ctx      &gg.Context      = unsafe { nil }
	vcontext &vglyph.Context  = unsafe { nil }
	renderer &vglyph.Renderer = unsafe { nil }
	layout   vglyph.Layout
	angle    f32 // animation offset
}

fn main() {
	mut app := &PathApp{}
	app.ctx = gg.new_context(
		bg_color:     gg.rgb(30, 30, 30)
		width:        800
		height:       600
		window_title: 'Text on Circular Path'
		init_fn:      init
		frame_fn:     frame
		user_data:    app
	)
	app.ctx.run()
}

fn init(mut app PathApp) {
	app.vcontext = vglyph.new_context(app.ctx.scale) or { panic(err) }
	app.renderer = vglyph.new_renderer(mut app.ctx, app.ctx.scale)

	cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans Bold 28'
			color:     gg.white
		}
	}
	app.layout = app.vcontext.layout_text('Hello from the curve!', cfg) or {
		println('Error: ${err}')
		return
	}
}

fn frame(mut app PathApp) {
	app.ctx.begin()

	// Animate rotation
	app.angle += 0.005
	if app.angle > math.pi * 2 {
		app.angle -= math.pi * 2
	}

	// Circle parameters
	cx := f32(400) // center x
	cy := f32(300) // center y
	radius := f32(180)

	// Get glyph advances from layout
	glyph_info := app.layout.glyph_positions()
	if glyph_info.len == 0 {
		app.ctx.end()
		return
	}

	// Total advance width for centering on arc
	mut total_advance := f32(0)
	for gi in glyph_info {
		total_advance += gi.advance
	}

	// Convert total advance to arc angle
	arc_span := total_advance / radius

	// Start angle: center text on arc, offset by animation
	start_angle := app.angle - arc_span / 2.0

	// Place each glyph along the arc
	mut placements := []vglyph.GlyphPlacement{len: app.layout.glyphs.len}
	mut cur_advance := f32(0)
	for gi in glyph_info {
		// Arc-length position for glyph center
		mid := cur_advance + gi.advance * 0.5
		theta := start_angle + mid / radius

		// Tangent angle (perpendicular to radius = theta + pi/2)
		tangent := theta + f32(math.pi) / 2.0

		// Arc point at midpoint of advance
		arc_x := cx + radius * f32(math.cos(theta))
		arc_y := cy + radius * f32(math.sin(theta))

		// Shift back to glyph origin (start of advance)
		half_adv := gi.advance * 0.5
		gx := arc_x - half_adv * f32(math.cos(tangent))
		gy := arc_y - half_adv * f32(math.sin(tangent))

		placements[gi.index] = vglyph.GlyphPlacement{
			x:     gx
			y:     gy
			angle: tangent
		}
		cur_advance += gi.advance
	}

	app.renderer.draw_layout_placed(app.layout, placements)
	app.renderer.commit()
	app.ctx.end()
}
