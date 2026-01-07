module vglyph

import log

pub struct Context {
	ft_lib         &C.FT_LibraryRec
	pango_font_map &C.PangoFontMap
	pango_context  &C.PangoContext
}

// new_context initializes the global Pango and FreeType environment.
//
// Operations:
// 1. Boots FreeType.
// 2. Creates Pango Font Map (based on FreeType/FontConfig).
// 3. Creates root Pango Context.
//
// Keep context alive for application duration. Passing this to `layout_text`
// shares the font cache.
pub fn new_context() !&Context {
	// Initialize pointer to null
	mut ft_lib := &C.FT_LibraryRec(unsafe { nil })
	if C.FT_Init_FreeType(&ft_lib) != 0 {
		log.error('${@FILE_LINE}: Failed to initialize FreeType library')
		return error('Failed to initialize FreeType library')
	}

	pango_font_map := C.pango_ft2_font_map_new()
	if voidptr(pango_font_map) == unsafe { nil } {
		C.FT_Done_FreeType(ft_lib)
		log.error('${@FILE_LINE}: Failed to create Pango Font Map')
		return error('Failed to create Pango Font Map')
	}
	// Set default resolution to 96 DPI (standard for screens).
	// This ensures that points (1/72 in) and pixels (1/96 in) are distinct.
	// Without this, Pango defaults to 72 DPI, making 1 pt == 1 px.
	C.pango_ft2_font_map_set_resolution(pango_font_map, 96.0, 96.0)

	pango_context := C.pango_font_map_create_context(pango_font_map)
	if voidptr(pango_context) == unsafe { nil } {
		C.g_object_unref(pango_font_map)
		C.FT_Done_FreeType(ft_lib)
		log.error('${@FILE_LINE}: Failed to create Pango Context')
		return error('Failed to create Pango Context')
	}

	return &Context{
		ft_lib:         ft_lib
		pango_font_map: pango_font_map
		pango_context:  pango_context
	}
}

pub fn (mut ctx Context) free() {
	if voidptr(ctx.pango_context) != unsafe { nil } {
		C.g_object_unref(ctx.pango_context)
	}
	if voidptr(ctx.pango_font_map) != unsafe { nil } {
		C.g_object_unref(ctx.pango_font_map)
	}
	if voidptr(ctx.ft_lib) != unsafe { nil } {
		C.FT_Done_FreeType(ctx.ft_lib)
	}
}

// add_font_file loads a font file from the given path to the Pango context.
// Returns true if successful. Uses FontConfig to register application font.
pub fn (mut ctx Context) add_font_file(path string) bool {
	// Retrieve current FontConfig configuration. Pango uses this by default.
	// Explicit initialization ensures safety when modifying.
	mut config := C.FcConfigGetCurrent()
	if config == unsafe { nil } {
		// Fallback: Initialize config if not currently available.
		config = C.FcInitLoadConfigAndFonts()
		if config == unsafe { nil } {
			log.error('${@FILE_LINE}: FcConfigGetCurrent failed')
			return false
		}
	}

	res := C.FcConfigAppFontAddFile(config, &char(path.str))
	return res == 1
}

// font_height returns the total visual height (ascent + descent) of the font
// described by cfg.
pub fn (mut ctx Context) font_height(cfg TextConfig) f32 {
	real_name := resolve_font_alias(cfg.font_name)
	desc := C.pango_font_description_from_string(real_name.str)
	if desc == unsafe { nil } {
		return 0
	}
	defer { C.pango_font_description_free(desc) }

	// Get metrics
	language := C.pango_language_get_default()
	font := C.pango_context_load_font(ctx.pango_context, desc)
	if font == unsafe { nil } {
		return 0
	}
	defer { C.g_object_unref(font) }

	metrics := C.pango_font_get_metrics(font, language)
	if metrics == unsafe { nil } {
		return 0
	}
	defer { C.pango_font_metrics_unref(metrics) }

	ascent := C.pango_font_metrics_get_ascent(metrics)
	descent := C.pango_font_metrics_get_descent(metrics)

	return f32(ascent + descent) / f32(pango_scale)
}

// resolve_font_name returns the actual font family name that Pango resolves
// for the given font description string. Useful for debugging system font loading.
pub fn (mut ctx Context) resolve_font_name(font_desc_str string) string {
	real_name := resolve_font_alias(font_desc_str)
	desc := C.pango_font_description_from_string(real_name.str)
	if desc == unsafe { nil } {
		return 'Error: Invalid font description'
	}
	defer { C.pango_font_description_free(desc) }

	font := C.pango_context_load_font(ctx.pango_context, desc)
	if font == unsafe { nil } {
		return 'Error: Could not load font'
	}
	defer { C.g_object_unref(font) }

	// Get the FT_Face from the Pango font (specific to pangoft2 backend)
	face := C.pango_ft2_font_get_face(font)
	if face == unsafe { nil } {
		return 'Error: Could not get FT_Face'
	}

	return unsafe { cstring_to_vstring(face.family_name) }
}

fn resolve_font_alias(name string) string {
	$if macos {
		// Pango/FontConfig on macOS often falls back to Verdana for "Sans".
		// We explicitly map common generic names to the System Font (San Francisco).
		// We assume "System Font" is available (loaded in new_context).
		if name == 'Sans-serif' || name == 'Sans' || name == 'System Font' {
			return 'System Font'
		}
	}
	return name
}
