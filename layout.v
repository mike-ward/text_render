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

	// Pre-calculate inverse scale for faster pixel conversion
	pixel_scale := 1.0 / (f64(pango_scale) * f64(scale_factor))

	// Get primary font metrics for vertical alignment of emojis
	mut primary_ascent := f64(0)
	mut primary_descent := f64(0)
	font_desc := C.pango_layout_get_font_description(layout)
	if font_desc != unsafe { nil } {
		// Create a temporary metrics context
		ctx := C.pango_layout_get_context(layout)
		lang := C.pango_language_get_default()
		metrics := C.pango_context_get_metrics(ctx, font_desc, lang)
		if metrics != unsafe { nil } {
			val_ascent := C.pango_font_metrics_get_ascent(metrics)
			val_descent := C.pango_font_metrics_get_descent(metrics)
			// Metrics are in Pango units
			// Metrics are in Pango units
			// pixel_scale already defined above
			primary_ascent = f64(val_ascent) * pixel_scale
			primary_descent = f64(val_descent) * pixel_scale
			C.pango_font_metrics_unref(metrics)
		}
	} else {
		// Fallback if no font desc (unlikely with valid PangoLayout, but possible)
		// Try to get from first run or default?
		// For now leave as 0, centering logic might skip or default.
	}

	mut all_glyphs := []Glyph{}
	mut items := []Item{}

	// Track cumulative vertical position for vertical text stacking
	mut vertical_pen_y := f64(0)
	if cfg.orientation == .vertical {
		// Start at ascent so the first character draws *below* the top edge (y=0).
		// Otherwise, drawing at y=0 puts the ascent part of the glyph above the box.
		vertical_pen_y = primary_ascent
	}

	for {
		// PangoLayoutRun is a typedef for PangoGlyphItem
		run_ptr := C.pango_layout_iter_get_run_readonly(iter)
		if run_ptr != unsafe { nil } {
			// Explicit cast since V treats C.PangoGlyphItem and C.PangoLayoutRun as distinct types
			run := unsafe { &C.PangoLayoutRun(run_ptr) }
			vertical_pen_y = process_run(mut items, mut all_glyphs, vertical_pen_y, ProcessRunConfig{
				run:             run
				iter:            iter
				text:            text
				scale_factor:    scale_factor
				pixel_scale:     pixel_scale
				primary_ascent:  primary_ascent
				primary_descent: primary_descent
				base_color:      cfg.style.color
				orientation:     cfg.orientation
			})
		}

		if !C.pango_layout_iter_next_run(iter) {
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
	lines := compute_lines(layout, iter, scale_factor) // Re-use iter logic or new iter

	ink_rect := C.PangoRectangle{}
	logical_rect := C.PangoRectangle{}
	C.pango_layout_get_extents(layout, &ink_rect, &logical_rect)

	// Convert Pango units to pixels
	l_width := (f32(logical_rect.width) / f32(pango_scale)) / scale_factor
	l_height := (f32(logical_rect.height) / f32(pango_scale)) / scale_factor
	mut v_width := (f32(ink_rect.width) / f32(pango_scale)) / scale_factor
	mut v_height := (f32(ink_rect.height) / f32(pango_scale)) / scale_factor

	// Override dimensions for manually stacked vertical text
	if cfg.orientation == .vertical {
		// Height is the total accumulated vertical pen position
		v_height = f32(vertical_pen_y)

		// Width is effectively the line height of the font (column width)
		// We can approx this with the Pango logical height (which acts as line height for horizontal)
		v_width = l_height
	}

	return Layout{
		items:              items
		glyphs:             all_glyphs
		char_rects:         char_rects
		char_rect_by_index: char_rect_by_index
		lines:              lines
		width:              l_width
		height:             l_height
		visual_width:       v_width
		visual_height:      v_height
	}
}

// Helper functions

// setup_pango_layout creates and configures a new PangoLayout object.
// It applies text, markup, wrapping, alignment, and font settings.
fn setup_pango_layout(mut ctx Context, text string, cfg TextConfig) !&C.PangoLayout {
	// Configure Context Gravity/Orientation
	// We must set this on the context before creating the layout, or call context_changed().
	// Since the context is shared, we should ideally save/restore, but Pango layouts snapshot
	// the context state on creation.
	// Actually, pango_layout_new *refs* the context. So changes to context *might* propagate
	// unless we are careful. But standard practice is set context -> create layout.
	// We'll set it every time to ensure consistency.

	// We use manual stacking for vertical text to ensure 'upright' orientation.
	// So we keep Pango in standard Horizontal mode (Gravity South, Identity Matrix).
	C.pango_context_set_base_gravity(ctx.pango_context, .pango_gravity_south)
	C.pango_context_set_gravity_hint(ctx.pango_context, .pango_gravity_hint_natural)
	C.pango_context_set_matrix(ctx.pango_context, unsafe { nil })
	C.pango_context_changed(ctx.pango_context)

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
			mut sb := strings.new_builder(64)
			for i, f in cfg.style.features.opentype_features {
				if i > 0 {
					sb.write_string(', ')
				}
				sb.write_string(f.tag)
				sb.write_u8(`=`)
				sb.write_string(f.value.str())
			}
			features_str := sb.str()
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
// from Pango attributes in a single pass.
fn parse_run_attributes(pango_item &C.PangoItem) RunAttributes {
	mut attrs := RunAttributes{
		// Default to transparent (0,0,0,0) to indicate "no color attribute"
		color:    gg.Color{0, 0, 0, 0}
		bg_color: gg.Color{0, 0, 0, 0}
	}

	// Single-pass iteration over GSList of attributes
	mut curr_attr_node := unsafe { &C.GSList(pango_item.analysis.extra_attrs) }
	for curr_attr_node != unsafe { nil } {
		unsafe {
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
			} else if attr_type == .pango_attr_shape {
				shape_attr := &C.PangoAttrShape(attr)
				if shape_attr.data != nil {
					attrs.is_object = true
					attrs.object_id = cstring_to_vstring(&char(shape_attr.data))
				}
			}
		}
		curr_attr_node = curr_attr_node.next
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
fn process_run(mut items []Item, mut all_glyphs []Glyph, vertical_pen_y f64, cfg ProcessRunConfig) f64 {
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
		// Logic: Align the visual center of the emoji with the approximate x-height center of the primary font.
		// "Raised" appearance comes from aligning to full ascent (which includes accents/line gap).
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

			mut final_x_off := x_off
			mut final_y_off := y_off
			mut final_x_adv := x_adv
			mut final_y_adv := y_adv

			// Swap coordinates for vertical layout
			if cfg.orientation == .vertical {
				// Manual Vertical Stacking (Text Orientation Upright)
				// We take the Horizontal layout and stack it vertically.
				// Pango gave us Horizontal info:
				// - x_advance: width of char
				// - y_offset: vertical shift (rise/drop) relative to baseline

				// We map:
				// - Advance -> Down (Y)
				// - Offset X -> Offset X (centering?) -> For now keep left aligned or center?
				//   Let's keep coordinates relative to the "Vertical Baseline" (which is the center of column?)
				//   Actually, simplified:
				//   Visual X = Line X (run_y in Pango) + Center Offset?
				//   Visual Y = Pen Y.

				// In this loop, we just store offsets/advances relative to the pen.
				// Pen moves Down (increasing screen Y).
				// Renderer does: cy -= y_advance, so negative y_advance moves down.
				line_height := cfg.primary_ascent + cfg.primary_descent
				final_x_adv = 0.0
				final_y_adv = -line_height // Negative to move pen DOWN

				// Center the glyph horizontally in the "column" defined by line_height
				center_offset := (line_height - x_adv) / 2.0
				final_x_off = center_offset

				// Offsets:
				// x_offset in Pango is horizontal shift. In Vertical, it might mean horizontal shift too.
				// y_offset in Pango is vertical shift.
				// So we generally keep them, but y_offset might need sign flip or adj?
				// Pango Y Up. Screen Y Down.
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

	// Post-process Run coordinates for Vertical
	mut final_run_x := run_x
	mut final_run_y := run_y
	mut new_vertical_pen_y := vertical_pen_y

	if cfg.orientation == .vertical {
		// Vertical text: stack runs vertically using cumulative pen position
		// X position: use baseline (run_y) for horizontal centering
		// Y position: use cumulative vertical_pen_y
		final_run_x = run_y
		final_run_y = vertical_pen_y

		// Advance vertical pen by total height of this run's glyphs
		line_height := cfg.primary_ascent + cfg.primary_descent
		new_vertical_pen_y = vertical_pen_y + line_height * f64(glyph_count)
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

	// Calculate fallback width for zero-width spaces
	pixel_scale := 1.0 / (f32(pango_scale) * scale_factor)
	font_desc := C.pango_layout_get_font_description(layout)
	mut fallback_width := f32(0)
	if font_desc != unsafe { nil } {
		size_pango := C.pango_font_description_get_size(font_desc)
		fallback_width = f32(size_pango) * pixel_scale / 3.0
	}

	for {
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
			break
		}
	}
	return char_rects
}

fn compute_lines(layout &C.PangoLayout, iter &C.PangoLayoutIter, scale_factor f32) []Line {
	line_count := C.pango_layout_get_line_count(layout)
	mut lines := []Line{cap: line_count}
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
				mut sb := strings.new_builder(64)
				for i, a in style.features.variation_axes {
					if i > 0 {
						sb.write_u8(`,`)
					}
					sb.write_string(a.tag)
					sb.write_u8(`=`)
					sb.write_string(a.value.str())
				}
				axes_str := sb.str()
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
		mut sb := strings.new_builder(64)
		for i, f in style.features.opentype_features {
			if i > 0 {
				sb.write_string(', ')
			}
			sb.write_string(f.tag)
			sb.write_u8(`=`)
			sb.write_string(f.value.str())
		}
		features_str := sb.str()
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
