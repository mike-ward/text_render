module vglyph

import log
import os

// FontMetricsEntry stores cached font metrics in Pango units.
struct FontMetricsEntry {
	ascent  int // Pango units
	descent int // Pango units
	linegap int // Pango units (0 if not available)
}

// MetricsCache is an LRU cache for font metrics keyed by (face, size) tuple.
struct MetricsCache {
mut:
	entries      map[u64]FontMetricsEntry
	access_order []u64 // Most recent at end
	capacity     int = 256
	// Profile fields - only accessed when -d profile is used
	hits   int
	misses int
}

fn (mut cache MetricsCache) get(key u64) ?FontMetricsEntry {
	if key in cache.entries {
		$if profile ? {
			cache.hits++
		}
		// Move to end (most recent)
		cache.access_order = cache.access_order.filter(it != key)
		cache.access_order << key
		return cache.entries[key]
	}
	$if profile ? {
		cache.misses++
	}
	return none
}

fn (mut cache MetricsCache) put(key u64, entry FontMetricsEntry) {
	if cache.entries.len >= cache.capacity && key !in cache.entries {
		// Evict oldest (first in access_order)
		if cache.access_order.len > 0 {
			evict_key := cache.access_order[0]
			cache.entries.delete(evict_key)
			cache.access_order.delete(0)
		}
	}
	cache.entries[key] = entry
	// Remove existing position if present, add to end
	cache.access_order = cache.access_order.filter(it != key)
	cache.access_order << key
}

$if profile ? {
	pub struct ProfileMetrics {
	pub mut:
		// Frame timing (nanoseconds)
		layout_time_ns    i64
		rasterize_time_ns i64
		upload_time_ns    i64
		draw_time_ns      i64

		// Cache statistics (INST-03)
		glyph_cache_hits      int
		glyph_cache_misses    int
		glyph_cache_evictions int
		layout_cache_hits     int
		layout_cache_misses   int
		// Note: metrics_cache_hits/misses added in Phase 9 when metrics cache implemented

		// Atlas statistics (INST-05)
		atlas_inserts      int
		atlas_grows        int
		atlas_resets       int
		atlas_used_pixels  i64
		atlas_total_pixels i64
		atlas_page_count   int // Number of active atlas pages

		// Memory tracking (INST-04)
		peak_atlas_bytes    i64
		current_atlas_bytes i64
	}

	// glyph_cache_hit_rate returns glyph cache hit rate as percentage (0-100).
	pub fn (m ProfileMetrics) glyph_cache_hit_rate() f32 {
		total := m.glyph_cache_hits + m.glyph_cache_misses
		if total == 0 {
			return 0.0
		}
		return f32(m.glyph_cache_hits) / f32(total) * 100.0
	}

	// layout_cache_hit_rate returns layout cache hit rate as percentage (0-100).
	pub fn (m ProfileMetrics) layout_cache_hit_rate() f32 {
		total := m.layout_cache_hits + m.layout_cache_misses
		if total == 0 {
			return 0.0
		}
		return f32(m.layout_cache_hits) / f32(total) * 100.0
	}

	// atlas_utilization returns atlas utilization as percentage (0-100).
	pub fn (m ProfileMetrics) atlas_utilization() f32 {
		if m.atlas_total_pixels == 0 {
			return 0.0
		}
		return f32(m.atlas_used_pixels) / f32(m.atlas_total_pixels) * 100.0
	}

	// print_summary outputs all profile metrics to stdout.
	pub fn (m ProfileMetrics) print_summary() {
		total_ns := m.layout_time_ns + m.rasterize_time_ns + m.upload_time_ns + m.draw_time_ns
		println('=== VGlyph Profile Metrics ===')
		println('Frame Time Breakdown:')
		println('  Layout:    ${m.layout_time_ns / 1000} us')
		println('  Rasterize: ${m.rasterize_time_ns / 1000} us')
		println('  Upload:    ${m.upload_time_ns / 1000} us')
		println('  Draw:      ${m.draw_time_ns / 1000} us')
		println('  Total:     ${total_ns / 1000} us')
		glyph_total := m.glyph_cache_hits + m.glyph_cache_misses
		layout_total := m.layout_cache_hits + m.layout_cache_misses
		println('Glyph Cache: ${m.glyph_cache_hit_rate():.1}% (${m.glyph_cache_hits}/${glyph_total}), ${m.glyph_cache_evictions} evictions')
		println('Layout Cache: ${m.layout_cache_hit_rate():.1}% (${m.layout_cache_hits}/${layout_total})')
		println('Atlas: ${m.atlas_page_count} pages, ${m.atlas_utilization():.1}% utilized (${m.atlas_used_pixels}/${m.atlas_total_pixels} px)')
		println('Memory: ${m.current_atlas_bytes / 1024} KB current, ${m.peak_atlas_bytes / 1024} KB peak')
	}
}

