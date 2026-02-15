module vglyph

import log
import strings

// setup_pango_layout creates and configures a new PangoLayout object.
// It applies text, markup, wrapping, alignment, and font settings.
//
// Returns error if:
// - pango_layout_new returns null (memory allocation failure)
fn setup_pango_layout(mut ctx Context, text string, cfg TextConfig) !PangoLayout {
	// Configure Context Gravity/Orientation
	C.pango_context_set_base_gravity(ctx.pango_context.ptr, .pango_gravity_south)
	C.pango_context_set_gravity_hint(ctx.pango_context.ptr, .pango_gravity_hint_natural)
	C.pango_context_set_matrix(ctx.pango_context.ptr, unsafe { nil })
	C.pango_context_changed(ctx.pango_context.ptr)

	ptr := C.pango_layout_new(ctx.pango_context.ptr)
	if ptr == unsafe { nil } {
		log.error('${@FILE_LINE}: failed to create Pango layout')
		return error('failed to create Pango layout')
	}
	layout := PangoLayout{
		ptr: ptr
	}

	if cfg.use_markup {
		layout.set_markup(text)
	} else {
		layout.set_text(text)
	}

	// Apply layout configuration
	if cfg.block.width > 0 {
		// Apply DPI scaling to input width (Logical -> Pango Units)
		layout.set_width(int(cfg.block.width * ctx.scale_factor * pango_scale))
		pango_wrap := match cfg.block.wrap {
			.word { PangoWrapMode.pango_wrap_word }
			.char { PangoWrapMode.pango_wrap_char }
			.word_char { PangoWrapMode.pango_wrap_word_char }
		}
		layout.set_wrap(pango_wrap)
	}
	pango_align := match cfg.block.align {
		.left { PangoAlignment.pango_align_left }
		.center { PangoAlignment.pango_align_center }
		.right { PangoAlignment.pango_align_right }
	}
	layout.set_alignment(pango_align)
	if cfg.block.indent != 0 {
		// Apply DPI scaling to indent
		layout.set_indent(int(cfg.block.indent * ctx.scale_factor * pango_scale))
	}

	mut desc := ctx.create_font_description(cfg.style)
	if !desc.is_nil() {
		layout.set_font_description(desc)
		desc.free()
	}

	// Apply Style Attributes
	mut attr_list := PangoAttrList{}

	existing_list := layout.get_attributes()
	if existing_list != unsafe { nil } {
		attr_list.ptr = C.pango_attr_list_copy(existing_list)
		track_attr_list_alloc()
	} else {
		attr_list = new_pango_attr_list()
	}

	if !attr_list.is_nil() {
		// Background Color
		if cfg.style.bg_color.a > 0 {
			mut bg_attr := C.pango_attr_background_new(u16(cfg.style.bg_color.r) << 8,
				u16(cfg.style.bg_color.g) << 8, u16(cfg.style.bg_color.b) << 8)
			bg_attr.start_index = 0
			bg_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list.ptr, bg_attr)
		}

		// Underline
		if cfg.style.underline {
			mut u_attr := C.pango_attr_underline_new(.pango_underline_single)
			u_attr.start_index = 0
			u_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list.ptr, u_attr)
		}

		// Strikethrough
		if cfg.style.strikethrough {
			mut s_attr := C.pango_attr_strikethrough_new(true)
			s_attr.start_index = 0
			s_attr.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list.ptr, s_attr)
		}

		// Letter Spacing
		if cfg.style.letter_spacing != 0 {
			spacing := int(cfg.style.letter_spacing * ctx.scale_factor * pango_scale)
			mut ls := C.pango_attr_letter_spacing_new(spacing)
			ls.start_index = 0
			ls.end_index = u32(C.G_MAXUINT)
			C.pango_attr_list_insert(attr_list.ptr, ls)
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
			C.pango_attr_list_insert(attr_list.ptr, f_attr)
		}

		layout.set_attributes(attr_list)
		attr_list.free()
	}

	// Apply Tabs
	if cfg.block.tabs.len > 0 {
		mut tab_array := PangoTabArray{
			ptr: C.pango_tab_array_new(cfg.block.tabs.len, 0)
		}
		for i, pos_px in cfg.block.tabs {
			// Pango tabs are in Pango units
			pos_pango := int(pos_px * ctx.scale_factor * pango_scale)
			C.pango_tab_array_set_tab(tab_array.ptr, i, .pango_tab_left, pos_pango)
		}
		layout.set_tabs(tab_array)
		tab_array.free()
	}

	return layout
}
