module vglyph

// Test glyph_positions returns correct count and ordering
fn test_glyph_positions_count() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	layout := ctx.layout_text('ABC', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!

	positions := layout.glyph_positions()

	// Should have one GlyphInfo per glyph
	assert positions.len == layout.glyphs.len
	// 'ABC' = 3 single-glyph chars
	assert positions.len == 3
}

// Test advances are positive and x increases
fn test_glyph_positions_advances() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	layout := ctx.layout_text('AB', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!

	positions := layout.glyph_positions()

	assert positions.len == 2
	// First glyph starts at or near 0
	assert positions[0].x >= 0
	// Advances should be positive
	assert positions[0].advance > 0
	assert positions[1].advance > 0
	// Second glyph x > first glyph x
	assert positions[1].x > positions[0].x
}

// Test empty layout returns empty positions
fn test_glyph_positions_empty() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	layout := ctx.layout_text('', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!

	positions := layout.glyph_positions()
	assert positions.len == 0
}

// Test index field matches layout.glyphs array index
fn test_glyph_positions_index() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	layout := ctx.layout_text('Hello', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!

	positions := layout.glyph_positions()

	for i, pos in positions {
		assert pos.index == i
	}
}
