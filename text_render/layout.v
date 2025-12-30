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
fn find_font_for_rune(ctx &Context, fonts []string, r rune) !&Font {
	for name in fonts {
		if name in ctx.fonts {
			f := ctx.fonts[name] or { return error('ctx.fonts[${name}] not found') }
			if f.has_glyph(u32(r)) {
				return f
			}
		}
	}
	// Fallback to first font if none found
	if fonts.len > 0 {
		return ctx.fonts[fonts[0]] or { error('Fallback to first font failed') }
	}
	return error('No fonts loaded')
}

pub fn (mut ctx Context) layout_text(text string, font_names []string) !Layout {
	if text.len == 0 {
		return Layout{}
	}

	runes := text.runes()
	len := runes.len

	// FriBidi allocations
	mut btypes := []u32{len: len}
	mut levels := []i8{len: len}
	mut visual_str := []u32{len: len}
	mut map_visual_to_logical := []int{len: len}
	mut map_logical_to_visual := []int{len: len}

	unsafe {
		C.fribidi_get_bidi_types(runes.data, len, btypes.data)
		mut pbase_dir := u32(fribidi_type_on)
		C.fribidi_get_par_embedding_levels(btypes.data, len, &pbase_dir, levels.data)
		C.fribidi_log2vis(runes.data, len, &pbase_dir, visual_str.data, map_visual_to_logical.data,
			map_logical_to_visual.data, levels.data)
	}
	mut items := []Item{}

	if len > 0 {
		mut start_i := 0
		mut start_logical := map_visual_to_logical[0]
		mut current_level := levels[start_logical]
		mut current_font := find_font_for_rune(ctx, font_names, runes[start_logical])!

		for i in 1 .. len {
			logical_idx := map_visual_to_logical[i]
			level := levels[logical_idx]
			font := find_font_for_rune(ctx, font_names, runes[logical_idx])!

			if level != current_level || voidptr(font) != voidptr(current_font) {
				items << ctx.create_item_from_run(runes, map_visual_to_logical, start_i,
					i, current_font, current_level)

				start_i = i
				current_level = level
				unsafe {
					current_font = font
				}
			}
		}
		items << ctx.create_item_from_run(runes, map_visual_to_logical, start_i, len,
			current_font, current_level)
	}

	return Layout{
		items: items
	}
}

fn (mut ctx Context) create_item_from_run(runes []rune, map_vis_to_log []int, start_i int, end_i int, font &Font, level i8) Item {
	first_log := map_vis_to_log[start_i]
	last_log := map_vis_to_log[end_i - 1]

	mut run_text_runes := []rune{cap: end_i - start_i}

	if first_log < last_log {
		for k in first_log .. (last_log + 1) {
			run_text_runes << runes[k]
		}
	} else {
		for k in last_log .. (first_log + 1) {
			run_text_runes << runes[k]
		}
	}

	run := unsafe {
		Run{
			font:  font
			text:  run_text_runes.string()
			level: level
		}
	}
	return ctx.shape_run(run)
}

struct Run {
	font  &Font
	text  string
	level i8
}

fn (mut ctx Context) shape_run(run Run) Item {
	buf := C.hb_buffer_create()
	defer { C.hb_buffer_destroy(buf) }

	C.hb_buffer_add_utf8(buf, run.text.str, run.text.len, 0, -1)

	dir := if run.level % 2 == 1 { hb_direction_rtl } else { hb_direction_ltr }
	C.hb_buffer_set_direction(buf, dir)

	C.hb_buffer_guess_segment_properties(buf)
	C.hb_shape(run.font.hb_font, buf, 0, 0)

	length := u32(0)
	infos := C.hb_buffer_get_glyph_infos(buf, &length)
	positions := C.hb_buffer_get_glyph_positions(buf, &length)

	mut glyphs := []Glyph{cap: int(length)}
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
