module text_render

pub struct Layout {
pub mut:
	items []Item
}

pub struct Item {
pub:
	font   &Font
	glyphs []Glyph
	width  f64
}

pub struct Glyph {
pub:
	index     u32
	x_offset  f64
	y_offset  f64
	x_advance f64
	y_advance f64
	codepoint u32
}

// simple fallback: find first font that supports the rune
fn find_font_for_rune(ctx &Context, fonts []string, r rune) &Font {
	for name in fonts {
		if name in ctx.fonts {
			f := ctx.fonts[name] or { panic('unreachable') }
			if f.has_glyph(u32(r)) {
				return f
			}
		}
	}
	// Fallback to first font if none found
	if fonts.len > 0 {
		return ctx.fonts[fonts[0]] or { panic('Font not loaded') }
	}
	panic('No fonts loaded')
}

pub fn (mut ctx Context) layout_text(text string, font_names []string) Layout {
	if text.len == 0 {
		return Layout{}
	}

	mut runs := []Run{}
	runes := text.runes()

	mut current_font := find_font_for_rune(ctx, font_names, runes[0])
	mut current_text := []rune{}

	for r in runes {
		f := find_font_for_rune(ctx, font_names, r)

		if voidptr(f) != voidptr(current_font) {
			runs << Run{
				font: current_font
				text: current_text.string()
			}
			current_text = []rune{}
			// Use unsafe assignment to bypass strict mutability check if confusing compiler
			current_font = unsafe { f }
		}
		current_text << r
	}
	runs << Run{
		font: current_font
		text: current_text.string()
	}

	// Shape each run
	mut items := []Item{}
	for run in runs {
		items << ctx.shape_run(run)
	}

	return Layout{
		items: items
	}
}

struct Run {
	font &Font
	text string
}

fn (mut ctx Context) shape_run(run Run) Item {
	buf := C.hb_buffer_create()
	defer { C.hb_buffer_destroy(buf) }

	C.hb_buffer_add_utf8(buf, run.text.str, run.text.len, 0, -1)
	C.hb_buffer_guess_segment_properties(buf)
	C.hb_shape(run.font.hb_font, buf, 0, 0)

	length := u32(0)
	infos := C.hb_buffer_get_glyph_infos(buf, &length)
	positions := C.hb_buffer_get_glyph_positions(buf, &length)

	mut glyphs := []Glyph{}
	mut total_width := f64(0)

	unsafe {
		for i in 0 .. int(length) {
			info := infos[i]
			pos := positions[i]

			glyphs << Glyph{
				index:     info.codepoint
				x_offset:  f64(pos.x_offset) / 64.0
				y_offset:  f64(pos.y_offset) / 64.0
				x_advance: f64(pos.x_advance) / 64.0
				y_advance: f64(pos.y_advance) / 64.0
			}
			total_width += f64(pos.x_advance) / 64.0
		}
	}
	return Item{
		font:   run.font
		glyphs: glyphs
		width:  total_width
	}
}
