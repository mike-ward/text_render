module vglyph

import gg

struct RunMetrics {
pub mut:
	und_pos      f64
	und_thick    f64
	strike_pos   f64
	strike_thick f64
}

// get_run_metrics fetches metrics (position, thickness) for active decorations
// (underline, strikethrough) using Pango API.
fn get_run_metrics(pango_font &C.PangoFont, language &C.PangoLanguage,
	attrs RunAttributes) RunMetrics {
	mut m := RunMetrics{}
	if attrs.has_underline || attrs.has_strikethrough {
		metrics := C.pango_font_get_metrics(pango_font, language)
		if metrics != unsafe { nil } {
			if attrs.has_underline {
				val_pos := C.pango_font_metrics_get_underline_position(metrics)
				val_thick := C.pango_font_metrics_get_underline_thickness(metrics)
				m.und_pos = f64(val_pos) / f64(pango_scale)
				m.und_thick = f64(val_thick) / f64(pango_scale)
				if m.und_thick < 1.0 {
					m.und_thick = 1.0
				}
				if m.und_pos < m.und_thick {
					m.und_pos = m.und_thick + 2.0
				}
			}
			if attrs.has_strikethrough {
				val_pos := C.pango_font_metrics_get_strikethrough_position(metrics)
				val_thick := C.pango_font_metrics_get_strikethrough_thickness(metrics)
				m.strike_pos = f64(val_pos) / f64(pango_scale)
				m.strike_thick = f64(val_thick) / f64(pango_scale)
				if m.strike_thick < 1.0 {
					m.strike_thick = 1.0
				}
			}
			C.pango_font_metrics_unref(metrics)
		}
	}
	return m
}

struct ProcessRunConfig {
	run             &C.PangoLayoutRun
	iter            &C.PangoLayoutIter
	text            string
	scale_factor    f32
	pixel_scale     f64
	primary_ascent  f64
	primary_descent f64
	base_color      gg.Color
	orientation     TextOrientation
}

