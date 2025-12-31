module text_render

import gg

pub struct Layout {
pub mut:
	items []Item
}

pub struct Item {
pub:
	run_text string // Useful for debugging or if we need original text
	ft_face  &C.FT_FaceRec
	glyphs   []Glyph
	width    f64
	x        f64 // Run position relative to layout (x)
	y        f64 // Run position relative to layout (baseline y)
	color    gg.Color = gg.Color{255, 255, 255, 255}
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

pub struct TextConfig {
pub:
	font_name  string
	width      int            = -1 // in pixels, -1 or 0 for no limit
	align      PangoAlignment = .pango_align_left
	wrap       PangoWrapMode  = .pango_wrap_word
	use_markup bool
}

pub fn (mut ctx Context) layout_text(text string, cfg TextConfig) !Layout {
	if text.len == 0 {
		return Layout{}
	}

	layout := C.pango_layout_new(ctx.pango_context)
	if voidptr(layout) == unsafe { nil } {
		return error('Failed to create Pango Layout')
	}
	defer { C.g_object_unref(layout) }

	if cfg.use_markup {
		C.pango_layout_set_markup(layout, text.str, text.len)
	} else {
		C.pango_layout_set_text(layout, text.str, text.len)
	}

	// Apply layout configuration
	if cfg.width > 0 {
		C.pango_layout_set_width(layout, cfg.width * pango_scale)
		C.pango_layout_set_wrap(layout, cfg.wrap)
	}
	C.pango_layout_set_alignment(layout, cfg.align)

	desc := C.pango_font_description_from_string(cfg.font_name.str)
	if voidptr(desc) != unsafe { nil } {
		C.pango_layout_set_font_description(layout, desc)
		C.pango_font_description_free(desc)
	}

	iter := C.pango_layout_get_iter(layout)
	if voidptr(iter) == unsafe { nil } {
		return error('Failed to create Pango Layout Iterator')
	}
	defer { C.pango_layout_iter_free(iter) }

	mut items := []Item{}

	for {
		run := C.pango_layout_iter_get_run_readonly(iter)
		if voidptr(run) != unsafe { nil } {
			pango_item := run.item
			pango_font := pango_item.analysis.font

			// Critical: Get FT_Face from PangoFont
			// Pango might return NULL font for generic fallback if not found?
			if voidptr(pango_font) != unsafe { nil } {
				ft_face := C.pango_ft2_font_get_face(pango_font)
				if voidptr(ft_face) != unsafe { nil } {
					// Get color attributes
					// Default to white
					mut item_color := gg.Color{255, 255, 255, 255}

					// Iterate GSList of attributes
					mut curr_attr_node := unsafe { &C.GSList(pango_item.analysis.extra_attrs) }
					// extra_attrs allows NULL if list is empty
					if voidptr(curr_attr_node) != unsafe { nil } {
						unsafe {
							for {
								if voidptr(curr_attr_node) == nil {
									break
								}

								attr := &C.PangoAttribute(curr_attr_node.data)

								// Access the first field 'type' of PangoAttrClass via unsafe cast
								// because 'type' is a reserved keyword in V.
								// struct PangoAttrClass { PangoAttrType type; ... }
								attr_type := *(&PangoAttrType(attr.klass))

								if attr_type == .pango_attr_foreground {
									color_attr := &C.PangoAttrColor(attr)
									// PangoColor is 16-bit (0-65535). Convert to 8-bit.
									item_color = gg.Color{
										r: u8(color_attr.color.red >> 8)
										g: u8(color_attr.color.green >> 8)
										b: u8(color_attr.color.blue >> 8)
										a: 255
									}
								}

								curr_attr_node = curr_attr_node.next
							}
						}
					}

					// Get run extents (for X position)
					logical_rect := C.PangoRectangle{}
					C.pango_layout_iter_get_run_extents(iter, unsafe { nil }, &logical_rect)
					run_x := f64(logical_rect.x) / f64(pango_scale)

					// Get baseline (for Y position) - this is absolute Y within layout of the baseline
					baseline := C.pango_layout_iter_get_baseline(iter)
					run_y := f64(baseline) / f64(pango_scale)

					// Extract glyphs
					glyph_string := run.glyphs
					num_glyphs := glyph_string.num_glyphs
					mut glyphs := []Glyph{cap: num_glyphs}
					mut width := f64(0)

					unsafe {
						// Iterate over C array of PangoGlyphInfo
						infos := glyph_string.glyphs

						for i in 0 .. num_glyphs {
							info := infos[i]

							// Pango uses PANGO_SCALE = 1024. So dividing by 1024.0 gives pixels.
							x_off := f64(info.geometry.x_offset) / f64(pango_scale)
							y_off := f64(info.geometry.y_offset) / f64(pango_scale)
							x_adv := f64(info.geometry.width) / f64(pango_scale)
							y_adv := 0.0 // Horizontal text assumption for now

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
					// Get sub-text for this item
					start_index := pango_item.offset
					length := pango_item.length
					// text is standard string (byte buffer). offset/length are bytes.
					run_str := unsafe { (text.str + start_index).vstring_with_len(length) }

					items << Item{
						run_text: run_str
						ft_face:  ft_face
						glyphs:   glyphs
						width:    width
						x:        run_x
						y:        run_y
						color:    item_color
					}
				}
			}
		}

		if !C.pango_layout_iter_next_run(iter) {
			break
		}
	}

	return Layout{
		items: items
	}
}
