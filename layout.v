module vglyph

import gg
import log
import strings

const space_char = u8(32)

// layout_text shapes, wraps, and arranges text using Pango.
//
// Algorithm:
// 1. Create transient `PangoLayout`.
// 2. Apply config: Width, Alignment, Font, Markup.
// 3. Iterate layout to decompose text into visual "Run"s (glyphs sharing font/attrs).
// 4. Extract glyph info (index, position) to V `Item`s.
// 5. "Bake" hit-testing data (char bounding boxes).
//
// Trade-offs:
// - **Performance**: Shaping is expensive. Call only when text changes.
//   Resulting `Layout` is cheap to draw.
// - **Memory**: Duplicates glyph indices/positions to V structs to decouple
//   lifecycle from Pango.
// - **Color**: Manually map Pango attrs to `gg.Color` for rendering. Pango
//   attaches colors as metadata, not to glyphs directly.
pub fn (mut ctx Context) layout_text(text string, cfg TextConfig) !Layout {
	if text.len == 0 {
		return Layout{}
	}

	layout := setup_pango_layout(mut ctx, text, cfg) or {
		log.error('${@FILE_LINE}: ${err.msg()}')
		return err
	}
	defer { C.g_object_unref(layout) }

	return build_layout_from_pango(layout, text, ctx.scale_factor, cfg)
}

// layout_rich_text layouts text with multiple styles (RichText).
// It combines the base configuration (cfg) with per-run style overrides.
// It concatenates the text from all runs to form the full paragraph.
pub fn (mut ctx Context) layout_rich_text(rt RichText, cfg TextConfig) !Layout {
	if rt.runs.len == 0 {
		return Layout{}
	}

	// 1. Build Full Text and Calculate Indices
	mut full_text := strings.new_builder(0)
	// Note: Strings in Pango are byte-indexed. We must track byte offsets.

	// Temporary struct to hold calculated ranges
	struct RunRange {
		start int
		end   int
		style TextStyle
	}

	mut valid_runs := []RunRange{cap: rt.runs.len}

	mut current_idx := 0
	for run in rt.runs {
		full_text.write_string(run.text)
		encoded_len := run.text.len // Byte length
		valid_runs << RunRange{
			start: current_idx
			end:   current_idx + encoded_len
			style: run.style
		}
		current_idx += encoded_len
	}

	text := full_text.str()

	// 2. Setup base layout with global config (font, align, wrap, base color)
	layout := setup_pango_layout(mut ctx, text, cfg) or {
		log.error('${@FILE_LINE}: ${err.msg()}')
		return err
	}
	defer { C.g_object_unref(layout) }

	// 3. Modify attributes with runs
	base_list := C.pango_layout_get_attributes(layout)
	mut attr_list := unsafe { &C.PangoAttrList(nil) }

	if base_list != unsafe { nil } {
		attr_list = C.pango_attr_list_copy(base_list)
	} else {
		attr_list = C.pango_attr_list_new()
	}

	// Apply styles from runs
	for run in valid_runs {
		apply_rich_text_style(mut ctx, attr_list, run.style, run.start, run.end)
	}

	C.pango_layout_set_attributes(layout, attr_list)
	C.pango_attr_list_unref(attr_list)

	// 4. Process layout
	return build_layout_from_pango(layout, text, ctx.scale_factor, cfg)
}

