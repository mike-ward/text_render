module vglyph

import gg
import sokol.sapp
import time

struct CachedLayout {
mut:
	layout      Layout
	last_access i64
}

pub struct TextSystem {
mut:
	ctx          &Context
	renderer     &Renderer
	cache        map[u64]&CachedLayout
	eviction_age i64 = 5000 // ms
}

// new_text_system creates a new TextSystem, initializing Pango context and
// Renderer.
pub fn new_text_system(mut gg_ctx gg.Context) !&TextSystem {
	scale := sapp.dpi_scale()
	tr_ctx := new_context(scale)!
	renderer := new_renderer(mut gg_ctx, scale)
	return &TextSystem{
		ctx:      tr_ctx
		renderer: renderer
		cache:    map[u64]&CachedLayout{}
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
	}
}

// draw_text renders text string at (x, y) using configuration.
// Handles layout caching to optimize performance for repeated calls.
// [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) draw_text(x f32, y f32, text string, cfg TextConfig) ! {
	key := ts.get_cache_key(text, cfg)
	ts.prune_cache()

	if key in ts.cache {
		mut item := ts.cache[key] or {
			return error('cache coherency error: key found but access failed')
		}
		item.last_access = time.ticks()
		ts.renderer.draw_layout(item.layout, x, y)
	} else {
		// Cache miss
		layout := ts.ctx.layout_text(text, cfg) or { return err }
		ts.cache[key] = &CachedLayout{
			layout:      layout
			last_access: time.ticks()
		}
		ts.renderer.draw_layout(layout, x, y)
	}
}

// text_width calculates width (pixels) of text if rendered with config.
// Useful for layout calculations before rendering. [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) text_width(text string, cfg TextConfig) !f32 {
	key := ts.get_cache_key(text, cfg)

	if key in ts.cache {
		mut item := ts.cache[key] or {
			return error('cache coherency error: key found but access failed')
		}
		item.last_access = time.ticks()
		return item.layout.width
	}

	layout := ts.ctx.layout_text(text, cfg) or { return err }
	ts.cache[key] = &CachedLayout{
		layout:      layout
		last_access: time.ticks()
	}
	return layout.width
}

// text_height calculates visual height (pixels) of text.
// Corresponds to vertical space occupied. [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) text_height(text string, cfg TextConfig) !f32 {
	key := ts.get_cache_key(text, cfg)

	if key in ts.cache {
		mut item := ts.cache[key] or {
			return error('cache coherency error: key found but access failed')
		}
		item.last_access = time.ticks()
		return item.layout.visual_height
	}

	layout := ts.ctx.layout_text(text, cfg) or { return err }
	ts.cache[key] = &CachedLayout{
		layout:      layout
		last_access: time.ticks()
	}
	return layout.visual_height
}

// font_height returns the true height of the font (ascent + descent) in pixels.
// This is the vertical space the font claims, including descenders, regardless
// of the actual text content. [TextConfig](#TextConfig)
pub fn (mut ts TextSystem) font_height(cfg TextConfig) f32 {
	return ts.ctx.font_height(cfg)
}

// commit should be called at the end of the frame to upload the texture atlas.
pub fn (mut ts TextSystem) commit() {
	ts.renderer.commit()
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

// layout_rich_text computes the layout for the given RichText and config.
// Useful for rendering attributed strings.
pub fn (mut ts TextSystem) layout_rich_text(rt RichText, cfg TextConfig) !Layout {
	return ts.ctx.layout_rich_text(rt, cfg)
}

// draw_layout renders a pre-computed layout.
pub fn (mut ts TextSystem) draw_layout(l Layout, x f32, y f32) {
	ts.renderer.draw_layout(l, x, y)
}

// Internal Helpers

fn (ts TextSystem) get_cache_key(text string, cfg TextConfig) u64 {
	// FNV-1a 64-bit hash
	mut hash := u64(14695981039346656037)
	prime := u64(1099511628211)

	// Hash text
	for i in 0 .. text.len {
		hash ^= u64(text[i])
		hash *= prime
	}

	// Separator
	hash ^= u64(124) // '|'
	hash *= prime

	// Hash font_name
	for i in 0 .. cfg.font_name.len {
		hash ^= u64(cfg.font_name[i])
		hash *= prime
	}

	// Mix width
	hash ^= u64(cfg.width)
	hash *= prime

	// Mix align
	hash ^= u64(cfg.align)
	hash *= prime

	// Mix wrap
	hash ^= u64(cfg.wrap)
	hash *= prime

	if cfg.use_markup {
		hash ^= 1
		hash *= prime
	} else {
		hash ^= 0
		hash *= prime
	}

	// Color
	hash ^= u64(cfg.color.r)
	hash *= prime
	hash ^= u64(cfg.color.g)
	hash *= prime
	hash ^= u64(cfg.color.b)
	hash *= prime
	hash ^= u64(cfg.color.a)
	hash *= prime

	// Bg Color
	hash ^= u64(cfg.bg_color.r)
	hash *= prime
	hash ^= u64(cfg.bg_color.g)
	hash *= prime
	hash ^= u64(cfg.bg_color.b)
	hash *= prime
	hash ^= u64(cfg.bg_color.a)
	hash *= prime

	if cfg.underline {
		hash ^= 1
		hash *= prime
	} else {
		hash ^= 0
		hash *= prime
	}

	if cfg.strikethrough {
		hash ^= 1
		hash *= prime
	} else {
		hash ^= 0
		hash *= prime
	}

	return hash
}

fn (mut ts TextSystem) prune_cache() {
	now := time.ticks()

	if ts.cache.len < 10_000 {
		return
	}

	// simpler: usage of `keys()` copies the keys, so safe to delete.
	keys := ts.cache.keys()
	for k in keys {
		item := ts.cache[k] or { continue }
		if now - item.last_access > ts.eviction_age {
			ts.cache.delete(k)
		}
	}
}
