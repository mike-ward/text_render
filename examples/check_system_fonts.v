module main

import gg
import vglyph

const window_width = 1000
const window_height = 800

struct AppSystemFonts {
mut:
	ctx      &gg.Context        = unsafe { nil }
	text_sys &vglyph.TextSystem = unsafe { nil }
	results  []FontResult
}

struct FontResult {
	request  string
	resolved string
	success  bool
}

fn main() {
	mut app := &AppSystemFonts{}
	app.ctx = gg.new_context(
		width:         window_width
		height:        window_height
		window_title:  'System Font Check'
		create_window: true
		init_fn:       init
		frame_fn:      frame
		user_data:     app
		bg_color:      gg.rgb(0x30, 0x30, 0x30)
	)
	app.ctx.run()
}

fn init(mut app AppSystemFonts) {
	app.text_sys = vglyph.new_text_system(mut app.ctx) or { panic(err) }

	// Perform resolution checks using a temporary Context
	mut check_ctx := vglyph.new_context() or { panic(err) }
	defer { check_ctx.free() }

	fonts := [
		'System Font',
		'Arial',
		'Times New Roman',
		'Courier New',
		'Geneva',
		'Cochin',
		'.AppleSystemUIFont',
		'Helvetica Neue',
		'Menlo',
		'San Francisco',
		'SF Pro',
		'SF Pro Text',
		'SF Pro Display',
		'SF UI Text',
		'SF UI Display',
		'NonExistentFont',
	]

	for f in fonts {
		resolved := check_ctx.resolve_font_name(f)
		success := resolved.to_lower().contains(f.to_lower()) || (f == '.AppleSystemUIFont' && resolved != '') || // Special case if needed, but likely fails
		 (f.starts_with('SF') && resolved.starts_with('SF'))

		// Strict check: if it fell back to Verdana (common fallback) or something else
		// We'll mark it visually.
		// Note: Pango fallback depends on system.

		app.results << FontResult{
			request:  f
			resolved: resolved
			success:  success && resolved != 'Verdana' // Assuming Verdana is fallback for non-existent
		}
	}
}

fn frame(mut app AppSystemFonts) {
	app.ctx.begin()

	mut y := f32(20)
	x_col1 := f32(20)
	x_col2 := f32(300)
	x_col3 := f32(500)

	smoke := gg.rgb(200, 200, 200)

	// Header
	app.text_sys.draw_text(x_col1, y, 'Requested Font', vglyph.TextConfig{
		font_name: 'Menlo Bold 14'
		color:     smoke
	}) or {}
	app.text_sys.draw_text(x_col2, y, 'Resolved To', vglyph.TextConfig{
		font_name: 'Menlo Bold 14'
		color:     smoke
	}) or {}
	app.text_sys.draw_text(x_col3, y, 'Sample Text', vglyph.TextConfig{
		font_name: 'Menlo Bold 14'
		color:     smoke
	}) or {}
	y += 30

	for res in app.results {
		color := if res.success { gg.rgb(100, 255, 100) } else { gg.rgb(255, 100, 100) }
		status := if res.success { 'OK' } else { 'FAIL' }

		// Column 1: Requested Name
		app.text_sys.draw_text(x_col1, y, '${res.request} (${status})', vglyph.TextConfig{
			font_name: 'Menlo 12'
			color:     color
		}) or {}

		// Column 2: Resolved Name
		app.text_sys.draw_text(x_col2, y, res.resolved, vglyph.TextConfig{
			font_name: 'Menlo 12'
			color:     smoke
		}) or {}

		// Column 3: Sample Text in the requested font
		// Ensure we don't crash if the font is totally bogus, Pango handles fallback.
		app.text_sys.draw_text(x_col3, y, 'The quick brown fox jumps over the lazy dog.',
			vglyph.TextConfig{
			font_name: '${res.request} 14'
			color:     smoke
		}) or {}

		y += 35
	}

	app.text_sys.commit()
	app.ctx.end()
}
