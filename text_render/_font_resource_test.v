module text_render

fn test_add_font_file() {
	// We test Context directly to avoid initializing the full graphics subsystem (gg/sokol)
	// which can fail in headless test environments.
	mut ctx := new_context() or {
		assert false, 'failed to create context'
		return
	}
	// Clean up valid context
	defer { ctx.free() }

	// Test loading a non-existent file
	assert !ctx.add_font_file('/path/to/non_existent_file.ttf')

	// Test loading an existing file (we use the asset we found earlier)
	font_path := '${@DIR}/../assets/feathericon.ttf'
	if true { // os.exists(font_path) {
		assert ctx.add_font_file(font_path)
	}
}
