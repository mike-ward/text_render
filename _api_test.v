module vglyph

import gg

fn test_get_cache_key_consistency() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:             ctx
		renderer:        unsafe { nil }
		font_hash_cache: map[string]u64{}
		am:              unsafe { nil }
	}

	cfg1 := TextConfig{
		style: TextStyle{
			font_name: 'Arial 12'
			color:     gg.black
		}
		block: BlockStyle{
			width: 100
			align: .left
		}
	}

	key1 := ts.get_cache_key('hello', cfg1)
	key2 := ts.get_cache_key('hello', cfg1)

	assert key1 != 0
	assert key1 == key2
}

fn test_get_cache_key_diff() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:             ctx
		renderer:        unsafe { nil }
		font_hash_cache: map[string]u64{}
		am:              unsafe { nil }
	}

	cfg1 := TextConfig{
		style: TextStyle{
			font_name: 'Arial 12'
			color:     gg.black
		}
		block: BlockStyle{
			width: 100
			align: .left
		}
	}

	cfg2 := TextConfig{
		style: TextStyle{
			font_name: 'Arial 12'
			color:     gg.black
		}
		block: BlockStyle{
			width: 101 // changed
			align: .left
		}
	}

	key1 := ts.get_cache_key('hello', cfg1)
	key2 := ts.get_cache_key('hello', cfg2)

	assert key1 != key2
}

fn test_get_cache_key_diff_text() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:             ctx
		renderer:        unsafe { nil }
		font_hash_cache: map[string]u64{}
		am:              unsafe { nil }
	}
	cfg1 := TextConfig{
		style: TextStyle{
			font_name: 'Arial 12'
		}
	}

	key1 := ts.get_cache_key('hello', cfg1)
	key2 := ts.get_cache_key('hello world', cfg1)

	assert key1 != key2
}

fn test_get_cache_key_diff_typeface() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:             ctx
		renderer:        unsafe { nil }
		font_hash_cache: map[string]u64{}
		am:              unsafe { nil }
	}

	cfg1 := TextConfig{
		style: TextStyle{
			font_name: 'Arial 12'
			typeface:  .regular
		}
	}

	cfg2 := TextConfig{
		style: TextStyle{
			font_name: 'Arial 12'
			typeface:  .bold
		}
	}

	key1 := ts.get_cache_key('hello', cfg1)
	key2 := ts.get_cache_key('hello', cfg2)

	assert key1 != key2
}

// ============================================================================
// API-level validation integration tests (SEC-01, SEC-02, SEC-03)
// ============================================================================

fn test_api_layout_text_invalid_utf8() {
	// Invalid UTF-8 bytes should be rejected at API boundary
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:      ctx
		renderer: unsafe { nil }
		am:       unsafe { nil }
	}
	cfg := TextConfig{}

	invalid_bytes := [u8(0xff), 0xfe].bytestr()
	ts.layout_text(invalid_bytes, cfg) or {
		assert err.msg().contains('invalid UTF-8')
		return
	}
	assert false, 'Invalid UTF-8 should error'
}

fn test_api_layout_text_empty_string() {
	// Empty string should be rejected
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:      ctx
		renderer: unsafe { nil }
		am:       unsafe { nil }
	}
	cfg := TextConfig{}

	ts.layout_text('', cfg) or {
		assert err.msg().contains('empty string')
		return
	}
	assert false, 'Empty string should error'
}

fn test_api_add_font_file_nonexistent() {
	// Nonexistent font path should return error
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:      ctx
		renderer: unsafe { nil }
		am:       unsafe { nil }
	}

	ts.add_font_file('/nonexistent/path/font.ttf') or {
		assert err.msg().contains('does not exist')
		return
	}
	assert false, 'Nonexistent path should error'
}

fn test_api_add_font_file_path_traversal() {
	// Path traversal should be rejected
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:      ctx
		renderer: unsafe { nil }
		am:       unsafe { nil }
	}

	ts.add_font_file('/fonts/../etc/passwd') or {
		assert err.msg().contains('path traversal')
		return
	}
	assert false, 'Path traversal should error'
}

fn test_api_layout_text_too_long() {
	// Text exceeding max length should be rejected
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:      ctx
		renderer: unsafe { nil }
		am:       unsafe { nil }
	}
	cfg := TextConfig{}

	// Create string > 10KB
	long_text := 'x'.repeat(11000)
	ts.layout_text(long_text, cfg) or {
		assert err.msg().contains('exceeds max')
		return
	}
	assert false, 'Too long text should error'
}

fn test_api_new_text_system_atlas_invalid_dimension() {
	// Zero atlas dimension should error
	// Note: This requires a gg context, so we test the validator directly
	validate_dimension(0, 'atlas_width', 'test') or {
		assert err.msg().contains('must be positive')
		return
	}
	assert false, 'Zero dimension should error'
}

fn test_api_layout_rich_text_invalid_utf8() {
	// Invalid UTF-8 in rich text run should be rejected
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:      ctx
		renderer: unsafe { nil }
		am:       unsafe { nil }
	}
	cfg := TextConfig{}

	invalid_bytes := [u8(0xff), 0xfe].bytestr()
	rt := RichText{
		runs: [
			StyleRun{
				text:  invalid_bytes
				style: TextStyle{}
			},
		]
	}

	ts.layout_rich_text(rt, cfg) or {
		assert err.msg().contains('invalid UTF-8')
		return
	}
	assert false, 'Invalid UTF-8 in rich text should error'
}

fn test_api_layout_text_success() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }
	mut ts := TextSystem{
		ctx:      ctx
		renderer: unsafe { nil }
		am:       unsafe { nil }
	}
	cfg := TextConfig{
		style: TextStyle{
			font_name: 'Sans 12'
		}
	}

	layout := ts.layout_text('Hello World', cfg)!
	assert layout.width > 0
	assert layout.height > 0
}
