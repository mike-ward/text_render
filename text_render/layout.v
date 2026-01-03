module text_render

import gg
import log

pub struct Layout {
pub mut:
	items      []Item
	char_rects []CharRect
}

pub struct CharRect {
pub:
	rect  gg.Rect
	index int // Byte index
}

pub struct Item {
pub:
	run_text string @[if debug] // Useful for debugging or if we need original text
	ft_face  &C.FT_FaceRec
	glyphs   []Glyph
	width    f64
	x        f64 // Run position relative to layout (x)
	y        f64 // Run position relative to layout (baseline y)
	color    gg.Color = gg.black

	// Text Decoration
	has_underline           bool
	has_strikethrough       bool
	underline_offset        f64
	underline_thickness     f64
	strikethrough_offset    f64
	strikethrough_thickness f64

	// Background
	has_bg_color       bool
	bg_color           gg.Color
	ascent             f64
	descent            f64
	use_original_color bool // If true, do not tint the item color (e.g. for Emojis)
}

pub struct Glyph {
pub:
	index     u32
	x_offset  f64
	y_offset  f64
	x_advance f64
	y_advance f64
	codepoint u32 // Optional, might be 0 if not easily tracking back
}

// Alignment specifies the horizontal alignment of the text within its layout box.
pub enum Alignment {
	left   // left aligns the text to the left.
	center // center aligns the text to the center.
	right  // right aligns the text to the right.
}

// WrapMode defines how text should wrap when it exceeds the maximum width.
pub enum WrapMode {
	word      // wrap at word boundaries (e.g. spaces).
	char      // wrap at character boundaries.
	word_char // wrap at word, fallback to char if word too long.
}

// TextConfig holds configuration for text layout and rendering.
pub struct TextConfig {
pub:
	// font_name is a Pango font description string properly formatted as:
	// "[FAMILY-LIST] [STYLE-OPTIONS] [SIZE] [VARIATIONS] [FEATURES]"
	//
	// FAMILY-LIST: Comma-separated list (e.g. "Sans, Helvetica, monospace").
	//
	// STYLE-OPTIONS: Space-separated words from:
	//   Styles:   Normal, Roman, Oblique, Italic
	//   Variants: Small-Caps, All-Small-Caps, Unicase, Title-Caps, etc.
	//   Weights:  Thin, Light, Regular, Medium, Bold, Heavy, Black, etc.
	//   Stretch:  Ultra-Condensed, Condensed, Expanded, Ultra-Expanded, etc.
	//   Gravity:  South, North, East, West, Rotated-Left, Rotated-Right
	//
	// SIZE: Points (decimal e.g. "12") or pixels (e.g. "20px").
	//
	// VARIATIONS: Comma-separated OpenType axis "@axis=value"
	//
	// FEATURES: Comma-separated OpenType features "@feature=value"
	//
	// Example: "Sans Italic Light 15"
	// Ref: https://docs.gtk.org/Pango/type_func.FontDescription.from_string.html
	font_name string
	width     int       = -1    // width is the wrapping width in pixels. Set to -1 or 0 for no wrapping.
	align     Alignment = .left // align controls the horizontal alignment of the text (left, center, right).
	wrap      WrapMode  = .word // wrap controls how text lines are broken (word, char, etc.).
	// use_markup enables Pango markup syntax.
	//
	// Supported tags:
	//   <b>, <i>, <s>, <u>, <tt>, <sub>, <sup>, <small>, <big>
	//
	// The <span> tag supports the following attributes:
	//   font_family (or face), font_desc, size (e.g. "small", "xx-large", "100"), style,
	//   weight, variant, stretch, foreground (or color/fgcolor), background (or bgcolor),
	//   alpha, background_alpha, underline ("none", "single", "double", "low"), underline_color,
	//   rise (vertical offset), strikethrough ("true"/"false"), strikethrough_color,
	//   fallback ("true"/"false"), lang, letter_spacing, gravity, gravity_hint.
	//
	// Example: <span foreground="blue" size="x-large">Blue Text</span>
	//
	// Also see: https://developer.gnome.org/pango/stable/PangoMarkupFormat.html
	use_markup bool

