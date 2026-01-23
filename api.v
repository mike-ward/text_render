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
mut:
	ctx      &Context
	renderer &Renderer
	cache    map[u64]&CachedLayout
	// Cache pruning only activates when cache exceeds 10,000 entries.
	// Items older than eviction_age (milliseconds) are then removed.
	eviction_age          i64 = 5000 // ms
	am                    &accessibility.AccessibilityManager
	accessibility_enabled bool
}

// new_text_system creates a new TextSystem, initializing Pango context and
// Renderer.
pub fn new_text_system(mut gg_ctx gg.Context) !&TextSystem {
	scale := sapp.dpi_scale()
	tr_ctx := new_context(scale)!
	renderer := new_renderer(mut gg_ctx, scale)
	return &TextSystem{
		ctx:                   tr_ctx
		renderer:              renderer
		cache:                 map[u64]&CachedLayout{}
		am:                    accessibility.new_accessibility_manager()
		accessibility_enabled: false
	}
}

pub fn new_text_system_atlas_size(mut gg_ctx gg.Context, atlas_width int, atlas_height int) !&TextSystem {
	scale := sapp.dpi_scale()
	tr_ctx := new_context(scale)!
	renderer := new_renderer_atlas_size(mut gg_ctx, atlas_width, atlas_height, scale)
	return &TextSystem{
		ctx:      tr_ctx
		renderer: renderer
		cache:    map[u64]&CachedLayout{}
		am:       accessibility.new_accessibility_manager()
	}
}

// draw_text renders text string at (x, y) using configuration.
// Handles layout caching to optimize performance for repeated calls.
// [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) draw_text(x f32, y f32, text string, cfg TextConfig) ! {
	// ts.prune_cache() moved to commit()
	item := ts.get_or_create_layout(text, cfg)!
	ts.renderer.draw_layout(item.layout, x, y)

	if ts.accessibility_enabled {
		update_accessibility(mut ts.am, item.layout, x, y)
	}
}

// text_width calculates width (pixels) of text if rendered with config.
// Useful for layout calculations before rendering. [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) text_width(text string, cfg TextConfig) !f32 {
	item := ts.get_or_create_layout(text, cfg)!
	return item.layout.width
}

// text_height calculates visual height (pixels) of text.
// Corresponds to vertical space occupied. [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) text_height(text string, cfg TextConfig) !f32 {
	item := ts.get_or_create_layout(text, cfg)!
	return item.layout.visual_height
}

// font_height returns the true height of the font (ascent + descent) in pixels.
// This is the vertical space the font claims, including descenders, regardless
// of the actual text content. [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) font_height(cfg TextConfig) f32 {
	return ts.ctx.font_height(cfg)
}

// font_metrics returns the metrics of the font given the config.
// [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) font_metrics(cfg TextConfig) TextMetrics {
	return ts.ctx.font_metrics(cfg)
}

// commit should be called at the end of the frame to upload the texture atlas.
pub fn (mut ts TextSystem) commit() {
	ts.renderer.commit()
	if ts.accessibility_enabled {
		ts.am.commit()
	}
	ts.prune_cache()
}

pub fn (ts &TextSystem) get_atlas_image() gg.Image {
	return ts.renderer.atlas.image
}

// add_font_file registers a font file (TTF/OTF). Returns true if successful.
// Once added, refer to font by its family name in TextConfig.font_name.
pub fn (mut ts TextSystem) add_font_file(path string) bool {
	return ts.ctx.add_font_file(path)
}

// resolve_font_name returns the actual font family name that Pango resolves
// for the given font description string. Useful for debugging.
pub fn (mut ts TextSystem) resolve_font_name(name string) string {
	return ts.ctx.resolve_font_name(name)
}

// layout_text computes the layout for the given text and config.
// This bypasses the cache and returns a new Layout struct.
// Useful for advanced text manipulation (hit testing, measuring).
pub fn (mut ts TextSystem) layout_text(text string, cfg TextConfig) !Layout {
	return ts.ctx.layout_text(text, cfg)
}

// layout_text_cached retrieves a cached layout or wraps text if not in cache.
// Returns a copy of the Layout struct (cheap).
pub fn (mut ts TextSystem) layout_text_cached(text string, cfg TextConfig) !Layout {
	// ts.prune_cache() moved to commit()
	item := ts.get_or_create_layout(text, cfg)!
	return item.layout
}

// layout_rich_text computes the layout for the given RichText and config.
// Useful for rendering attributed strings.
pub fn (mut ts TextSystem) layout_rich_text(rt RichText, cfg TextConfig) !Layout {
	return ts.ctx.layout_rich_text(rt, cfg)
}

// draw_layout renders a pre-computed layout.
pub fn (mut ts TextSystem) draw_layout(l Layout, x f32, y f32) {
	ts.renderer.draw_layout(l, x, y)
	if ts.accessibility_enabled {
		update_accessibility(mut ts.am, l, x, y)
	}
}

// draw_layout_rotated renders a layout rotated by an angle (radians) around its origin.
pub fn (mut ts TextSystem) draw_layout_rotated(l Layout, x f32, y f32, angle f32) {
	ts.renderer.draw_layout_rotated(l, x, y, angle)
	if ts.accessibility_enabled {
		// For accessibility, we currently report the un-rotated bounding box at (x,y).
		// Precise rotated bounds for A11y is a future enhancement.
		update_accessibility(mut ts.am, l, x, y)
	}
}