// process_run converts a single Pango glyph run into a V `Item`.
// Handles attribute parsing, metric calculation, and glyph extraction.
// Returns the updated vertical pen position (for vertical text stacking).
fn process_run(mut items []Item, mut all_glyphs []Glyph, vertical_pen_y f64,
	cfg ProcessRunConfig) f64 {
	run := cfg.run
	iter := cfg.iter
	text := cfg.text
	_ = cfg.scale_factor
	pixel_scale := cfg.pixel_scale
	primary_ascent := cfg.primary_ascent
	// primary_descent is currently unused but kept for symmetry/interface
	_ = cfg.primary_descent

	pango_item := run.item
	pango_font := pango_item.analysis.font
	if pango_font == unsafe { nil } {
		return vertical_pen_y
	}

	ft_face := C.pango_ft2_font_get_face(pango_font)
	if ft_face == unsafe { nil } {
		return vertical_pen_y
	}

	attrs := parse_run_attributes(pango_item)
	metrics := get_run_metrics(pango_font, pango_item.analysis.language, attrs)

	// Get logical extents for ascent/descent (used for background rect)
	logical_rect := C.PangoRectangle{}
	// We need ascent/descent relative to baseline.
	// run_x and run_y are logical POSITIONS (y is baseline)
	// logical_rect from get_run_extents is relative to layout origin (top-left)
	C.pango_layout_iter_get_run_extents(iter, unsafe { nil }, &logical_rect)

	// Round run position to integer grid
	run_x := f64(logical_rect.x) * pixel_scale

	baseline_pango := C.pango_layout_iter_get_baseline(iter)
	ascent_pango := baseline_pango - logical_rect.y
	descent_pango := (logical_rect.y + logical_rect.height) - baseline_pango

	run_ascent := f64(ascent_pango) * pixel_scale
	run_descent := f64(descent_pango) * pixel_scale
	mut run_y := f64(baseline_pango) * pixel_scale

	// Emoji Vertical Centering
	// Detect if this is an emoji run
	fam_name := unsafe { cstring_to_vstring(ft_face.family_name) } // Assumes ft_face is valid
	if fam_name.contains('Emoji') && primary_ascent > 0 {
		// Logic: Align emoji visual center with approximate x-height center of primary font.
		// "Raised" look comes from aligning to full ascent (includes accents/line gap).
		// CSS `vertical-align: middle` aligns with `baseline + x-height / 2`.
		//
		// Approx X-Height = 0.5 * PrimaryAscent
		// Target Center (from baseline) = - (XHeight / 2)
		// Emoji Center (relative to baseline) = (run_descent - run_ascent) / 2
		//
		// Shift = Target_Center - Emoji_Center
		x_height := primary_ascent * 0.5 // heuristic
		target_center := -x_height / 2.0
		emoji_center := (run_descent - run_ascent) / 2.0

		shift := target_center - emoji_center
		run_y += shift
	}

	// Extract glyphs
	glyph_string := run.glyphs
	num_glyphs := glyph_string.num_glyphs

	start_glyph_idx := all_glyphs.len
	mut width := f64(0)
	infos := glyph_string.glyphs

	for i in 0 .. num_glyphs {
		unsafe {
			info := infos[i]
			x_off := f64(info.geometry.x_offset) * pixel_scale
			y_off := f64(info.geometry.y_offset) * pixel_scale
			x_adv := f64(info.geometry.width) * pixel_scale
			y_adv := 0.0

			// Vertical Transform - Manual Stacking (Upright CJK)
			//
			// Input (from Pango horizontal layout):
			//   x_advance = character width (horizontal)
			//   y_offset  = vertical baseline shift
			//
			// Output (for vertical stacking):
			//   x_advance = 0 (no horizontal movement)
			//   y_advance = -line_height (negative = pen moves DOWN in screen coords)
			//   x_offset  = (line_height - char_width) / 2 (center in column)
			//
			// Formula: final_y_adv = -(ascent + descent)
			// Why: Screen Y increases downward, so negative advance moves pen down

			line_height := cfg.primary_ascent + cfg.primary_descent
			final_x_off, final_y_off, final_x_adv, final_y_adv := match cfg.orientation {
				.horizontal {
					compute_glyph_transform_horizontal(x_off, y_off, x_adv, y_adv)
				}
				.vertical {
					compute_glyph_transform_vertical(x_off, y_off, x_adv, y_adv, line_height)
				}
			}

			all_glyphs << Glyph{
				index:     info.glyph
				x_offset:  final_x_off
				y_offset:  final_y_off
				x_advance: final_x_adv
				y_advance: final_y_adv
				codepoint: 0
			}
			width += x_adv
		}
	}

	glyph_count := all_glyphs.len - start_glyph_idx

	// Vertical Run Positioning
	//
	// Transform: swap X/Y baselines
	//   final_run_x = run_y (horizontal baseline -> vertical X position)
	//   final_run_y = vertical_pen_y (cumulative vertical stack position)
	//
	// Why: In vertical text, the "baseline" becomes vertical center of column.
	// Pango's run_y (horizontal baseline offset) maps to X centering.

	line_height_run := cfg.primary_ascent + cfg.primary_descent
	final_run_x, final_run_y, new_vertical_pen_y := match cfg.orientation {
		.horizontal {
			compute_run_position_horizontal(run_x, run_y, vertical_pen_y)
		}
		.vertical {
			compute_run_position_vertical(run_x, run_y, vertical_pen_y, line_height_run,
				glyph_count)
		}
	}

	// Get sub-text
	start_index := pango_item.offset
	length := pango_item.length

	// Check for transparent color (no attribute found) and fallback to base_color
	mut final_color := attrs.color
	if final_color.a == 0 {
		final_color = cfg.base_color
	}

	// Double fallback: if base_color was transparent, default to black (opaque)
	if final_color.a == 0 {
		final_color = gg.Color{0, 0, 0, 255}
	}

	// Conditionally include run_text for debug builds
	$if debug {
		// Bounds check before creating substring
		run_str := if start_index >= 0 && length >= 0 && start_index + length <= text.len {
			unsafe { (text.str + start_index).vstring_with_len(length) }
		} else {
			''
		}
		items << Item{
			run_text: run_str
			ft_face:  ft_face

			width:   width
			x:       final_run_x
			y:       final_run_y
			ascent:  run_ascent
			descent: run_descent

			glyph_start: start_glyph_idx
			glyph_count: glyph_count
			start_index: start_index
			length:      length

			underline_offset:        metrics.und_pos
			underline_thickness:     metrics.und_thick
			strikethrough_offset:    metrics.strike_pos
			strikethrough_thickness: metrics.strike_thick

			color:    final_color
			bg_color: attrs.bg_color

			has_underline:      attrs.has_underline
			has_strikethrough:  attrs.has_strikethrough
			has_bg_color:       attrs.has_bg_color
			use_original_color: (ft_face.face_flags & ft_face_flag_color) != 0
		}
		return new_vertical_pen_y
	} $else {
		item := Item{
			ft_face:   ft_face
			object_id: attrs.object_id

			width:   width
			x:       final_run_x
			y:       final_run_y
			ascent:  run_ascent
			descent: run_descent

			glyph_start: start_glyph_idx
			glyph_count: glyph_count
			start_index: start_index
			length:      length

			underline_offset:        metrics.und_pos
			underline_thickness:     metrics.und_thick
			strikethrough_offset:    metrics.strike_pos
			strikethrough_thickness: metrics.strike_thick

			color:    final_color
			bg_color: attrs.bg_color

			has_underline:      attrs.has_underline
			has_strikethrough:  attrs.has_strikethrough
			has_bg_color:       attrs.has_bg_color
			use_original_color: (ft_face.face_flags & ft_face_flag_color) != 0
			is_object:          attrs.is_object
		}
		if item.glyph_count > 0 || item.is_object {
			items << item
		}
		return new_vertical_pen_y
	}
}

