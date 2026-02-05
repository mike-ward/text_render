module vglyph

import gg
import strings

$if debug {
	__global attr_list_alloc_count = int(0)
}

// track_attr_list_alloc increments debug counter when AttrList created.
fn track_attr_list_alloc() {
	$if debug {
		attr_list_alloc_count++
	}
}

// track_attr_list_free decrements debug counter when AttrList freed.
fn track_attr_list_free() {
	$if debug {
		attr_list_alloc_count--
	}
}

// check_attr_list_leaks panics if any AttrLists leaked. Call at shutdown.
pub fn check_attr_list_leaks() {
	$if debug {
		if attr_list_alloc_count != 0 {
			panic('AttrList leak: ${attr_list_alloc_count} list(s) not freed')
		}
	}
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

// apply_rich_text_style modifies a caller-owned AttrList.
// Caller retains ownership; this function only inserts attributes.
// Attributes inserted become owned by the list (don't free them separately).
fn apply_rich_text_style(mut ctx Context, list &C.PangoAttrList, style TextStyle, start int,
	end int, mut cloned_ids []string) {
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

	// 5. Font Description (Name, Size, Typeface, Variations)
	// Set if font_name, size, or typeface is defined.
	if style.font_name != '' || style.size > 0 || style.typeface != .regular {
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

			// Apply typeface (bold/italic override)
			apply_typeface(desc, style.typeface)

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

		// Clone object ID to ensure lifetime exceeds Pango usage.
		// Skip cloning empty strings (per user decision).
		mut data_ptr := unsafe { nil }
		if obj.id.len > 0 {
			cloned_id := obj.id.clone()
			cloned_ids << cloned_id
			data_ptr = unsafe { cloned_id.str }
		}

		mut attr := C.pango_attr_shape_new(&ink_rect, &logical_rect)
		attr.start_index = u32(start)
		attr.end_index = u32(end)

		mut shape_attr := unsafe { &C.PangoAttrShape(attr) }
		shape_attr.data = data_ptr

		C.pango_attr_list_insert(list, attr)
	}
}
