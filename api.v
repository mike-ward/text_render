module vglyph

import gg
import sokol.sapp
import time
import math
import accessibility

struct CachedLayout {
mut:
	layout      Layout
	last_access i64
}

pub struct TextSystem {
pub mut:
	composition   CompositionState
	dead_key      DeadKeyState
	ime_apply_fn  fn (text string, user_data voidptr) = unsafe { nil }
	ime_update_fn fn (user_data voidptr)              = unsafe { nil }
	ime_user_data voidptr = unsafe { nil }
mut:
	ctx      &Context
	renderer &Renderer
	cache    map[u64]&CachedLayout
	// Cache pruning only activates when cache exceeds 10,000 entries.
	// Items older than eviction_age (milliseconds) are then removed.
	eviction_age          i64 = 5000 // ms
	am                    &accessibility.AccessibilityManager
	accessibility_enabled bool
	// Performance optimizations
	font_hash_cache map[string]u64
	// Profile fields - only accessed when -d profile is used
	layout_cache_hits   int
	layout_cache_misses int
	eviction_count      int
}

// new_text_system creates a new TextSystem, initializing Pango context and
// Renderer.
//
// Returns error if:
// - FreeType library initialization fails
// - Pango font map creation fails
// - Pango context creation fails
pub fn new_text_system(mut gg_ctx gg.Context) !&TextSystem {
	scale := sapp.dpi_scale()
	tr_ctx := new_context(scale)!
	renderer := new_renderer(mut gg_ctx, scale)
	return &TextSystem{
		ctx:                   tr_ctx
		renderer:              renderer
		cache:                 map[u64]&CachedLayout{}
		font_hash_cache:       map[string]u64{}
		am:                    accessibility.new_accessibility_manager()
		accessibility_enabled: false
		composition:           CompositionState{}
		dead_key:              DeadKeyState{}
	}
}

// new_text_system_atlas_size creates a TextSystem with custom atlas dimensions.
//
// Returns error if:
// - atlas_width or atlas_height is non-positive or exceeds max texture dimension (16384)
// - FreeType/Pango initialization fails (see new_text_system)
pub fn new_text_system_atlas_size(mut gg_ctx gg.Context, atlas_width int,
	atlas_height int) !&TextSystem {
	// Validate atlas dimensions
	validate_dimension(atlas_width, 'atlas_width', @FN)!
	validate_dimension(atlas_height, 'atlas_height', @FN)!

	scale := sapp.dpi_scale()
	tr_ctx := new_context(scale)!
	renderer := new_renderer_atlas_size(mut gg_ctx, atlas_width, atlas_height, scale)
	return &TextSystem{
		ctx:             tr_ctx
		renderer:        renderer
		cache:           map[u64]&CachedLayout{}
		font_hash_cache: map[string]u64{}
		am:              accessibility.new_accessibility_manager()
		composition:     CompositionState{}
		dead_key:        DeadKeyState{}
	}
}

// draw_text renders text string at (x, y) using configuration.
// Handles layout caching to optimize performance for repeated calls.
// [TextConfig](#TextConfig)
//
// Returns error if:
// - text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - null context or renderer
// - layout creation fails
pub fn (mut ts TextSystem) draw_text(x f32, y f32, text string, cfg TextConfig) ! {
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	if ts.renderer == unsafe { nil } {
		return error('null renderer at ${@FILE}:${@LINE}')
	}
	// ts.prune_cache() moved to commit()
	item := ts.get_or_create_layout(text, cfg)!
	ts.renderer.draw_layout(item.layout, x, y)

	if ts.accessibility_enabled {
		update_accessibility(mut ts.am, item.layout, x, y)
	}
}

// text_width calculates width (pixels) of text if rendered with config.
// Useful for layout calculations before rendering. [TextConfig](#TextConfig)
//
// Returns error if:
// - text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - null context
// - layout creation fails
pub fn (mut ts TextSystem) text_width(text string, cfg TextConfig) !f32 {
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	item := ts.get_or_create_layout(text, cfg)!
	return item.layout.width
}