// build_layout_from_pango extracts V Items, Lines, and Rects from a configured PangoLayout.
fn build_layout_from_pango(layout &C.PangoLayout, text string, scale_factor f32, cfg TextConfig) Layout {
	iter := C.pango_layout_get_iter(layout)
	if iter == unsafe { nil } {
		// handle error gracefully
		return Layout{}
	}
	defer { C.pango_layout_iter_free(iter) }

	mut items := []Item{}

	for {
		// PangoLayoutRun is a typedef for PangoGlyphItem
		run_ptr := C.pango_layout_iter_get_run_readonly(iter)
		if run_ptr != unsafe { nil } {
			// Explicit cast since V treats C.PangoGlyphItem and C.PangoLayoutRun as distinct types
			run := unsafe { &C.PangoLayoutRun(run_ptr) }
			item := process_run(run, iter, text, scale_factor)
			if item.glyphs.len > 0 {
				items << item
			}
		}

		if !C.pango_layout_iter_next_run(iter) {
			break
		}
	}

	mut char_rects := []CharRect{}
	if !cfg.no_hit_testing {
		char_rects = compute_hit_test_rects(layout, text, scale_factor)
	}
	lines := compute_lines(layout, iter, scale_factor) // Re-use iter logic or new iter

	ink_rect := C.PangoRectangle{}
	logical_rect := C.PangoRectangle{}
	C.pango_layout_get_extents(layout, &ink_rect, &logical_rect)

	// Convert Pango units to pixels
	l_width := (f32(logical_rect.width) / f32(pango_scale)) / scale_factor
	l_height := (f32(logical_rect.height) / f32(pango_scale)) / scale_factor
	v_width := (f32(ink_rect.width) / f32(pango_scale)) / scale_factor
	v_height := (f32(ink_rect.height) / f32(pango_scale)) / scale_factor

	return Layout{
		items:         items
		char_rects:    char_rects
		lines:         lines
		width:         l_width
		height:        l_height
		visual_width:  v_width
		visual_height: v_height
	}
}

// Helper functions

// setup_pango_layout creates and configures a new PangoLayout object.
// It applies text, markup, wrapping, alignment, and font settings.
fn setup_pango_layout(mut ctx Context, text string, cfg TextConfig) !&C.PangoLayout {
	layout := C.pango_layout_new(ctx.pango_context)
	if layout == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to create Pango Layout')
		return error('Failed to create Pango Layout')
	}

	if cfg.use_markup {
		C.pango_layout_set_markup(layout, text.str, text.len)
	} else {
		C.pango_layout_set_text(layout, text.str, text.len)
	}

	// Apply layout configuration
	// Apply layout configuration
	if cfg.block.width > 0 {
		// Apply DPI scaling to input width (Logical -> Pango Units)
		// block.width (Logical) * scale_factor (DPI) * pango_scale (Pango)
		C.pango_layout_set_width(layout, int(cfg.block.width * ctx.scale_factor * pango_scale))
		pango_wrap := match cfg.block.wrap {
			.word { PangoWrapMode.pango_wrap_word }
			.char { PangoWrapMode.pango_wrap_char }
			.word_char { PangoWrapMode.pango_wrap_word_char }
		}
		C.pango_layout_set_wrap(layout, pango_wrap)
	}
	pango_align := match cfg.block.align {
		.left { PangoAlignment.pango_align_left }
		.center { PangoAlignment.pango_align_center }
		.right { PangoAlignment.pango_align_right }
	}
	C.pango_layout_set_alignment(layout, pango_align)
	if cfg.block.indent != 0 {
		// Apply DPI scaling to indent
		C.pango_layout_set_indent(layout, int(cfg.block.indent * ctx.scale_factor * pango_scale))
	}

	desc := ctx.create_font_description(cfg.style)
	if desc != unsafe { nil } {
		C.pango_layout_set_font_description(layout, desc)
		C.pango_font_description_free(desc)
	}

	// Apply Style Attributes
	// Use PangoAttrList for global styles (merges with markup).
	// Copy existing list or create new to avoid overwriting.
	mut attr_list := unsafe { &C.PangoAttrList(nil) }

	existing_list := C.pango_layout_get_attributes(layout)
	if existing_list != unsafe { nil } {
		attr_list = C.pango_attr_list_copy(existing_list)
	} else {
		attr_list = C.pango_attr_list_new()
	}

	if attr_list != unsafe { nil } {
		// Foreground Color
		// Apply cfg.color unless markup overrides it (markup wins by default).
		if !cfg.use_markup {
			// Pango uses 16-bit colors (0-65535)
			mut fg_attr := C.pango_attr_foreground_new(u16(cfg.style.color.r) << 8, u16(cfg.style.color.g) << 8,
				u16(cfg.style.color.b) << 8)
			// Range covers entire text
			fg_attr.start_index = 0
			fg_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, fg_attr)
		}

		// Background Color
		if cfg.style.bg_color.a > 0 {
			mut bg_attr := C.pango_attr_background_new(u16(cfg.style.bg_color.r) << 8,
				u16(cfg.style.bg_color.g) << 8, u16(cfg.style.bg_color.b) << 8)
			bg_attr.start_index = 0
			bg_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, bg_attr)
		}

		// Underline
		if cfg.style.underline {
			mut u_attr := C.pango_attr_underline_new(.pango_underline_single)
			u_attr.start_index = 0
			u_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, u_attr)
		}

		// Strikethrough
		if cfg.style.strikethrough {
			mut s_attr := C.pango_attr_strikethrough_new(true)
			s_attr.start_index = 0
			s_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, s_attr)
		}

		// OpenType Features
		if unsafe { cfg.style.features != nil } && cfg.style.features.opentype_features.len > 0 {
			mut features_str := ''
			mut first := true
			for k, v in cfg.style.features.opentype_features {
				if !first {
					features_str += ', '
				}
				features_str += '${k}=${v}'
				first = false
			}
			mut f_attr := C.pango_attr_font_features_new(&char(features_str.str))
			f_attr.start_index = 0
			f_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, f_attr)
		}

		C.pango_layout_set_attributes(layout, attr_list)
		C.pango_attr_list_unref(attr_list)
	}

	// Apply Tabs
	if cfg.block.tabs.len > 0 {
		tab_array := C.pango_tab_array_new(cfg.block.tabs.len, 0)
		for i, pos_px in cfg.block.tabs {
			// Pango tabs are in Pango units
			pos_pango := int(pos_px * ctx.scale_factor * pango_scale)
			C.pango_tab_array_set_tab(tab_array, i, .pango_tab_left, pos_pango)
		}
		C.pango_layout_set_tabs(layout, tab_array)
		C.pango_tab_array_free(tab_array)
	}

	return layout
}