	// Style Overrides (applied to the whole text if checked)
	color         gg.Color = gg.black
	bg_color      gg.Color = gg.Color{0, 0, 0, 0}
	underline     bool
	strikethrough bool
}

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

	iter := C.pango_layout_get_iter(layout)
	if iter == unsafe { nil } {
		return error('Failed to create Pango Layout Iterator')
	}
	defer { C.pango_layout_iter_free(iter) }

	mut items := []Item{}

	for {
		// PangoLayoutRun is a typedef for PangoGlyphItem
		run_ptr := C.pango_layout_iter_get_run_readonly(iter)
		if run_ptr != unsafe { nil } {
			// Explicit cast since V treats C.PangoGlyphItem and C.PangoLayoutRun as distinct types
			run := unsafe { &C.PangoLayoutRun(run_ptr) }
			item := process_run(run, iter, text)
			if item.glyphs.len > 0 {
				items << item
			}
		}

		if !C.pango_layout_iter_next_run(iter) {
			break
		}
	}

	char_rects := compute_hit_test_rects(layout, text)

	return Layout{
		items:      items
		char_rects: char_rects
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
	if cfg.width > 0 {
		C.pango_layout_set_width(layout, cfg.width * pango_scale)
		pango_wrap := match cfg.wrap {
			.word { PangoWrapMode.pango_wrap_word }
			.char { PangoWrapMode.pango_wrap_char }
			.word_char { PangoWrapMode.pango_wrap_word_char }
		}
		C.pango_layout_set_wrap(layout, pango_wrap)
	}
	pango_align := match cfg.align {
		.left { PangoAlignment.pango_align_left }
		.center { PangoAlignment.pango_align_center }
		.right { PangoAlignment.pango_align_right }
	}
	C.pango_layout_set_alignment(layout, pango_align)

	desc := C.pango_font_description_from_string(cfg.font_name.str)
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
			mut fg_attr := C.pango_attr_foreground_new(u16(cfg.color.r) << 8, u16(cfg.color.g) << 8,
				u16(cfg.color.b) << 8)
			// Range covers entire text
			fg_attr.start_index = 0
			fg_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, fg_attr)
		}

		// Background Color
		if cfg.bg_color.a > 0 {
			mut bg_attr := C.pango_attr_background_new(u16(cfg.bg_color.r) << 8, u16(cfg.bg_color.g) << 8,
				u16(cfg.bg_color.b) << 8)
			bg_attr.start_index = 0
			bg_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, bg_attr)
		}

		// Underline
		if cfg.underline {
			mut u_attr := C.pango_attr_underline_new(.pango_underline_single)
			u_attr.start_index = 0
			u_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, u_attr)
		}

		// Strikethrough
		if cfg.strikethrough {
			mut s_attr := C.pango_attr_strikethrough_new(true)
			s_attr.start_index = 0
			s_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list, s_attr)
		}

		C.pango_layout_set_attributes(layout, attr_list)
		C.pango_attr_list_unref(attr_list)
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
fn process_run(run &C.PangoLayoutRun, iter &C.PangoLayoutIter, text string) Item {
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

	run_x := f64(logical_rect.x) / f64(pango_scale)

	baseline_pango := C.pango_layout_iter_get_baseline(iter)
	ascent_pango := baseline_pango - logical_rect.y
	descent_pango := (logical_rect.y + logical_rect.height) - baseline_pango

	run_ascent := f64(ascent_pango) / f64(pango_scale)
	run_descent := f64(descent_pango) / f64(pango_scale)
	run_y := f64(baseline_pango) / f64(pango_scale)

	// Extract glyphs
	glyph_string := run.glyphs
	num_glyphs := glyph_string.num_glyphs
	mut glyphs := []Glyph{cap: num_glyphs}
	mut width := f64(0)
	infos := glyph_string.glyphs

	for i in 0 .. num_glyphs {
		unsafe {
			info := infos[i]
			x_off := f64(info.geometry.x_offset) / f64(pango_scale)
			y_off := f64(info.geometry.y_offset) / f64(pango_scale)
			x_adv := f64(info.geometry.width) / f64(pango_scale)
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
	$if debug {
		run_str := unsafe { (text.str + start_index).vstring_with_len(length) }
		return Item{
			run_text:                run_str
			ft_face:                 ft_face
			glyphs:                  glyphs
			width:                   width
			x:                       run_x
			y:                       run_y
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
	}
}

// compute_hit_test_rects generates bounding boxes for every character
// to enable efficient hit testing.
fn compute_hit_test_rects(layout &C.PangoLayout, text string) []CharRect {
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

		mut final_x := f32(pos.x) / f32(pango_scale)
		mut final_y := f32(pos.y) / f32(pango_scale)
		mut final_w := f32(pos.width) / f32(pango_scale)
		mut final_h := f32(pos.height) / f32(pango_scale)

		if final_w < 0 {
			final_x += final_w
			final_w = -final_w
		}
		if final_h < 0 {
			final_y += final_h
			final_h = -final_h
		}

		// Fix zero-width spaces
		if final_w == 0 && text[i] == 32 {
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

// hit_test_rect returns the bounding box of the character at (x, y) relative to the layout origin.
// Returns none if no character is found close enough.
pub fn (l Layout) hit_test_rect(x f32, y f32) ?gg.Rect {
	for cr in l.char_rects {
		if x >= cr.rect.x && x <= cr.rect.x + cr.rect.width && y >= cr.rect.y
			&& y <= cr.rect.y + cr.rect.height {
			return cr.rect
		}
	}
	return none
}

// hit_test returns the byte index of the character at (x, y) relative to origin.
// Returns -1 if no character is found.
//
// Algorithm:
// Linear search (O(N)) over baked char rects.
// Trade-offs:
// - Efficiency: Faster than spatial structures for typical N < 1000.
// - Accuracy: Returns first matching index (logical order).
pub fn (l Layout) hit_test(x f32, y f32) int {
	// Simple linear search.
	// We could optimize with spatial partitioning if needed.
	for cr in l.char_rects {
		if x >= cr.rect.x && x <= cr.rect.x + cr.rect.width && y >= cr.rect.y
			&& y <= cr.rect.y + cr.rect.height {
			return cr.index
		}
	}
	return -1
}