// text_height calculates visual height (pixels) of text.
// Corresponds to vertical space occupied. [TextConfig](#TextConfig)
//
// Returns error if:
// - text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - null context
// - layout creation fails
pub fn (mut ts TextSystem) text_height(text string, cfg TextConfig) !f32 {
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	item := ts.get_or_create_layout(text, cfg)!
	return item.layout.visual_height
}

// font_height returns the true height of the font (ascent + descent) in pixels.
// This is the vertical space the font claims, including descenders, regardless
// of the actual text content. [TextConfig](#TextConfig)
//
// Returns error if:
// - null context
// - font description invalid, font not found, or metrics unavailable
pub fn (mut ts TextSystem) font_height(cfg TextConfig) !f32 {
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	return ts.ctx.font_height(cfg)
}

// font_metrics returns the metrics of the font given the config.
// [TextConfig](#TextConfig)
//
// Returns error if:
// - null context
// - font description invalid, font not found, or metrics unavailable
pub fn (mut ts TextSystem) font_metrics(cfg TextConfig) !TextMetrics {
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	return ts.ctx.font_metrics(cfg)
}

// commit should be called at the end of the frame to upload the texture atlas.
pub fn (mut ts TextSystem) commit() {
	if ts.renderer == unsafe { nil } {
		return
	}
	ts.renderer.commit()
	if ts.accessibility_enabled {
		ts.am.commit()
	}
	ts.prune_cache()
}

// get_atlas_image returns the first glyph atlas page's gg.Image for debugging.
pub fn (ts &TextSystem) get_atlas_image() gg.Image {
	if ts.renderer == unsafe { nil } {
		return gg.Image{}
	}
	if ts.renderer.atlas.pages.len == 0 {
		return gg.Image{}
	}
	return ts.renderer.atlas.pages[0].image
}

// ShelfDebugInfo provides shelf data for visualization.
pub struct ShelfDebugInfo {
pub:
	y      int // Shelf top Y position
	height int // Shelf height
	used_x int // Used horizontal space (cursor_x)
	width  int // Total shelf width
}

// AtlasDebugInfo provides atlas layout info for visualization.
pub struct AtlasDebugInfo {
pub:
	page_width   int
	page_height  int
	shelves      []ShelfDebugInfo
	used_pixels  i64
	total_pixels i64
}

// get_atlas_debug_info returns shelf layout info for visualization.
pub fn (ts &TextSystem) get_atlas_debug_info() AtlasDebugInfo {
	if ts.renderer == unsafe { nil } {
		return AtlasDebugInfo{}
	}
	if ts.renderer.atlas.pages.len == 0 {
		return AtlasDebugInfo{}
	}
	page := ts.renderer.atlas.pages[ts.renderer.atlas.current_page]

	mut shelves := []ShelfDebugInfo{cap: page.shelves.len}
	for shelf in page.shelves {
		shelves << ShelfDebugInfo{
			y:      shelf.y
			height: shelf.height
			used_x: shelf.cursor_x
			width:  shelf.width
		}
	}

	return AtlasDebugInfo{
		page_width:   page.width
		page_height:  page.height
		shelves:      shelves
		used_pixels:  page.used_pixels
		total_pixels: i64(page.width) * i64(page.height)
	}
}

// add_font_file registers a font file (TTF/OTF).
// Once added, refer to font by its family name in TextConfig.font_name.
//
// Returns error if:
// - path is empty, contains traversal (..), or does not exist
// - null context
// - FontConfig initialization fails
// - font file format is invalid
pub fn (mut ts TextSystem) add_font_file(path string) ! {
	// Validate font path first (fail fast on bad input)
	validate_font_path(path, @FN)!
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	ts.ctx.add_font_file(path)!
}

// resolve_font_name returns the actual font family name that Pango resolves
// for the given font description string. Useful for debugging.
//
// Returns error if:
// - null context
// - font description string is invalid
// - font loading fails
pub fn (mut ts TextSystem) resolve_font_name(name string) !string {
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	return ts.ctx.resolve_font_name(name)
}