// enable_accessibility toggles automatic accessibility updates.
// When enabled, draw_text and draw_layout will automatically update the accessibility tree.
pub fn (mut ts TextSystem) enable_accessibility(enabled bool) {
	ts.accessibility_enabled = enabled
}

// update_accessibility publishes the layout to the accessibility tree.
// This should be called after drawing logic if accessibility support is desired.
pub fn (mut ts TextSystem) update_accessibility(l Layout, x f32, y f32) {
	update_accessibility(mut ts.am, l, x, y)
}

// get_or_create_layout retrieves a cached layout or creates a new one.
// Updates the last access time for cache eviction tracking.
fn (mut ts TextSystem) get_or_create_layout(text string, cfg TextConfig) !&CachedLayout {
	key := ts.get_cache_key(text, &cfg)

	mut item := ts.cache[key] or {
		layout := ts.ctx.layout_text(text, cfg)!
		new_item := &CachedLayout{
			layout:      layout
			last_access: 0
		}
		ts.cache[key] = new_item
		new_item
	}

	item.last_access = time.ticks()
	return item
}

// Internal Helpers

pub fn (ts TextSystem) get_cache_key(text string, cfg &TextConfig) u64 {
	// FNV-1a 64-bit hash
	mut hash := u64(14695981039346656037)
	prime := u64(1099511628211)

	// Hash text (optimization: use unsafe pointer access to skip bounds checks)
	unsafe {
		mut ptr := text.str
		end := ptr + text.len
		for ptr < end {
			hash ^= u64(*ptr)
			hash *= prime
			ptr++
		}
	}
	// Separator
	hash ^= u64(124) // '|'
	hash *= prime

	// Hash TextStyle
	// font_name
	unsafe {
		mut ptr := cfg.style.font_name.str
		end := ptr + cfg.style.font_name.len
		for ptr < end {
			hash ^= u64(*ptr)
			hash *= prime
			ptr++
		}
	}
	// size
	hash ^= math.f32_bits(cfg.style.size)
	hash *= prime

	// Color
	hash ^= u64(cfg.style.color.r)
	hash *= prime
	hash ^= u64(cfg.style.color.g)
	hash *= prime
	hash ^= u64(cfg.style.color.b)
	hash *= prime
	hash ^= u64(cfg.style.color.a)
	hash *= prime

	// Bg Color
	hash ^= u64(cfg.style.bg_color.r)
	hash *= prime
	hash ^= u64(cfg.style.bg_color.g)
	hash *= prime
	hash ^= u64(cfg.style.bg_color.b)
	hash *= prime
	hash ^= u64(cfg.style.bg_color.a)
	hash *= prime

	if cfg.style.underline {
		hash ^= 1
		hash *= prime
	}
	if cfg.style.strikethrough {
		hash ^= 2
		hash *= prime
	}

	// Features (Pointer or Content)
	if cfg.style.features != unsafe { nil } {
		// We should hash the content of features if possible, or at least the pointer if we assume immutability/uniqueness.
		// For now, let's hash the content to be safe and correct.
		// NOTE: This might be slow if features are large, but usually they are small.
		unsafe {
			// Iterate opentype_features
			for f in cfg.style.features.opentype_features {
				// tag is string
				mut ptr := f.tag.str
				end := ptr + f.tag.len
				for ptr < end {
					hash ^= u64(*ptr)
					hash *= prime
					ptr++
				}
				hash ^= u64(f.value)
				hash *= prime
			}
			// Iterate variation_axes
			for a in cfg.style.features.variation_axes {
				mut ptr := a.tag.str
				end := ptr + a.tag.len
				for ptr < end {
					hash ^= u64(*ptr)
					hash *= prime
					ptr++
				}
				hash ^= math.f32_bits(a.value)
				hash *= prime
			}
		}
	}

	// Inline Object
	if cfg.style.object != unsafe { nil } {
		unsafe {
			// Hash object ID
			mut ptr := cfg.style.object.id.str
			end := ptr + cfg.style.object.id.len
			for ptr < end {
				hash ^= u64(*ptr)
				hash *= prime
				ptr++
			}
			// Hash dimensions/offset to be safe
			hash ^= math.f32_bits(cfg.style.object.width)
			hash *= prime
			hash ^= math.f32_bits(cfg.style.object.height)
			hash *= prime
			hash ^= math.f32_bits(cfg.style.object.offset)
			hash *= prime
		}
	}

	// Hash BlockStyle
	// width
	hash ^= math.f32_bits(cfg.block.width)
	hash *= prime

	// indent
	hash ^= math.f32_bits(cfg.block.indent)
	hash *= prime

	// align
	hash ^= u64(cfg.block.align)
	hash *= prime

	// wrap
	hash ^= u64(cfg.block.wrap)
	hash *= prime

	// tabs
	for t in cfg.block.tabs {
		hash ^= u64(t)
		hash *= prime
	}

	if cfg.use_markup {
		hash ^= 4
		hash *= prime
	}

	if cfg.no_hit_testing {
		hash ^= 8
		hash *= prime
	}

	return hash
}

fn (mut ts TextSystem) prune_cache() {
	now := time.ticks()

	if ts.cache.len < 10_000 {
		return
	}

	// Using keys() creates a copy, avoiding iterator invalidation when
	// deleting entries during iteration.
	keys := ts.cache.keys()
	for k in keys {
		item := ts.cache[k] or { continue }
		if now - item.last_access > ts.eviction_age {
			ts.cache.delete(k)
		}
	}
}