// compute_hit_test_rects generates bounding boxes for every character
// to enable efficient hit testing.
fn compute_hit_test_rects(layout &C.PangoLayout, text string, scale_factor f32) []CharRect {
	mut char_rects := []CharRect{cap: text.len}

	// Use iterator for O(N) traversal instead of O(N^2) with index_to_pos
	iter := C.pango_layout_get_iter(layout)
	if iter == unsafe { nil } {
		return char_rects
	}
	defer { C.pango_layout_iter_free(iter) }
	mut iter_exhausted := false

	// Calculate fallback width for zero-width spaces
	pixel_scale := 1.0 / (f32(pango_scale) * scale_factor)
	font_desc := C.pango_layout_get_font_description(layout)
	mut fallback_width := f32(0)
	if font_desc != unsafe { nil } {
		size_pango := C.pango_font_description_get_size(font_desc)
		fallback_width = f32(size_pango) * pixel_scale / 3.0
	}

	for {
		$if debug {
			if iter_exhausted {
				panic('char iterator reused after exhaustion')
			}
		}
		// Get current char index
		idx := C.pango_layout_iter_get_index(iter)

		// If we've gone past valid text, stop (Pango iter can go to end)
		if idx >= text.len {
			break
		}

		pos := C.PangoRectangle{}
		C.pango_layout_iter_get_char_extents(iter, &pos)

		mut final_x := f32(pos.x) * pixel_scale
		mut final_y := f32(pos.y) * pixel_scale
		mut final_w := f32(pos.width) * pixel_scale
		mut final_h := f32(pos.height) * pixel_scale

		if final_w < 0 {
			final_x += final_w
			final_w = -final_w
		}
		if final_h < 0 {
			final_y += final_h
			final_h = -final_h
		}

		// Fix zero-width spaces
		if final_w == 0 && text[idx] == space_char {
			final_w = fallback_width
		}

		char_rects << CharRect{
			rect:  gg.Rect{
				x:      final_x
				y:      final_y
				width:  final_w
				height: final_h
			}
			index: idx
		}

		if !C.pango_layout_iter_next_char(iter) {
			iter_exhausted = true
			break
		}
	}
	return char_rects
}

fn compute_lines(layout &C.PangoLayout, iter &C.PangoLayoutIter, scale_factor f32) []Line {
	line_count := C.pango_layout_get_line_count(layout)
	mut lines := []Line{cap: line_count}
	// Reset iterator to start
	line_iter := C.pango_layout_get_iter(layout)
	defer { C.pango_layout_iter_free(line_iter) }

	for {
		line_ptr := C.pango_layout_iter_get_line_readonly(line_iter)
		if line_ptr != unsafe { nil } {
			rect := C.PangoRectangle{}
			C.pango_layout_iter_get_line_extents(line_iter, unsafe { nil }, &rect)

			// Pango coords to Pixels
			pixel_scale := 1.0 / (f32(pango_scale) * scale_factor)
			mut final_x := f32(rect.x) * pixel_scale
			mut final_y := f32(rect.y) * pixel_scale
			mut final_w := f32(rect.width) * pixel_scale
			mut final_h := f32(rect.height) * pixel_scale

			lines << Line{
				start_index:        line_ptr.start_index
				length:             line_ptr.length
				rect:               gg.Rect{
					x:      final_x
					y:      final_y
					width:  final_w
					height: final_h
				}
				is_paragraph_start: (line_ptr.is_paragraph_start & 1) != 0
			}
		}

		if !C.pango_layout_iter_next_line(line_iter) {
			break
		}
	}
	return lines
}

