module vglyph

import gg as _

// Test context creation and cleanup
fn test_context_creation() {
	mut ctx := new_context(1.0) or {
		assert false, 'Failed to create context: ${err}'
		return
	}
	ctx.free()
}

// Test basic layout generation
fn test_layout_simple_text() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
		block: BlockStyle{
			width: -1
			align: .left
		}
	}

	layout := ctx.layout_text('Hello World', cfg)!

	// Should have items
	assert layout.items.len > 0

	// Should have char rects equal to text length
	assert layout.char_rects.len == 'Hello World'.len

	// Check content of first item
	$if debug {
		assert layout.items[0].run_text == 'Hello World'
	}
}

// Test empty text
fn test_layout_empty_text() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	}

	layout := ctx.layout_text('', cfg)!

	assert layout.items.len == 0
	assert layout.char_rects.len == 0
}

// Test wrapping
fn test_layout_wrapping() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
		block: BlockStyle{
			width: 50
			wrap:  .word
		}
	}

	text := 'This is a long text that should wrap'
	layout := ctx.layout_text(text, cfg)!

	assert layout.items.len > 1
}

// Test hit testing
fn test_hit_test() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
		block: BlockStyle{
			width: -1
		}
	}

	// "A" is clearly at 0,0
	layout := ctx.layout_text('A', cfg)!

	// Test hit at middle of first char
	index := layout.hit_test(5, 5)

	assert index == 0

	// Test miss
	miss_index := layout.hit_test(-10, -10)
	assert miss_index == -1
}

// Test markup
fn test_layout_markup() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style:      TextStyle{
			font_name: 'Sans 20'
		}
		use_markup: true
	}

	// Text with color
	text := '<span foreground="#FF0000">Red</span>'
	layout := ctx.layout_text(text, cfg)!

	assert layout.items.len > 0

	// Check color of first item
	item := layout.items[0]
	// Correct color should be Red (255, 0, 0, 255)
	assert item.color.r == 255
	assert item.color.g == 0
	assert item.color.b == 0
}

// Test hit test rect
fn test_hit_test_rect() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
		block: BlockStyle{
			width: -1
		}
	}

	layout := ctx.layout_text('A', cfg)!

	// Test hit at middle of first char
	rect := layout.hit_test_rect(5, 5) or {
		assert false, 'Should have hit'
		return
	}

	// Basic validation that we got a reasonable rect
	assert rect.width > 0
	assert rect.height > 0

	// Test miss
	if _ := layout.hit_test_rect(-10, -10) {
		assert false, 'Should have missed'
	}
}

// Test vertical layout dimensions
fn test_vertical_layout_dimensions() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	// Vertical layout should have width < height for stacked text
	mut layout := ctx.layout_text('ABC', TextConfig{
		style:       TextStyle{
			font_name: 'Sans 12'
		}
		orientation: .vertical
	})!
	defer { layout.destroy() }

	// For 3 chars stacked vertically:
	// - visual_width ~ line_height (column width)
	// - visual_height ~ 3 * line_height
	assert layout.visual_height > layout.visual_width, 'vertical text should be taller than wide'
	assert layout.visual_height > 0, 'vertical layout has height'
	assert layout.visual_width > 0, 'vertical layout has width'
}

// Test horizontal layout dimensions (regression guard)
fn test_horizontal_layout_dimensions() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	mut layout := ctx.layout_text('ABC', TextConfig{
		style:       TextStyle{
			font_name: 'Sans 12'
		}
		orientation: .horizontal
	})!
	defer { layout.destroy() }

	// Horizontal text should be wider than tall (single line)
	assert layout.visual_width > layout.visual_height, 'horizontal text should be wider than tall'
}

// Test vertical glyph advances
fn test_vertical_glyph_advances() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	mut layout := ctx.layout_text('AB', TextConfig{
		style:       TextStyle{
			font_name: 'Sans 12'
		}
		orientation: .vertical
	})!
	defer { layout.destroy() }

	// Vertical glyphs should have y_advance (not x_advance)
	if layout.glyphs.len >= 2 {
		glyph := layout.glyphs[0]
		assert glyph.x_advance == 0, 'vertical glyph has no x_advance'
		assert glyph.y_advance != 0, 'vertical glyph has y_advance'
	}
}

// Test log_attrs extraction during layout
fn test_log_attrs_extraction() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	text := 'Hello'
	mut layout := ctx.layout_text(text, TextConfig{
		style: TextStyle{
			font_name: 'Sans 12'
		}
	})!
	defer { layout.destroy() }

	// log_attrs should have len = text.len + 1 (positions before each char + end)
	assert layout.log_attrs.len == text.len + 1, 'log_attrs len should be text.len + 1'
}

// Test get_cursor_pos returns valid geometry
fn test_get_cursor_pos() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	text := 'Hello'
	mut layout := ctx.layout_text(text, TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!
	defer { layout.destroy() }

	// Valid index at start
	pos := layout.get_cursor_pos(0) or {
		assert false, 'cursor pos at 0 should succeed'
		return
	}
	assert pos.height > 0, 'cursor height should be positive'

	// Valid index at end (byte_index == text.len)
	end_pos := layout.get_cursor_pos(text.len) or {
		assert false, 'cursor pos at end should succeed'
		return
	}
	assert end_pos.height > 0, 'cursor height at end should be positive'

	// Invalid index
	if _ := layout.get_cursor_pos(-1) {
		assert false, 'cursor pos at -1 should fail'
	}
	if _ := layout.get_cursor_pos(text.len + 1) {
		assert false, 'cursor pos beyond end should fail'
	}
}
