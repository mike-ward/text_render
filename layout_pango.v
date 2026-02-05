module vglyph

import log
import strings

// setup_pango_layout creates and configures a new PangoLayout object.
// It applies text, markup, wrapping, alignment, and font settings.
//
// Returns error if:
// - pango_layout_new returns null (memory allocation failure)
fn setup_pango_layout(mut ctx Context, text string, cfg TextConfig) !&C.PangoLayout {
	// Configure Context Gravity/Orientation
	C.pango_context_set_base_gravity(ctx.pango_context, .pango_gravity_south)
	C.pango_context_set_gravity_hint(ctx.pango_context, .pango_gravity_hint_natural)
	C.pango_context_set_matrix(ctx.pango_context, unsafe { nil })
	C.pango_context_changed(ctx.pango_context)

	layout := C.pango_layout_new(ctx.pango_context)
	if layout == unsafe { nil } {
		log.error('${@FILE_LINE}: failed to create Pango layout')
		return error('failed to create Pango layout')
	}

	if cfg.use_markup {
		C.pango_layout_set_markup(layout, text.str, text.len)
	} else {
		C.pango_layout_set_text(layout, text.str, text.len)
	}

	// Apply layout configuration
	if cfg.block.width > 0 {
		// Apply DPI scaling to input width (Logical -> Pango Units)
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
	mut attr_list := unsafe { &C.PangoAttrList(nil) }

	existing_list := C.pango_layout_get_attributes(layout)
	if existing_list != unsafe { nil } {
		attr_list = C.pango_attr_list_copy(existing_list)
		track_attr_list_alloc()
	} else {
		attr_list = C.pango_attr_list_new()
		track_attr_list_alloc()
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
		track_attr_list_free()
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