struct RunAttributes {
pub mut:
	color             gg.Color
	has_bg_color      bool
	bg_color          gg.Color
	has_underline     bool
	has_strikethrough bool
	is_object         bool
	object_id         string
}

// parse_run_attributes extracts visual properties (color, decorations)
// from Pango attributes.
fn parse_run_attributes(pango_item &C.PangoItem) RunAttributes {
	mut attrs := RunAttributes{
		color:    gg.black
		bg_color: gg.Color{0, 0, 0, 0}
	}

	// Iterate GSList of attributes
	mut curr_attr_node := unsafe { &C.GSList(pango_item.analysis.extra_attrs) }
	if curr_attr_node != unsafe { nil } {
		for {
			unsafe {
				if curr_attr_node == nil {
					break
				}
				attr := &C.PangoAttribute(curr_attr_node.data)
				attr_type := attr.klass.type

				if attr_type == .pango_attr_foreground {
					color_attr := &C.PangoAttrColor(attr)
					attrs.color = gg.Color{
						r: u8(color_attr.color.red >> 8)
						g: u8(color_attr.color.green >> 8)
						b: u8(color_attr.color.blue >> 8)
						a: 255
					}
				} else if attr_type == .pango_attr_background {
					color_attr := &C.PangoAttrColor(attr)
					attrs.has_bg_color = true
					attrs.bg_color = gg.Color{
						r: u8(color_attr.color.red >> 8)
						g: u8(color_attr.color.green >> 8)
						b: u8(color_attr.color.blue >> 8)
						a: 255
					}
				} else if attr_type == .pango_attr_underline {
					int_attr := &C.PangoAttrInt(attr)
					if int_attr.value != int(PangoUnderline.pango_underline_none) {
						attrs.has_underline = true
					}
				} else if attr_type == .pango_attr_strikethrough {
					int_attr := &C.PangoAttrInt(attr)
					if int_attr.value != 0 {
						attrs.has_strikethrough = true
					}
				}
			}
			curr_attr_node = curr_attr_node.next
		}
	}
	// Check for shape/inline object
	// Currently parsing extra_attrs for shape
	mut curr_attr_node2 := unsafe { &C.GSList(pango_item.analysis.extra_attrs) }
	for curr_attr_node2 != unsafe { nil } {
		unsafe {
			attr := &C.PangoAttribute(curr_attr_node2.data)
			if attr.klass.type == .pango_attr_shape {
				shape_attr := &C.PangoAttrShape(attr)
				if shape_attr.data != nil {
					attrs.is_object = true
					attrs.object_id = cstring_to_vstring(&char(shape_attr.data))
				}
			}
		}
		curr_attr_node2 = unsafe { curr_attr_node2.next }
	}

	return attrs
}

