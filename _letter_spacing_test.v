module vglyph

// test_letter_spacing_wider verifies positive letter_spacing
// produces a wider layout than default.
fn test_letter_spacing_wider() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	text := 'ABCDEF'
	base_cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	}
	wide_cfg := TextConfig{
		style: TextStyle{
			font_name:      'Sans 20'
			letter_spacing: 5
		}
	}

	base := ctx.layout_text(text, base_cfg)!
	wide := ctx.layout_text(text, wide_cfg)!

	assert wide.width > base.width, 'positive letter_spacing should widen layout'
}

// test_letter_spacing_narrower verifies negative letter_spacing
// produces a narrower layout than default.
fn test_letter_spacing_narrower() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	text := 'ABCDEF'
	base_cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	}
	tight_cfg := TextConfig{
		style: TextStyle{
			font_name:      'Sans 20'
			letter_spacing: -1
		}
	}

	base := ctx.layout_text(text, base_cfg)!
	tight := ctx.layout_text(text, tight_cfg)!

	assert tight.width < base.width, 'negative letter_spacing should narrow layout'
}

// test_letter_spacing_zero_unchanged verifies zero letter_spacing
// produces the same width as default (no letter_spacing field).
fn test_letter_spacing_zero_unchanged() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	text := 'ABCDEF'
	base_cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	}
	zero_cfg := TextConfig{
		style: TextStyle{
			font_name:      'Sans 20'
			letter_spacing: 0
		}
	}

	base := ctx.layout_text(text, base_cfg)!
	zero := ctx.layout_text(text, zero_cfg)!

	assert zero.width == base.width, 'zero letter_spacing should match default width'
}
