module vglyph

import log
import strings
import time

const space_char = u8(32)

// Coordinate Systems (vglyph conventions):
// - Pango units: 1/PANGO_SCALE of a point (1024 units per point)
// - Logical pixels: 1pt = 1px before DPI scaling
// - Physical pixels: logical * scale_factor (for rasterization)
// - Screen Y: Down is positive (standard graphics convention)
// - Baseline Y: Up is positive (FreeType/typography convention)
//
// Vertical Text Flow:
// - Characters stack top-to-bottom (pen moves DOWN)
// - Each glyph centered horizontally in column
// - Column width = line_height (ascent + descent)

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
//
// Returns error if:
// - text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - Pango layout creation fails
pub fn (mut ctx Context) layout_text(text string, cfg TextConfig) !Layout {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			ctx.layout_time_ns += time.sys_mono_now() - start
		}
	}
	if text.len == 0 {
		return Layout{}
	}

	// Defensive UTF-8 validation (API boundary validates, this is defense-in-depth)
	validate_text_input(text, max_text_length, @FN)!

	mut layout := setup_pango_layout(mut ctx, text, cfg) or {
		log.error('${@FILE_LINE}: ${err.msg()}')
		return err
	}
	defer { layout.free() }

	return build_layout_from_pango(layout, text, ctx.scale_factor, cfg)
}

// layout_rich_text layouts text with multiple styles (RichText).
// It combines the base configuration (cfg) with per-run style overrides.
// It concatenates the text from all runs to form the full paragraph.
//
// Returns error if:
// - any run's text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - Pango layout creation fails
pub fn (mut ctx Context) layout_rich_text(rt RichText, cfg TextConfig) !Layout {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			ctx.layout_time_ns += time.sys_mono_now() - start
		}
	}
	if rt.runs.len == 0 {
		return Layout{}
	}

	// Defensive validation of each run's text (defense-in-depth)
	for run in rt.runs {
		validate_text_input(run.text, max_text_length, @FN)!
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
	mut layout := setup_pango_layout(mut ctx, text, cfg) or {
		log.error('${@FILE_LINE}: ${err.msg()}')
		return err
	}
	defer { layout.free() }

	// 3. Modify attributes with runs
	base_list := layout.get_attributes()
	mut attr_list := PangoAttrList{}

	if base_list != unsafe { nil } {
		attr_list.ptr = C.pango_attr_list_copy(base_list)
		track_attr_list_alloc()
	} else {
		attr_list = new_pango_attr_list()
	}

	// Apply styles from runs
	mut cloned_ids := []string{}
	for run in valid_runs {
		apply_rich_text_style(mut ctx, attr_list, run.style, run.start, run.end, mut cloned_ids)
	}

	layout.set_attributes(attr_list)
	attr_list.free()

	// 4. Process layout
	mut result := build_layout_from_pango(layout, text, ctx.scale_factor, cfg)
	result.cloned_object_ids = cloned_ids
	return result
}

// build_layout_from_pango extracts V Items, Lines, and Rects from a configured PangoLayout.
fn build_layout_from_pango(layout PangoLayout, text string, scale_factor f32,
	cfg TextConfig) Layout {
	// Iterator lifecycle:
	// 1. Create via pango_layout_get_iter (caller owns)
	// 2. Iterate with next_run/next_char/next_line until returns false
	// 3. DO NOT reuse after exhausted - create new iterator
	// 4. MUST free via pango_layout_iter_free (defer handles this)
	mut iter := layout.get_iter()
	if iter.is_nil() {
		// handle error gracefully
		return Layout{}
	}
	defer { iter.free() }
	mut iter_exhausted := false

	// Pre-calculate inverse scale for faster pixel conversion
	pixel_scale := 1.0 / (f64(pango_scale) * f64(scale_factor))

	// Get primary font metrics for vertical alignment of emojis
	mut primary_ascent := f64(0)
	mut primary_descent := f64(0)
	font_desc := C.pango_layout_get_font_description(layout.ptr)
	if font_desc != unsafe { nil } {
		// Create a temporary metrics context
		ctx := C.pango_layout_get_context(layout.ptr)
		lang := C.pango_language_get_default()
		metrics := C.pango_context_get_metrics(ctx, font_desc, lang)
		if metrics != unsafe { nil } {
			val_ascent := C.pango_font_metrics_get_ascent(metrics)
			val_descent := C.pango_font_metrics_get_descent(metrics)
			primary_ascent = f64(val_ascent) * pixel_scale
			primary_descent = f64(val_descent) * pixel_scale
			C.pango_font_metrics_unref(metrics)
		}
	}

	mut all_glyphs := []Glyph{}
	mut items := []Item{}

	// Track cumulative vertical position for vertical text stacking
	mut vertical_pen_y := match cfg.orientation {
		.horizontal { init_vertical_pen_horizontal() }
		.vertical { init_vertical_pen_vertical(primary_ascent) }
	}

	for {
		$if debug {
			if iter_exhausted {
				panic('layout iterator reused after exhaustion')
			}
		}
		run_ptr := C.pango_layout_iter_get_run_readonly(iter.ptr)
		if run_ptr != unsafe { nil } {
			run := unsafe { &C.PangoLayoutRun(run_ptr) }
			vertical_pen_y = process_run(mut items, mut all_glyphs, vertical_pen_y, ProcessRunConfig{
				run:             run
				iter:            iter.ptr
				text:            text
				scale_factor:    scale_factor
				pixel_scale:     pixel_scale
				primary_ascent:  primary_ascent
				primary_descent: primary_descent
				base_color:      cfg.style.color
				orientation:     cfg.orientation
			})
		}

		if !C.pango_layout_iter_next_run(iter.ptr) {
			iter_exhausted = true
			break
		}
	}

	mut char_rects := []CharRect{}
	mut char_rect_by_index := map[int]int{}
	if !cfg.no_hit_testing {
		char_rects = compute_hit_test_rects(layout, text, scale_factor)
		// Build index map for O(1) lookup
		for i, cr in char_rects {
			char_rect_by_index[cr.index] = i
		}
	}
	lines := compute_lines(layout, scale_factor)

	ink_rect := C.PangoRectangle{}
	logical_rect := C.PangoRectangle{}
	C.pango_layout_get_extents(layout.ptr, &ink_rect, &logical_rect)

	// Convert Pango units to pixels
	l_width := (f32(logical_rect.width) / f32(pango_scale)) / scale_factor
	l_height := (f32(logical_rect.height) / f32(pango_scale)) / scale_factor
	mut v_width := (f32(ink_rect.width) / f32(pango_scale)) / scale_factor
	mut v_height := (f32(ink_rect.height) / f32(pango_scale)) / scale_factor

	v_width, v_height = match cfg.orientation {
		.horizontal {
			compute_dimensions_horizontal(f32(ink_rect.width), f32(ink_rect.height), f32(pango_scale),
				scale_factor)
		}
		.vertical {
			compute_dimensions_vertical(l_height, f32(vertical_pen_y))
		}
	}

	// Extract LogAttr data while PangoLayout is still valid
	log_attr_result := extract_log_attrs(layout, text)

	return Layout{
		items:              items
		glyphs:             all_glyphs
		char_rects:         char_rects
		char_rect_by_index: char_rect_by_index
		lines:              lines
		log_attrs:          log_attr_result.attrs
		log_attr_by_index:  log_attr_result.by_index
		width:              l_width
		height:             l_height
		visual_width:       v_width
		visual_height:      v_height
	}
}