// layout_text computes the layout for the given text and config.
// This bypasses the cache and returns a new Layout struct.
// Useful for advanced text manipulation (hit testing, measuring).
//
// Returns error if:
// - text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - null context
// - Pango layout creation fails
pub fn (mut ts TextSystem) layout_text(text string, cfg TextConfig) !Layout {
	// Validate text input first (fail fast on bad input)
	validate_text_input(text, max_text_length, @FN)!
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	return ts.ctx.layout_text(text, cfg)
}

// layout_text_cached retrieves a cached layout or wraps text if not in cache.
// Returns a copy of the Layout struct (cheap).
//
// Returns error if:
// - text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - null context
// - Pango layout creation fails
pub fn (mut ts TextSystem) layout_text_cached(text string, cfg TextConfig) !Layout {
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	// ts.prune_cache() moved to commit()
	item := ts.get_or_create_layout(text, cfg)!
	return item.layout
}

// layout_rich_text computes the layout for the given RichText and config.
// Useful for rendering attributed strings.
//
// Returns error if:
// - any run's text is empty, exceeds max length (10KB), or contains invalid UTF-8
// - null context
// - Pango layout creation fails
pub fn (mut ts TextSystem) layout_rich_text(rt RichText, cfg TextConfig) !Layout {
	// Validate each run's text first (fail fast on bad input)
	for run in rt.runs {
		validate_text_input(run.text, max_text_length, @FN)!
	}
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}
	return ts.ctx.layout_rich_text(rt, cfg)
}

// draw_layout renders a pre-computed layout.
pub fn (mut ts TextSystem) draw_layout(l Layout, x f32, y f32) {
	if ts.renderer == unsafe { nil } {
		return
	}
	ts.renderer.draw_layout(l, x, y)
	if ts.accessibility_enabled {
		update_accessibility(mut ts.am, l, x, y)
	}
}

// draw_layout_rotated renders a layout rotated by an angle (radians) around its origin.
pub fn (mut ts TextSystem) draw_layout_rotated(l Layout, x f32, y f32, angle f32) {
	if ts.renderer == unsafe { nil } {
		return
	}
	ts.renderer.draw_layout_rotated(l, x, y, angle)
	if ts.accessibility_enabled {
		// For accessibility, we currently report the un-rotated bounding box at (x,y).
		// Precise rotated bounds for A11y is a future enhancement.
		update_accessibility(mut ts.am, l, x, y)
	}
}

// draw_composition renders IME preedit visual feedback (clause underlines and cursor).
// Per CONTEXT.md: thick underline for selected clause, thin for others, cursor ~70% opacity.
pub fn (mut ts TextSystem) draw_composition(layout Layout, x f32, y f32, cs &CompositionState,
	cursor_color gg.Color) {
	if ts.renderer == unsafe { nil } {
		return
	}
	ts.renderer.draw_composition(layout, x, y, cs, cursor_color)
}

// reset_ime_state resets both composition and dead key state.
pub fn (mut ts TextSystem) reset_ime_state() {
	ts.composition.reset()
	ts.dead_key.reset()
}

// is_composing returns true if an IME composition is currently active.
pub fn (ts &TextSystem) is_composing() bool {
	return ts.composition.is_composing()
}

// enable_accessibility toggles automatic accessibility updates.
// When enabled, draw_text and draw_layout will automatically update the accessibility tree.
pub fn (mut ts TextSystem) enable_accessibility(enabled bool) {
	ts.accessibility_enabled = enabled
}

// accessibility_manager returns the internal AccessibilityManager.
pub fn (ts &TextSystem) accessibility_manager() &accessibility.AccessibilityManager {
	return ts.am
}

// update_accessibility publishes the layout to the accessibility tree.
// This should be called after drawing logic if accessibility support is desired.
pub fn (mut ts TextSystem) update_accessibility(l Layout, x f32, y f32) {
	update_accessibility(mut ts.am, l, x, y)
}