// LogAttrResult holds both the array and byte-index mapping for log_attrs.
struct LogAttrResult {
	attrs    []LogAttr
	by_index map[int]int // byte index -> attrs array index
}

// extract_log_attrs extracts cursor/word boundary information from PangoLayout.
// Returns LogAttr array indexed by byte position and a mapping from byte index to array index.
// Uses Pango iterator to properly handle multi-byte characters (emoji, CJK, etc).
fn extract_log_attrs(layout &C.PangoLayout, text string) LogAttrResult {
	mut n_attrs := int(0)
	attrs_ptr := C.pango_layout_get_log_attrs_readonly(layout, &n_attrs)
	if attrs_ptr == unsafe { nil } || n_attrs == 0 {
		return LogAttrResult{}
	}

	// Use iterator to map byte indices to log_attr indices
	iter := C.pango_layout_get_iter(layout)
	if iter == unsafe { nil } {
		return LogAttrResult{}
	}
	defer { C.pango_layout_iter_free(iter) }

	mut attrs := []LogAttr{cap: n_attrs}
	mut by_index := map[int]int{}

	// First, convert all Pango attrs to our LogAttr struct
	for i in 0 .. n_attrs {
		pango_attr := unsafe { attrs_ptr[i] }
		attrs << LogAttr{
			is_cursor_position: pango_attr.is_cursor_position != 0
			is_word_start:      pango_attr.is_word_start != 0
			is_word_end:        pango_attr.is_word_end != 0
			is_line_break:      pango_attr.is_line_break != 0
		}
	}

	// Build byte index -> attr index mapping using iterator
	mut attr_idx := 0
	for {
		byte_idx := C.pango_layout_iter_get_index(iter)
		if attr_idx < attrs.len {
			by_index[byte_idx] = attr_idx
		}
		attr_idx++

		if !C.pango_layout_iter_next_char(iter) {
			break
		}
	}

	// Add final position (end of text)
	if attr_idx < attrs.len {
		by_index[text.len] = attr_idx
	}

	return LogAttrResult{
		attrs:    attrs
		by_index: by_index
	}
}

// --- Orientation Helper Functions ---

// init_vertical_pen_horizontal returns initial vertical_pen_y for horizontal layout.
fn init_vertical_pen_horizontal() f64 {
	return f64(0)
}

// init_vertical_pen_vertical returns initial vertical_pen_y for vertical layout.
fn init_vertical_pen_vertical(primary_ascent f64) f64 {
	return primary_ascent
}

// compute_glyph_transform_horizontal returns glyph offsets/advances unchanged.
fn compute_glyph_transform_horizontal(x_off f64, y_off f64, x_adv f64,
	y_adv f64) (f64, f64, f64, f64) {
	return x_off, y_off, x_adv, y_adv
}

// compute_glyph_transform_vertical transforms glyph for vertical stacking.
fn compute_glyph_transform_vertical(x_off f64, y_off f64, x_adv f64, y_adv f64,
	line_height f64) (f64, f64, f64, f64) {
	_ = x_off
	_ = y_adv
	center_offset := (line_height - x_adv) / 2.0
	return center_offset, y_off, 0.0, -line_height
}

// compute_run_position_horizontal returns run position for horizontal text.
fn compute_run_position_horizontal(run_x f64, run_y f64, vertical_pen_y f64) (f64, f64, f64) {
	return run_x, run_y, vertical_pen_y
}

// compute_run_position_vertical transforms run position for vertical stacking.
fn compute_run_position_vertical(run_x f64, run_y f64, vertical_pen_y f64, line_height f64,
	glyph_count int) (f64, f64, f64) {
	_ = run_x
	new_pen_y := vertical_pen_y + line_height * f64(glyph_count)
	return run_y, vertical_pen_y, new_pen_y
}

// compute_dimensions_horizontal returns layout dimensions for horizontal text.
fn compute_dimensions_horizontal(ink_width f32, ink_height f32, pango_scale f32,
	scale_factor f32) (f32, f32) {
	return (ink_width / pango_scale) / scale_factor, (ink_height / pango_scale) / scale_factor
}

// compute_dimensions_vertical returns layout dimensions for vertical text.
fn compute_dimensions_vertical(line_height f32, vertical_pen_y f32) (f32, f32) {
	return line_height, vertical_pen_y
}
