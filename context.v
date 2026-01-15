module vglyph

import log
import os

pub struct Context {
	ft_lib         &C.FT_LibraryRec
	pango_font_map &C.PangoFontMap
	pango_context  &C.PangoContext
	scale_factor   f32 = 1.0
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
pub fn new_context(scale_factor f32) !&Context {
	// Initialize pointer to null
	ft_lib := &C.FT_LibraryRec(unsafe { nil })
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
	// Set default resolution to 72 DPI * scale_factor.
	// This ensures that 1 pt == 1 px (logical).
	C.pango_ft2_font_map_set_resolution(pango_font_map, 72.0 * scale_factor, 72.0 * scale_factor)

	pango_context := C.pango_font_map_create_context(pango_font_map)
	if voidptr(pango_context) == unsafe { nil } {
		C.g_object_unref(pango_font_map)
		C.FT_Done_FreeType(ft_lib)
		log.error('${@FILE_LINE}: Failed to create Pango Context')
		return error('Failed to create Pango Context')
	}

	// Auto-register system fonts on macOS
	$if macos {
		// Ensure config is loaded
		mut config := C.FcConfigGetCurrent()
		if config == unsafe { nil } {
			config = C.FcInitLoadConfigAndFonts()
		}
		if config != unsafe { nil } {
			C.FcConfigAppFontAddDir(config, c'/System/Library/Fonts')
			C.FcConfigAppFontAddDir(config, c'/Library/Fonts')
			// User fonts?
            home := os.getenv('HOME')
            if home != '' {
                path := '${home}/Library/Fonts'
			    C.FcConfigAppFontAddDir(config, &char(path.str))
            }
            // Trigger update
            C.pango_fc_font_map_config_changed(pango_font_map)
		}
	}

	return &Context{
		ft_lib:         ft_lib
		pango_font_map: pango_font_map
		pango_context:  pango_context
		scale_factor:   scale_factor
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
	if res == 1 {
		C.pango_fc_font_map_config_changed(ctx.pango_font_map)
		return true
	}
	return false
}

// font_height returns the total visual height (ascent + descent) of the font
// described by cfg.
pub fn (mut ctx Context) font_height(cfg TextConfig) f32 {
	desc := ctx.create_font_description(cfg.style)
	if desc == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to create Pango Font Description')
		return 0
	}
	defer { C.pango_font_description_free(desc) }

	// Get metrics
	language := C.pango_language_get_default()
	font := C.pango_context_load_font(ctx.pango_context, desc)
	if font == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to load Pango Font')
		return 0
	}
	defer { C.g_object_unref(font) }

	metrics := C.pango_font_get_metrics(font, language)
	if metrics == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to get Pango Font Metrics')
		return 0
	}
	defer { C.pango_font_metrics_unref(metrics) }

	ascent := C.pango_font_metrics_get_ascent(metrics)
	descent := C.pango_font_metrics_get_descent(metrics)

	// descent is positive distance from baseline down even though it's "down"
	return (f32(ascent + descent) / f32(pango_scale)) / ctx.scale_factor
}

// resolve_font_name returns the actual font family name that Pango resolves
// for the given font description string. Useful for debugging system font loading.
pub fn (mut ctx Context) resolve_font_name(font_desc_str string) string {
	desc := C.pango_font_description_from_string(font_desc_str.str)
	if desc == unsafe { nil } {
		return 'Error: Invalid font description'
	}
	defer { C.pango_font_description_free(desc) }

	// Resolve aliases
	fam_ptr := C.pango_font_description_get_family(desc)
	fam := if fam_ptr != unsafe { nil } { unsafe { cstring_to_vstring(fam_ptr) } } else { '' }
	resolved_fam := resolve_family_alias(fam)
	C.pango_font_description_set_family(desc, resolved_fam.str)

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

pub fn resolve_font_alias(name string) string {
	// Parse the font description string into a Pango object.
	// This safely handles complex strings like "Sans Bold 17px" without us resolving it manually.
	desc := C.pango_font_description_from_string(name.str)
	if desc == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to create Pango Font Description')
		return name
	}
	defer { C.pango_font_description_free(desc) }

	// Get the family name (comma separated list)
	fam_ptr := C.pango_font_description_get_family(desc)
	fam := if fam_ptr != unsafe { nil } { unsafe { cstring_to_vstring(fam_ptr) } } else { '' }

	// Apply aliases
	resolved_fam := resolve_family_alias(fam)

	// Set the modified family list back to the description
	C.pango_font_description_set_family(desc, resolved_fam.str)

	// Serialize the description back to a string (Pango handles the formatting: "Family List Size Style")
	// Note: Pango might strip some information here, which is why we prefer using `desc` directly in other functions.
	new_str_ptr := C.pango_font_description_to_string(desc)
	if new_str_ptr == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to serialize Pango Font Description')
		return name // Should not happen
	}
	final_name := unsafe { cstring_to_vstring(new_str_ptr) }
	C.g_free(new_str_ptr) // Free the string allocated by Pango

	return final_name
}

fn resolve_family_alias(fam string) string {
	mut new_fam := fam
	$if macos {
		new_fam += ', SF Pro Display, System Font'
	} $else $if windows {
		new_fam += ', Segoe UI'
	} $else {
		// On Linux/BSD, we trust FontConfig to handle aliases (e.g. Sans -> Noto Sans).
		// however, we append 'Sans' to ensuring that we always have a sans-serif fallback if the requested font is missing.
		new_fam += ', Sans'
	}
	return new_fam.trim(', ')
}

// create_font_description helper function to create and configure a PangoFontDescription
// based on the provided TextStyle. It handles font name parsing, alias resolution,
// and variable font axes.
// Caller is responsible for freeing the returned description with pango_font_description_free.
pub fn (mut ctx Context) create_font_description(style TextStyle) &C.PangoFontDescription {
	desc := C.pango_font_description_from_string(style.font_name.str)
	if desc == unsafe { nil } {
		return unsafe { &C.PangoFontDescription(nil) }
	}

	// Resolve and set family aliases
	fam_ptr := C.pango_font_description_get_family(desc)
	fam := if fam_ptr != unsafe { nil } { unsafe { cstring_to_vstring(fam_ptr) } } else { '' }
	resolved_fam := resolve_family_alias(fam)
	C.pango_font_description_set_family(desc, resolved_fam.str)

	// Apply variable font axes
	if style.variation_axes.len > 0 {
		mut axes_str := ''
		mut first := true
		for k, v in style.variation_axes {
			if !first {
				axes_str += ','
			}
			axes_str += '${k}=${v}'
			first = false
		}
		C.pango_font_description_set_variations(desc, &char(axes_str.str))
	}

	// Apply Explicit Size (overrides size in font_name)
	if style.size > 0 {
		// pango_font_description_set_size takes Pango units (1/1024 of a point)
		// We cast to int because pango_scale is 1024 (integer).
		C.pango_font_description_set_size(desc, int(style.size * pango_scale))
	}

	return desc
}