// get_or_create_layout retrieves a cached layout or creates a new one.
// Updates the last access time for cache eviction tracking.
fn (mut ts TextSystem) get_or_create_layout(text string, cfg TextConfig) !&CachedLayout {
	// Validate text input first (fail fast on bad input)
	validate_text_input(text, max_text_length, @FN)!
	if ts.ctx == unsafe { nil } {
		return error('null context at ${@FILE}:${@LINE}')
	}

	key := ts.get_cache_key(text, &cfg)

	if key in ts.cache {
		$if profile ? {
			ts.layout_cache_hits++
		}
		// unreachable: map access after 'key in ts.cache' check
		mut item := ts.cache[key] or { panic('unreachable') }
		item.last_access = time.ticks()
		return item
	}

	$if profile ? {
		ts.layout_cache_misses++
	}

	layout := ts.ctx.layout_text(text, cfg)!
	new_item := &CachedLayout{
		layout:      layout
		last_access: time.ticks()
	}
	ts.cache[key] = new_item
	return new_item
}

// Internal Helpers

// FNV-1a 64-bit hash constants
const fnv_offset_basis = u64(14695981039346656037)
const fnv_prime = u64(1099511628211)

// fnv_hash_string hashes a string into an existing hash value using FNV-1a
@[inline]
fn fnv_hash_string(h u64, s string) u64 {
	mut hash := h
	unsafe {
		mut ptr := s.str
		end := ptr + s.len
		for ptr < end {
			hash ^= u64(*ptr)
			hash *= fnv_prime
			ptr++
		}
	}
	return hash
}

// fnv_hash_u64 hashes a u64 value into an existing hash
@[inline]
fn fnv_hash_u64(h u64, v u64) u64 {
	mut hash := h
	hash ^= v
	hash *= fnv_prime
	return hash
}

// fnv_hash_f32 hashes a f32 value into an existing hash
@[inline]
fn fnv_hash_f32(h u64, v f32) u64 {
	return fnv_hash_u64(h, math.f32_bits(v))
}

// fnv_hash_color hashes a gg.Color into an existing hash
@[inline]
fn fnv_hash_color(h u64, c gg.Color) u64 {
	color_u32 := u32(c.r) | (u32(c.g) << 8) | (u32(c.b) << 16) | (u32(c.a) << 24)
	return fnv_hash_u64(h, u64(color_u32))
}

fn (mut ts TextSystem) get_cache_key(text string, cfg &TextConfig) u64 {
	mut hash := fnv_offset_basis

	// Hash text
	hash = fnv_hash_string(hash, text)

	// Separator
	hash = fnv_hash_u64(hash, u64(124)) // '|'

	// Hash TextStyle
	hash = fnv_hash_string(hash, cfg.style.font_name)

	hash = fnv_hash_f32(hash, cfg.style.size)
	hash = fnv_hash_color(hash, cfg.style.color)
	hash = fnv_hash_color(hash, cfg.style.bg_color)

	// Pack scalar fields to reduce FNV calls:
	// typeface (4 bits), underline (1), strikethrough (1), align (4), wrap (4),
	// use_markup (1), no_hit_testing (1), orientation (4)
	mut packed := u64(cfg.style.typeface)
	if cfg.style.underline {
		packed |= u64(1) << 4
	}
	if cfg.style.strikethrough {
		packed |= u64(1) << 5
	}
	packed |= u64(cfg.block.align) << 6
	packed |= u64(cfg.block.wrap) << 10
	if cfg.use_markup {
		packed |= u64(1) << 14
	}
	if cfg.no_hit_testing {
		packed |= u64(1) << 15
	}
	packed |= u64(cfg.orientation) << 16
	hash = fnv_hash_u64(hash, packed)

	// Features
	if cfg.style.features != unsafe { nil } {
		for f in cfg.style.features.opentype_features {
			hash = fnv_hash_string(hash, f.tag)
			hash = fnv_hash_u64(hash, u64(f.value))
		}
		for a in cfg.style.features.variation_axes {
			hash = fnv_hash_string(hash, a.tag)
			hash = fnv_hash_f32(hash, a.value)
		}
	}

	// Inline Object
	if cfg.style.object != unsafe { nil } {
		hash = fnv_hash_string(hash, cfg.style.object.id)
		hash = fnv_hash_f32(hash, cfg.style.object.width)
		hash = fnv_hash_f32(hash, cfg.style.object.height)
		hash = fnv_hash_f32(hash, cfg.style.object.offset)
	}

	// Hash remaining BlockStyle
	hash = fnv_hash_f32(hash, cfg.block.width)
	hash = fnv_hash_f32(hash, cfg.block.indent)

	for t in cfg.block.tabs {
		hash = fnv_hash_u64(hash, u64(t))
	}

	return hash
}