pub struct Context {
	ft_lib         &C.FT_LibraryRec
	pango_font_map &C.PangoFontMap
	pango_context  &C.PangoContext
	scale_factor   f32 = 1.0
	scale_inv      f32 = 1.0
mut:
	metrics_cache MetricsCache
pub mut:
	// Profile timing fields - only accessed when -d profile is used
	layout_time_ns i64
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
	safe_scale := if scale_factor > 0 { scale_factor } else { 1.0 }
	C.pango_ft2_font_map_set_resolution(pango_font_map, 72.0 * safe_scale, 72.0 * safe_scale)

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
		scale_factor:   safe_scale
		scale_inv:      1.0 / safe_scale
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

	// Load font to get FT_Face for cache key
	font := C.pango_context_load_font(ctx.pango_context, desc)
	if font == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to load Pango Font')
		return 0
	}
	defer { C.g_object_unref(font) }

	face := C.pango_ft2_font_get_face(font)
	size_units := C.pango_font_description_get_size(desc)
	cache_key := u64(voidptr(face)) ^ (u64(size_units) << 32)

	// Check cache
	if entry := ctx.metrics_cache.get(cache_key) {
		return (f32(entry.ascent + entry.descent) / f32(pango_scale)) / ctx.scale_factor
	}

	// Cache miss: fetch from Pango
	language := C.pango_language_get_default()
	metrics := C.pango_font_get_metrics(font, language)
	if metrics == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to get Pango Font Metrics')
		return 0
	}
	defer { C.pango_font_metrics_unref(metrics) }

	ascent := C.pango_font_metrics_get_ascent(metrics)
	descent := C.pango_font_metrics_get_descent(metrics)

	// Store in cache
	ctx.metrics_cache.put(cache_key, FontMetricsEntry{
		ascent:  ascent
		descent: descent
		linegap: 0
	})

	// descent is positive distance from baseline down even though it's "down"
	return (f32(ascent + descent) / f32(pango_scale)) / ctx.scale_factor
}

// font_metrics returns detailed metrics for the font, including ascender, descender,
// and line gap. All values are in pixels.
pub fn (mut ctx Context) font_metrics(cfg TextConfig) TextMetrics {
	desc := ctx.create_font_description(cfg.style)
	if desc == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to create Pango Font Description')
		return TextMetrics{}
	}
	defer { C.pango_font_description_free(desc) }

	// Load font to get FT_Face for cache key
	font := C.pango_context_load_font(ctx.pango_context, desc)
	if font == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to load Pango Font')
		return TextMetrics{}
	}
	defer { C.g_object_unref(font) }

	face := C.pango_ft2_font_get_face(font)
	size_units := C.pango_font_description_get_size(desc)
	cache_key := u64(voidptr(face)) ^ (u64(size_units) << 32)

	scale := f32(pango_scale) * ctx.scale_factor

	// Check cache
	if entry := ctx.metrics_cache.get(cache_key) {
		ascender_px := f32(entry.ascent) / scale
		descender_px := f32(entry.descent) / scale
		return TextMetrics{
			ascender:  ascender_px
			descender: descender_px
			height:    ascender_px + descender_px
			line_gap:  f32(entry.linegap) / scale
		}
	}

	// Cache miss: fetch from Pango
	language := C.pango_language_get_default()
	metrics := C.pango_font_get_metrics(font, language)
	if metrics == unsafe { nil } {
		log.error('${@FILE_LINE}: Failed to get Pango Font Metrics')
		return TextMetrics{}
	}
	defer { C.pango_font_metrics_unref(metrics) }

	ascent := C.pango_font_metrics_get_ascent(metrics)
	descent := C.pango_font_metrics_get_descent(metrics)

	// Store in cache
	ctx.metrics_cache.put(cache_key, FontMetricsEntry{
		ascent:  ascent
		descent: descent
		linegap: 0
	})

	ascender_px := f32(ascent) / scale
	descender_px := f32(descent) / scale

	return TextMetrics{
		ascender:  ascender_px
		descender: descender_px
		height:    ascender_px + descender_px
		line_gap:  0 // Standard Pango metrics don't typically include line gap separately
	}
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

	// Apply typeface (bold/italic override)
	apply_typeface(desc, style.typeface)

	// Apply variable font axes
	if unsafe { style.features != nil } && style.features.variation_axes.len > 0 {
		mut axes_str := ''
		mut first := true
		for a in style.features.variation_axes {
			if !first {
				axes_str += ','
			}
			axes_str += '${a.tag}=${a.value}'
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

// apply_typeface sets weight/style on a font description based on Typeface enum.
fn apply_typeface(desc &C.PangoFontDescription, typeface Typeface) {
	match typeface {
		.regular {}
		.bold {
			C.pango_font_description_set_weight(desc, .pango_weight_bold)
		}
		.italic {
			C.pango_font_description_set_style(desc, .pango_style_italic)
		}
		.bold_italic {
			C.pango_font_description_set_weight(desc, .pango_weight_bold)
			C.pango_font_description_set_style(desc, .pango_style_italic)
		}
	}
}