struct RunMetrics {
pub mut:
	und_pos      f64
	und_thick    f64
	strike_pos   f64
	strike_thick f64
}

// get_run_metrics fetches metrics (position, thickness) for active decorations
// (underline, strikethrough) using Pango API.
fn get_run_metrics(pango_font &C.PangoFont, language &C.PangoLanguage, attrs RunAttributes) RunMetrics {
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

// process_run converts a single Pango glyph run into a V `Item`.
// Handles attribute parsing, metric calculation, and glyph extraction.
fn process_run(run &C.PangoLayoutRun, iter &C.PangoLayoutIter, text string, scale_factor f32) Item {
	pango_item := run.item
	pango_font := pango_item.analysis.font
	if pango_font == unsafe { nil } {
		return Item{
			ft_face: unsafe { nil }
		}
	}

	ft_face := C.pango_ft2_font_get_face(pango_font)
	if ft_face == unsafe { nil } {
		return Item{
			ft_face: unsafe { nil }
		}
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
	run_x := (f64(logical_rect.x) / f64(pango_scale)) / scale_factor

	baseline_pango := C.pango_layout_iter_get_baseline(iter)
	ascent_pango := baseline_pango - logical_rect.y
	descent_pango := (logical_rect.y + logical_rect.height) - baseline_pango

	run_ascent := (f64(ascent_pango) / f64(pango_scale)) / scale_factor

	run_descent := (f64(descent_pango) / f64(pango_scale)) / scale_factor
	run_y := (f64(baseline_pango) / f64(pango_scale)) / scale_factor

	// Extract glyphs
	glyph_string := run.glyphs
	num_glyphs := glyph_string.num_glyphs
	mut glyphs := []Glyph{cap: num_glyphs}
	mut width := f64(0)
	infos := glyph_string.glyphs

	for i in 0 .. num_glyphs {
		unsafe {
			info := infos[i]
			x_off := (f64(info.geometry.x_offset) / f64(pango_scale)) / scale_factor
			y_off := (f64(info.geometry.y_offset) / f64(pango_scale)) / scale_factor
			x_adv := (f64(info.geometry.width) / f64(pango_scale)) / scale_factor
			y_adv := 0.0

			glyphs << Glyph{
				index:     info.glyph
				x_offset:  x_off
				y_offset:  y_off
				x_advance: x_adv
				y_advance: y_adv
				codepoint: 0
			}
			width += x_adv
		}
	}

	// Get sub-text
	start_index := pango_item.offset
	length := pango_item.length

	// Conditionally include run_text for debug builds
	$if debug {
		run_str := unsafe { (text.str + start_index).vstring_with_len(length) }
		return Item{
			run_text:                run_str
			ft_face:                 ft_face
			glyphs:                  glyphs
			width:                   width
			x:                       run_x
			y:                       run_y
			start_index:             start_index
			length:                  length
			color:                   attrs.color
			has_underline:           attrs.has_underline
			has_strikethrough:       attrs.has_strikethrough
			underline_offset:        metrics.und_pos
			underline_thickness:     metrics.und_thick
			strikethrough_offset:    metrics.strike_pos
			strikethrough_thickness: metrics.strike_thick
			has_bg_color:            attrs.has_bg_color
			bg_color:                attrs.bg_color
			ascent:                  run_ascent
			descent:                 run_descent
			use_original_color:      (ft_face.face_flags & ft_face_flag_color) != 0
		}
	} $else {
		return Item{
			ft_face:                 ft_face
			glyphs:                  glyphs
			width:                   width
			x:                       run_x
			y:                       run_y
			start_index:             start_index
			length:                  length
			color:                   attrs.color
			has_underline:           attrs.has_underline
			has_strikethrough:       attrs.has_strikethrough
			underline_offset:        metrics.und_pos
			underline_thickness:     metrics.und_thick
			strikethrough_offset:    metrics.strike_pos
			strikethrough_thickness: metrics.strike_thick
			has_bg_color:            attrs.has_bg_color
			bg_color:                attrs.bg_color
			ascent:                  run_ascent
			descent:                 run_descent
			use_original_color:      (ft_face.face_flags & ft_face_flag_color) != 0
			is_object:               attrs.is_object
			object_id:               attrs.object_id
		}
	}
}

// compute_hit_test_rects generates bounding boxes for every character
// to enable efficient hit testing.
fn compute_hit_test_rects(layout &C.PangoLayout, text string, scale_factor f32) []CharRect {
	mut char_rects := []CharRect{}
	mut i := 0
	// Calculate fallback width for zero-width spaces
	font_desc := C.pango_layout_get_font_description(layout)
	mut fallback_width := f32(0)
	if font_desc != unsafe { nil } {
		// Size is in Pango units (1/1024)
		size_pango := C.pango_font_description_get_size(font_desc)
		// Approx char width is often 1/2 em or similar. Using a safe 1/3 em for space.
		fallback_width = f32(size_pango) / f32(pango_scale) / 3.0
	}

	for i < text.len {
		pos := C.PangoRectangle{}
		C.pango_layout_index_to_pos(layout, i, &pos)

		mut final_x := (f32(pos.x) / f32(pango_scale)) / scale_factor
		mut final_y := (f32(pos.y) / f32(pango_scale)) / scale_factor
		mut final_w := (f32(pos.width) / f32(pango_scale)) / scale_factor
		mut final_h := (f32(pos.height) / f32(pango_scale)) / scale_factor

		if final_w < 0 {
			final_x += final_w
			final_w = -final_w
		}
		if final_h < 0 {
			final_y += final_h
			final_h = -final_h
		}

		// Fix zero-width spaces
		if final_w == 0 && text[i] == space_char {
			final_w = fallback_width
		}

		char_rects << CharRect{
			rect:  gg.Rect{
				x:      final_x
				y:      final_y
				width:  final_w
				height: final_h
			}
			index: i
		}

		// Iterate runes manually
		mut step := 1
		b := text[i]
		if b >= 0xF0 {
			step = 4
		} else if b >= 0xE0 {
			step = 3
		} else if b >= 0xC0 {
			step = 2
		}
		i += step
	}
	return char_rects
}

fn compute_lines(layout &C.PangoLayout, iter &C.PangoLayoutIter, scale_factor f32) []Line {
	mut lines := []Line{}
	// Reset iterator to start
	// Note: The passed 'iter' might be at the end from previous run iteration.
	// It's safer to create a new one or reset if valid. Pango iterators don't have a reset.
	// So we create a new one.
	line_iter := C.pango_layout_get_iter(layout)
	defer { C.pango_layout_iter_free(line_iter) }

	for {
		line_ptr := C.pango_layout_iter_get_line_readonly(line_iter)
		if line_ptr != unsafe { nil } {
			rect := C.PangoRectangle{}
			C.pango_layout_iter_get_line_extents(line_iter, unsafe { nil }, &rect)

			// Pango coords to Pixels
			mut final_x := (f32(rect.x) / f32(pango_scale)) / scale_factor
			mut final_y := (f32(rect.y) / f32(pango_scale)) / scale_factor
			mut final_w := (f32(rect.width) / f32(pango_scale)) / scale_factor
			mut final_h := (f32(rect.height) / f32(pango_scale)) / scale_factor

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

fn apply_rich_text_style(mut ctx Context, list &C.PangoAttrList, style TextStyle, start int, end int) {
	// 1. Color
	if style.color.a > 0 {
		mut attr := C.pango_attr_foreground_new(u16(style.color.r) << 8, u16(style.color.g) << 8,
			u16(style.color.b) << 8)
		attr.start_index = u32(start)
		attr.end_index = u32(end)
		C.pango_attr_list_insert(list, attr)
	}

	// 2. Background Color
	if style.bg_color.a > 0 {
		mut attr := C.pango_attr_background_new(u16(style.bg_color.r) << 8, u16(style.bg_color.g) << 8,
			u16(style.bg_color.b) << 8)
		attr.start_index = u32(start)
		attr.end_index = u32(end)
		C.pango_attr_list_insert(list, attr)
	}

	// 3. Underline
	if style.underline {
		mut attr := C.pango_attr_underline_new(.pango_underline_single)
		attr.start_index = u32(start)
		attr.end_index = u32(end)
		C.pango_attr_list_insert(list, attr)
	}

	// 4. Strikethrough
	if style.strikethrough {
		mut attr := C.pango_attr_strikethrough_new(true)
		attr.start_index = u32(start)
		attr.end_index = u32(end)
		C.pango_attr_list_insert(list, attr)
	}

	// 5. Font Description (Name, Size, Variations)
	// Set if font_name is defined OR size is defined.
	if style.font_name != '' || style.size > 0 {
		mut desc := unsafe { &C.PangoFontDescription(nil) }

		if style.font_name != '' {
			desc = C.pango_font_description_from_string(style.font_name.str)
		} else {
			desc = C.pango_font_description_new()
		}

		if desc != unsafe { nil } {
			if style.font_name != '' {
				// Resolve aliases (important for 'System Font')
				fam_ptr := C.pango_font_description_get_family(desc)
				fam := if fam_ptr != unsafe { nil } {
					unsafe { cstring_to_vstring(fam_ptr) }
				} else {
					''
				}
				resolved_fam := resolve_family_alias(fam)
				C.pango_font_description_set_family(desc, resolved_fam.str)
			}

			// Apply Variations
			if unsafe { style.features != nil } && style.features.variation_axes.len > 0 {
				mut axes_str := ''
				mut first := true
				for k, v in style.features.variation_axes {
					if !first {
						axes_str += ','
					}
					axes_str += '${k}=${v}'
					first = false
				}
				C.pango_font_description_set_variations(desc, &char(axes_str.str))
			}

			// Apply Explicit Size
			if style.size > 0 {
				C.pango_font_description_set_size(desc, int(style.size * pango_scale))
			}

			// Create attribute
			mut attr := C.pango_attr_font_desc_new(desc)
			attr.start_index = u32(start)
			attr.end_index = u32(end)
			C.pango_attr_list_insert(list, attr)

			C.pango_font_description_free(desc)
		}
	}

	// 6. OpenType Features
	if unsafe { style.features != nil } && style.features.opentype_features.len > 0 {
		mut features_str := ''
		mut first := true
		for k, v in style.features.opentype_features {
			if !first {
				features_str += ', '
			}
			features_str += '${k}=${v}'
			first = false
		}
		mut attr := C.pango_attr_font_features_new(&char(features_str.str))
		attr.start_index = u32(start)
		attr.end_index = u32(end)
		C.pango_attr_list_insert(list, attr)
	}
	// 7. Inline Objects
	if unsafe { style.object != nil } {
		obj := style.object
		// Pango units
		w := int(obj.width * pango_scale)
		h := int(obj.height * pango_scale)
		offset := int(obj.offset * pango_scale)

		// Logical Rect: relative to baseline.
		// y is top of the object. If we align bottom to baseline+offset.
		// Standard: y = -(height) corresponds to sitting ON the baseline.
		// Adjust with offset.
		logical_rect := C.PangoRectangle{
			x:      0
			y:      -h - offset
			width:  w
			height: h
		}
		ink_rect := logical_rect

		// Pass object ID as data.
		// Warning: This assumes obj.id string data remains valid during layout.
		data_ptr := unsafe { obj.id.str }

		mut attr := C.pango_attr_shape_new(&ink_rect, &logical_rect)
		attr.start_index = u32(start)
		attr.end_index = u32(end)

		mut shape_attr := unsafe { &C.PangoAttrShape(attr) }
		shape_attr.data = data_ptr

		C.pango_attr_list_insert(list, attr)
	}
}