fn (mut ts TextSystem) prune_cache() {
	now := time.ticks()

	if ts.cache.len < 10_000 {
		return
	}

	// Mark-and-sweep: collect keys to delete first, then delete
	mut to_delete := []u64{cap: ts.cache.len / 4}
	for k, item in ts.cache {
		if now - item.last_access > ts.eviction_age {
			to_delete << k
		}
	}
	for k in to_delete {
		ts.cache.delete(k)
		$if profile ? {
			ts.eviction_count++
		}
	}
}

$if profile ? {
	// get_profile_metrics returns aggregated profiling metrics from all subsystems.
	// Combines: Context timing, Renderer cache/timing, GlyphAtlas memory, TextSystem layout cache.
	// This is the primary API for accessing profiling data.
	pub fn (ts &TextSystem) get_profile_metrics() ProfileMetrics {
		// Calculate atlas utilization across all pages
		mut used_pixels := i64(0)
		mut total_pixels := i64(0)
		for page in ts.renderer.atlas.pages {
			used_pixels += page.used_pixels
			total_pixels += i64(page.width) * i64(page.height)
		}

		return ProfileMetrics{
			// Timing from Context (layout) and Renderer (rasterize/upload/draw)
			layout_time_ns:    ts.ctx.layout_time_ns
			rasterize_time_ns: ts.renderer.rasterize_time_ns
			upload_time_ns:    ts.renderer.upload_time_ns
			draw_time_ns:      ts.renderer.draw_time_ns
			// Glyph cache from Renderer
			glyph_cache_hits:      ts.renderer.glyph_cache_hits
			glyph_cache_misses:    ts.renderer.glyph_cache_misses
			glyph_cache_evictions: ts.renderer.glyph_cache_evictions
			// Layout cache from TextSystem
			layout_cache_hits:      ts.layout_cache_hits
			layout_cache_misses:    ts.layout_cache_misses
			layout_cache_evictions: ts.eviction_count
			layout_cache_size:      ts.cache.len
			// Atlas from GlyphAtlas (via Renderer)
			atlas_inserts:      ts.renderer.atlas.atlas_inserts
			atlas_grows:        ts.renderer.atlas.atlas_grows
			atlas_resets:       ts.renderer.atlas.atlas_resets
			atlas_used_pixels:  used_pixels
			atlas_total_pixels: total_pixels
			atlas_page_count:   ts.renderer.atlas.pages.len
			// Memory from GlyphAtlas
			current_atlas_bytes: ts.renderer.atlas.current_atlas_bytes
			peak_atlas_bytes:    ts.renderer.atlas.peak_atlas_bytes
		}
	}

	// reset_profile_metrics clears all profiling counters across all subsystems.
	pub fn (mut ts TextSystem) reset_profile_metrics() {
		// Reset Context timing
		ts.ctx.layout_time_ns = 0

		// Reset Renderer timing and cache
		ts.renderer.rasterize_time_ns = 0
		ts.renderer.upload_time_ns = 0
		ts.renderer.draw_time_ns = 0
		ts.renderer.glyph_cache_hits = 0
		ts.renderer.glyph_cache_misses = 0
		ts.renderer.glyph_cache_evictions = 0

		// Reset TextSystem layout cache counters
		ts.layout_cache_hits = 0
		ts.layout_cache_misses = 0
		ts.eviction_count = 0

		// Note: Don't reset atlas counters - they represent lifetime stats
	}

	// set_async_uploads toggles async texture upload mode (profiling only).
	pub fn (mut ts TextSystem) set_async_uploads(enabled bool) {
		ts.renderer.atlas.async_uploads = enabled
	}
}

// set_async_uploads_diag toggles async texture upload mode (diagnostic builds only).
$if diag ? {
	pub fn (mut ts TextSystem) set_async_uploads_diag(enabled bool) {
		ts.renderer.atlas.async_uploads = enabled
	}
}
