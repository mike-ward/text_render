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
