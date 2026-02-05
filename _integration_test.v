module vglyph

import gg

// test_layout_lifecycle verifies context creation and resource cleanup.
fn test_layout_lifecycle() {
	mut ctx := new_context(1.0) or {
		assert false, 'Failed to create context: ${err}'
		return
	}
	assert voidptr(ctx) != unsafe { nil }
	assert voidptr(ctx.pango_context.ptr) != unsafe { nil }
	ctx.free()
}

// test_layout_basic verifies simple text layout generates expected items and dimensions.
fn test_layout_basic() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	}

	text := 'Hello VGlyph'
	layout := ctx.layout_text(text, cfg)!

	assert layout.items.len > 0
	assert layout.width > 0
	assert layout.height > 0
	assert layout.visual_width > 0
	assert layout.visual_height > 0
	
	// UTF-8 check
	utf8_text := 'こんにちは'
	utf8_layout := ctx.layout_text(utf8_text, cfg)!
	assert utf8_layout.items.len > 0
	assert utf8_layout.width > 0
}

// test_layout_rich_text verifies layout with multiple style runs.
fn test_layout_rich_text() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
			color: gg.black
		}
	}

	rt := RichText{
		runs: [
			StyleRun{
				text: 'Red '
				style: TextStyle{
					font_name: 'Sans 20'
					color: gg.red
				}
			},
			StyleRun{
				text: 'Blue'
				style: TextStyle{
					font_name: 'Sans 20'
					color: gg.blue
				}
			},
		]
	}

	layout := ctx.layout_rich_text(rt, cfg)!

	// Pango might merge or split runs depending on shaping, 
	// but we expect at least two items if colors are different and not merged.
	// Actually, PangoFT2 might merge them into one PangoItem if they share the same font,
	// but vglyph's process_run should handle attributes.
	// Wait, Pango attributes are mapped back to Items in build_layout_from_pango.
	
	assert layout.items.len >= 2
	
	// Verify colors (approximate as Pango might have slightly different mapping if using markup, 
	// but here we use layout_rich_text which applies attributes directly).
	mut found_red := false
	mut found_blue := false
	
	for item in layout.items {
		if item.color.r == 255 && item.color.g == 0 && item.color.b == 0 {
			found_red = true
		}
		if item.color.r == 0 && item.color.g == 0 && item.color.b == 255 {
			found_blue = true
		}
	}
	
	assert found_red, 'Red run not found in layout items'
	assert found_blue, 'Blue run not found in layout items'
}

// test_hit_testing verifies character rectangles and hit testing accuracy.
fn test_hit_testing() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	}

	text := 'Test'
	layout := ctx.layout_text(text, cfg)!

	assert layout.char_rects.len == text.len
	
	// Test hit testing on first character 'T'
	// It should be roughly at (0, 0)
	first_char_rect := layout.char_rects[0]
	first_rect := first_char_rect.rect
	assert first_rect.width > 0
	assert first_rect.height > 0
	
	hit_idx := layout.hit_test(first_rect.x + first_rect.width / 2, first_rect.y + first_rect.height / 2)
	assert hit_idx == 0
	
	// Test cursor position
	cursor_pos := layout.get_cursor_pos(0) or { panic('failed to get cursor pos') }
	assert cursor_pos.x == first_rect.x
	assert cursor_pos.height >= first_rect.height

	// Test with multi-byte characters (Japanese 'こんにちは' - 5 chars, 15 bytes)
	utf8_text := 'こんにちは'
	utf8_layout := ctx.layout_text(utf8_text, cfg)!
	assert utf8_layout.char_rects.len == 5 // 5 logical characters
	
	// Byte index of second character 'ん' is 3
	idx_n := utf8_layout.hit_test(utf8_layout.char_rects[1].rect.x + 1, utf8_layout.char_rects[1].rect.y + 1)
	assert idx_n == 3
	
	// Cursor at index 3 should be at the start of 'ん'
	cursor_n := utf8_layout.get_cursor_pos(3) or { panic(err) }
	assert cursor_n.x == utf8_layout.char_rects[1].rect.x
}

// test_vertical_layout verifies vertical orientation transforms.
fn test_vertical_layout() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	text := 'ABC'
	
	// Horizontal for baseline
	h_layout := ctx.layout_text(text, TextConfig{
		style: TextStyle{
			font_name: 'Sans 12'
		}
		orientation: .horizontal
	})!
	
	// Vertical layout
	v_layout := ctx.layout_text(text, TextConfig{
		style: TextStyle{
			font_name: 'Sans 12'
		}
		orientation: .vertical
	})!

	assert v_layout.visual_height > v_layout.visual_width, 'vertical layout should be taller than wide'
	assert v_layout.visual_height > h_layout.visual_height, 'vertical layout should be taller than horizontal'
	
	// In vertical layout, glyphs should have y_advance and zero x_advance
	if v_layout.glyphs.len > 0 {
		g := v_layout.glyphs[0]
		assert g.x_advance == 0
		assert g.y_advance < 0, 'vertical glyph should have negative y_advance to move pen down (cy -= y_adv)'
	}
}
