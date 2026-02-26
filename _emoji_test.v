module vglyph

// Tests for emoji layout properties that the renderer relies on:
// - use_original_color flag set for color emoji fonts
// - ascent and descent both positive (GPU scaling uses ascent+descent)
// - glyph advances positive and proportional to em height
// - ZWJ sequences produce fewer glyphs than separated codepoints

fn test_emoji_use_original_color() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	mut layout := ctx.layout_text('\U0001F600', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!
	defer { layout.destroy() }

	assert layout.items.len > 0, 'emoji should produce items'

	// Find the emoji item (might be preceded by a text run
	// if Pango splits into separate font runs)
	mut found := false
	for item in layout.items {
		if item.use_original_color {
			found = true
			break
		}
	}
	assert found, 'emoji item should have use_original_color=true'
}

fn test_emoji_ascent_descent_positive() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	mut layout := ctx.layout_text('\U0001F600\U0001F680', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!
	defer { layout.destroy() }

	for item in layout.items {
		if item.use_original_color {
			assert item.ascent > 0, 'emoji ascent must be positive'
			assert item.descent >= 0, 'emoji descent must be non-negative'
			assert item.ascent + item.descent > 0, 'emoji em height (ascent+descent) must be positive for GPU scaling'
		}
	}
}

fn test_emoji_glyph_advances_positive() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	mut layout := ctx.layout_text('\U0001F600\U0001F680\U0001F389', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!
	defer { layout.destroy() }

	for item in layout.items {
		if !item.use_original_color {
			continue
		}
		for i := item.glyph_start; i < item.glyph_start + item.glyph_count; i++ {
			if i >= 0 && i < layout.glyphs.len {
				glyph := layout.glyphs[i]
				if (glyph.index & pango_glyph_unknown_flag) != 0 {
					continue
				}
				assert glyph.x_advance > 0, 'emoji glyph advance must be positive'
			}
		}
	}
}

fn test_emoji_zwj_reduces_glyph_count() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	// Without ZWJ: two separate emoji
	mut layout_sep := ctx.layout_text('\U0001F469\U0001F4BB', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!
	defer { layout_sep.destroy() }

	// With ZWJ: should form single compound emoji
	mut layout_zwj := ctx.layout_text('\U0001F469\u200D\U0001F4BB', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!
	defer { layout_zwj.destroy() }

	// ZWJ sequence should produce fewer or equal glyphs
	assert layout_zwj.glyphs.len <= layout_sep.glyphs.len, 'ZWJ sequence should not produce more glyphs than separated codepoints'
}

fn test_emoji_advance_proportional_to_em_height() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	mut layout := ctx.layout_text('\U0001F600', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!
	defer { layout.destroy() }

	for item in layout.items {
		if !item.use_original_color {
			continue
		}
		em_height := item.ascent + item.descent
		for i := item.glyph_start; i < item.glyph_start + item.glyph_count; i++ {
			if i >= 0 && i < layout.glyphs.len {
				glyph := layout.glyphs[i]
				if (glyph.index & pango_glyph_unknown_flag) != 0 {
					continue
				}
				// Advance should be in the same ballpark as em height
				// (within 2x — guards against wildly wrong values)
				assert glyph.x_advance < em_height * 2.0, 'emoji advance ${glyph.x_advance} should not exceed 2x em height ${em_height}'

				assert glyph.x_advance > em_height * 0.3, 'emoji advance ${glyph.x_advance} should not be less than 0.3x em height ${em_height}'
			}
		}
	}
}
