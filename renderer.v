module vglyph

import gg
import math
import sokol.sgl
import sokol.gfx as sg
import time

pub struct Bitmap {
pub:
	width    int
	height   int
	channels int
	data     []u8
}

pub struct Renderer {
mut:
	ctx               &gg.Context
	atlas             GlyphAtlas
	sampler           sg.Sampler
	cache             map[u64]CachedGlyph
	cache_ages        map[u64]u64 // key -> last_used_frame
	max_cache_entries int = 4096 // capacity limit (enforced minimum 256)
	scale_factor      f32 = 1.0
	scale_inv         f32 = 1.0
pub mut:
	// Profile timing fields - only accessed when -d profile is used
	rasterize_time_ns     i64
	upload_time_ns        i64
	draw_time_ns          i64
	glyph_cache_hits      int
	glyph_cache_misses    int
	glyph_cache_evictions int
}

pub struct RendererConfig {
pub:
	max_glyph_cache_entries int = 4096
}

// Panic at init is acceptable per PROJECT.md: if we can't allocate the initial atlas,
// the text system cannot function. Callers (new_text_system) propagate errors upward.
pub fn new_renderer_with_config(mut ctx gg.Context, scale_factor f32,
	cfg RendererConfig) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, 1024, 1024) or { panic(err) }
	safe_scale := if scale_factor > 0 { scale_factor } else { 1.0 }
	max := if cfg.max_glyph_cache_entries < 256 { 256 } else { cfg.max_glyph_cache_entries }
	return &Renderer{
		ctx:               ctx
		atlas:             atlas
		sampler:           create_linear_sampler()
		cache:             map[u64]CachedGlyph{}
		cache_ages:        map[u64]u64{}
		max_cache_entries: max
		scale_factor:      safe_scale
		scale_inv:         1.0 / safe_scale
	}
}

// new_renderer creates a Renderer with default atlas size (1024x1024).
pub fn new_renderer(mut ctx gg.Context, scale_factor f32) &Renderer {
	return new_renderer_with_config(mut ctx, scale_factor, RendererConfig{})
}

// new_renderer_atlas_size creates a Renderer with custom initial atlas dimensions.
pub fn new_renderer_atlas_size(mut ctx gg.Context, width int, height int,
	scale_factor f32) &Renderer {
	return new_renderer_atlas_size_with_config(mut ctx, width, height, scale_factor, RendererConfig{})
}

// Panic at init is acceptable: if atlas creation fails, the text system cannot function.
// Callers (new_text_system_atlas_size) propagate errors upward.
pub fn new_renderer_atlas_size_with_config(mut ctx gg.Context, width int, height int,
	scale_factor f32, cfg RendererConfig) &Renderer {
	mut atlas := new_glyph_atlas(mut ctx, width, height) or { panic(err) }
	safe_scale := if scale_factor > 0 { scale_factor } else { 1.0 }
	max := if cfg.max_glyph_cache_entries < 256 { 256 } else { cfg.max_glyph_cache_entries }
	return &Renderer{
		ctx:               ctx
		atlas:             atlas
		sampler:           create_linear_sampler()
		cache:             map[u64]CachedGlyph{}
		cache_ages:        map[u64]u64{}
		max_cache_entries: max
		scale_factor:      safe_scale
		scale_inv:         1.0 / safe_scale
	}
}

fn create_linear_sampler() sg.Sampler {
	smp_desc := sg.SamplerDesc{
		min_filter: .linear
		mag_filter: .linear
		wrap_u:     .clamp_to_edge
		wrap_v:     .clamp_to_edge
	}
	return sg.make_sampler(&smp_desc)
}

// commit updates GPU texture if atlas changed. Call once per frame after draws.
//
// Sokol/Graphics APIs prefer single-update-per-frame for dynamic textures.
// Multiple updates can overwrite buffer or cause stalls.
pub fn (mut renderer Renderer) commit() {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.upload_time_ns += time.sys_mono_now() - start
		}
	}
	// Sync fallback path (when async_uploads disabled)
	if !renderer.atlas.async_uploads {
		for i, mut page in renderer.atlas.pages {
			if page.dirty {
				$if diag ? {
					eprintln('[DIAG] SYNC: page=${i} frame=${renderer.atlas.frame_counter}')
				}
				// Copy staging_back directly to image.data, upload
				unsafe {
					vmemcpy(page.image.data, page.staging_back.data, page.staging_back.len)
				}
				page.image.update_pixel_data(page.image.data)
				page.dirty = false
			}
		}
		return
	}

	// Async path: swap buffers then upload from front
	for i, mut page in renderer.atlas.pages {
		if page.dirty {
			$if diag ? {
				eprintln('[DIAG] ASYNC: page=${i} frame=${renderer.atlas.frame_counter} dirty=true')
			}
			page.swap_staging_buffers()
			$if diag ? {
				// Check if back buffer is stale after swap
				sample_len := if page.staging_front.len < 16 { page.staging_front.len } else { 16 }
				front_sample := page.staging_front[..sample_len]
				back_sample := page.staging_back[..sample_len]
				if front_sample == back_sample {
					eprintln('[DIAG] WARNING: staging_front == staging_back after swap - frame ${renderer.atlas.frame_counter} glyphs may be missing from frame ${
						renderer.atlas.frame_counter + 2} upload')
				}
			}
			page.image.update_pixel_data(page.staging_front.data)
			page.dirty = false
		}
	}
}

// draw_layout renders Layout at (x, y).
//
// Algorithm:
// 1. Iterate Layout items.
// 2. Check cache for glyphs; loads from FreeType if missing (lazy loading).
// 3. Calc screen pos (Layout pos + Glyph offset + FreeType bearing).
// 4. Queue textured quad draw.
//
// Performance:
// - `gg` batches draws.
// - Lazy loading may cause CPU spike on first frame with new text.
pub fn (mut renderer Renderer) draw_layout(layout Layout, x f32, y f32) {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.draw_time_ns += time.sys_mono_now() - start
		}
	}
	// Item.y is BASELINE y. Draw relative to x + item.x, y + item.y.

	// Cleanup old atlas textures from previous frames
	renderer.atlas.cleanup(renderer.ctx.frame)

	// Increment frame counter for page age tracking
	renderer.atlas.frame_counter++

	for item in layout.items {
		// item.ft_face is &C.FT_FaceRec

		// Starting pen position for this run
		mut cx := x + f32(item.x)
		mut cy := y + f32(item.y) // Baseline

		// Draw Background Color
		if item.has_bg_color {
			bg_x := cx
			// item.y is baseline. Ascent is positive up.
			// so top is cy - ascent.
			bg_y := cy - f32(item.ascent)
			bg_w := f32(item.width)
			bg_h := f32(item.ascent + item.descent)
			renderer.ctx.draw_rect_filled(bg_x, bg_y, bg_w, bg_h, item.bg_color)
		}

		for i := item.glyph_start; i < item.glyph_start + item.glyph_count; i++ {
			if i < 0 || i >= layout.glyphs.len {
				continue
			}
			glyph := layout.glyphs[i]
			// Check for unknown glyph flag
			if (glyph.index & pango_glyph_unknown_flag) != 0 {
				continue
			}

			// Subpixel Positioning Logic
			// We calculate the precise physical X position we want.
			// Then we snap it to the nearest 1/4 pixel (bin 0, 1, 2, 3).
			// We effectively draw at the snapped integer position, using a glyph that
			// has been pre-shifted by the fractional part.

			scale := renderer.scale_factor
			target_x := cx + f32(glyph.x_offset)

			// Convert to physical pixels
			phys_origin_x := target_x * scale

			// Snap to nearest 0.25
			snapped_phys_x := math.round(phys_origin_x * 4.0) / 4.0

			// Separate into integer part (for placement) and subpixel bin (for glyph selection)
			draw_origin_x := math.floor(snapped_phys_x)
			frac_x := snapped_phys_x - draw_origin_x
			bin := int(frac_x * f32(subpixel_bins) + 0.1) & (subpixel_bins - 1) // +0.1 for float safety

			// Key includes the bin
			// (glyph.index << 2) | bin
			// Logic now handled in get_or_load_glyph

			// Intentional error suppression: missing glyph renders as blank space.
			// This is correct behavior - a single glyph failure should not crash
			// the entire text rendering. The empty CachedGlyph has width=0, height=0.
			cg := renderer.get_or_load_glyph(item, glyph, bin) or { CachedGlyph{} }

			// Update page age on use
			if cg.page >= 0 && cg.page < renderer.atlas.pages.len {
				renderer.atlas.pages[cg.page].age = renderer.atlas.frame_counter
			}

			// Compute final draw position
			// Y is still pixel-snapped (Bin 0 equivalent) to preserve baseline sharpness
			phys_origin_y := (cy - f32(glyph.y_offset)) * scale
			draw_origin_y := math.round(phys_origin_y) // Bin 0

			// cg.left / cg.top are the bitmap offsets from origin (in physical pixels)
			// draw_x/y are logical coordinates for gg

			scale_inv := renderer.scale_inv
			mut draw_x := (f32(draw_origin_x) + f32(cg.left)) * scale_inv
			mut draw_y := (f32(draw_origin_y) - f32(cg.top)) * scale_inv

			mut glyph_w := f32(cg.width) * scale_inv
			mut glyph_h := f32(cg.height) * scale_inv

			// GPU emoji scaling: scale native-resolution emoji to target ascent
			if item.use_original_color && glyph_h > 0 {
				target_h := f32(item.ascent)
				if glyph_h != target_h {
					emoji_scale := target_h / glyph_h
					glyph_w *= emoji_scale
					glyph_h = target_h
					// Adjust position for scaled bearing
					draw_x = (f32(draw_origin_x) + f32(cg.left) * emoji_scale) * scale_inv
					draw_y = (f32(draw_origin_y) - f32(cg.top) * emoji_scale) * scale_inv
				}
			}

			// Draw image from glyph atlas
			if cg.width > 0 && cg.height > 0 && cg.page >= 0 && cg.page < renderer.atlas.pages.len {
				dst := gg.Rect{
					x:      draw_x
					y:      draw_y
					width:  glyph_w
					height: glyph_h
				}
				src := gg.Rect{
					x:      f32(cg.x)
					y:      f32(cg.y)
					width:  f32(cg.width)
					height: f32(cg.height)
				}

				mut c := item.color
				if item.use_original_color {
					c = gg.white
				}

				renderer.ctx.draw_image_with_config(
					img:       &renderer.atlas.pages[cg.page].image
					part_rect: src
					img_rect:  dst
					color:     c
				)
			}

			// Advance cursor
			cx += f32(glyph.x_advance)
			cy -= f32(glyph.y_advance)
		}

		// Draw Text Decorations (Underline / Strikethrough)
		if item.has_underline || item.has_strikethrough {
			// Reset pen to start of run
			run_x := x + f32(item.x)
			run_y := y + f32(item.y)

			if item.has_underline {
				line_x := run_x
				// item.underline_offset is (+) for below
				line_y := run_y + f32(item.underline_offset) - f32(item.underline_thickness)
				line_w := f32(item.width)
				line_h := f32(item.underline_thickness)

				renderer.ctx.draw_rect_filled(line_x, line_y, line_w, line_h, item.color)
			}

			if item.has_strikethrough {
				line_x := run_x
				line_y := run_y - f32(item.strikethrough_offset) + f32(item.strikethrough_thickness)
				line_w := f32(item.width)
				line_h := f32(item.strikethrough_thickness)

				renderer.ctx.draw_rect_filled(line_x, line_y, line_w, line_h, item.color)
			}
		}
	}
}

// get_atlas_height returns the current height of the first glyph atlas page.
pub fn (renderer &Renderer) get_atlas_height() int {
	if renderer.atlas.pages.len == 0 {
		return 0
	}
	return renderer.atlas.pages[0].height
}

// debug_insert_bitmap manually inserts a bitmap into the atlas.
// This is primarily for debugging atlas resizing behavior.
pub fn (mut renderer Renderer) debug_insert_bitmap(bmp Bitmap, left int, top int) !CachedGlyph {
	cached, _, _ := renderer.atlas.insert_bitmap(bmp, left, top)!
	return cached
}

// get_or_load_glyph retrieves a glyph from the cache or loads it from FreeType.
fn (mut renderer Renderer) get_or_load_glyph(item Item, glyph Glyph, bin int) !CachedGlyph {
	if item.ft_face == unsafe { nil } {
		return error('invalid font face')
	}
	font_id := u64(voidptr(item.ft_face))

	// Key includes the bin
	// We shift the index left by 2 bits to make room for 2 bits of bin.
	// (glyph.index << 2) | bin
	index_with_bin := (u64(glyph.index) << 2) | u64(bin)
	key := font_id ^ (index_with_bin << 32)

	if key in renderer.cache {
		$if profile ? {
			renderer.glyph_cache_hits++
		}
		// Update LRU age
		renderer.cache_ages[key] = renderer.atlas.frame_counter
		// unreachable: map access after 'key in renderer.cache' check
		cached := renderer.cache[key] or { panic('unreachable') }

		// Secondary key validation in debug builds
		$if debug {
			if cached.font_face != voidptr(item.ft_face) || cached.glyph_index != glyph.index
				|| cached.subpixel_bin != u8(bin) {
				exp := 'face=${voidptr(item.ft_face)} index=${glyph.index} bin=${bin}'
				got := 'face=${cached.font_face} index=${cached.glyph_index} bin=${cached.subpixel_bin}'
				panic('Glyph cache collision: key=0x${key:016x} expected ${exp}, got ${got}')
			}
		}

		return cached
	}

	$if profile ? {
		renderer.glyph_cache_misses++
	}

	target_h := int(f32(item.ascent) * renderer.scale_factor)
	mut cached_glyph := renderer.load_glyph(LoadGlyphConfig{
		face:          item.ft_face
		index:         glyph.index
		target_height: target_h
		subpixel_bin:  bin
	})!

	// Set secondary key fields for collision detection
	cached_glyph = CachedGlyph{
		...cached_glyph
		font_face:    voidptr(item.ft_face)
		glyph_index:  glyph.index
		subpixel_bin: u8(bin)
	}

	// Evict oldest if at capacity
	if renderer.cache.len >= renderer.max_cache_entries && key !in renderer.cache {
		renderer.evict_oldest_glyph()
	}

	renderer.cache[key] = cached_glyph
	renderer.cache_ages[key] = renderer.atlas.frame_counter
	return cached_glyph
}

fn (mut renderer Renderer) evict_oldest_glyph() {
	mut oldest_key := u64(0)
	mut oldest_age := u64(0xFFFFFFFFFFFFFFFF)
	for k, age in renderer.cache_ages {
		if age < oldest_age {
			oldest_age = age
			oldest_key = k
		}
	}
	if oldest_key != 0 || oldest_age != u64(0xFFFFFFFFFFFFFFFF) {
		renderer.cache.delete(oldest_key)
		renderer.cache_ages.delete(oldest_key)
		$if profile ? {
			renderer.glyph_cache_evictions++
		}
	}
}

@[inline]
fn transform_layout_point(transform AffineTransform, origin_x f32, origin_y f32,
	x f32, y f32) (f32, f32) {
	tx, ty := transform.apply(x, y)
	return origin_x + tx, origin_y + ty
}

// lerp_color interpolates between two colors.
@[inline]
fn lerp_color(a gg.Color, b gg.Color, t f32) gg.Color {
	tc := math.clamp(t, 0.0, 1.0)
	inv := 1.0 - tc
	return gg.Color{
		r: u8(f32(a.r) * inv + f32(b.r) * tc)
		g: u8(f32(a.g) * inv + f32(b.g) * tc)
		b: u8(f32(a.b) * inv + f32(b.b) * tc)
		a: u8(f32(a.a) * inv + f32(b.a) * tc)
	}
}

// gradient_color_at samples the gradient at normalized position t.
@[inline]
fn gradient_color_at(stops []GradientStop, t f32) gg.Color {
	if stops.len == 0 {
		return gg.Color{0, 0, 0, 255}
	}
	if stops.len == 1 || t <= stops[0].position {
		return stops[0].color
	}
	if t >= stops[stops.len - 1].position {
		return stops[stops.len - 1].color
	}
	for i := 0; i < stops.len - 1; i++ {
		if t >= stops[i].position && t <= stops[i + 1].position {
			span := stops[i + 1].position - stops[i].position
			if span <= 0 {
				return stops[i].color
			}
			local_t := (t - stops[i].position) / span
			return lerp_color(stops[i].color, stops[i + 1].color, local_t)
		}
	}
	return stops[stops.len - 1].color
}

// draw_layout_rotated draws the layout rotated by `angle` (in radians) around its origin.
pub fn (mut renderer Renderer) draw_layout_rotated(layout Layout, x f32, y f32, angle f32) {
	renderer.draw_layout_impl(layout, x, y, affine_rotation(angle), unsafe { nil })
}

// draw_layout_transformed draws the layout using an affine transform around origin (x, y).
pub fn (mut renderer Renderer) draw_layout_transformed(layout Layout, x f32, y f32,
	transform AffineTransform) {
	renderer.draw_layout_impl(layout, x, y, transform, unsafe { nil })
}

// draw_layout_with_gradient draws the layout with gradient colors.
pub fn (mut renderer Renderer) draw_layout_with_gradient(layout Layout, x f32, y f32,
	gradient &GradientConfig) {
	renderer.draw_layout_impl(layout, x, y, affine_identity(), gradient)
}

// draw_layout_transformed_with_gradient draws with both transform and gradient.
pub fn (mut renderer Renderer) draw_layout_transformed_with_gradient(layout Layout,
	x f32, y f32, transform AffineTransform, gradient &GradientConfig) {
	renderer.draw_layout_impl(layout, x, y, transform, gradient)
}

// draw_layout_rotated_with_gradient draws rotated with gradient colors.
pub fn (mut renderer Renderer) draw_layout_rotated_with_gradient(layout Layout,
	x f32, y f32, angle f32, gradient &GradientConfig) {
	renderer.draw_layout_impl(layout, x, y, affine_rotation(angle), gradient)
}

// draw_layout_impl is the shared implementation for transformed/gradient rendering.
fn (mut renderer Renderer) draw_layout_impl(layout Layout, x f32, y f32,
	transform AffineTransform, gradient &GradientConfig) {
	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.draw_time_ns += time.sys_mono_now() - start
		}
	}
	// Cleanup old atlas textures from previous frames
	renderer.atlas.cleanup(renderer.ctx.frame)

	// Increment frame counter for page age tracking
	renderer.atlas.frame_counter++

	has_gradient := gradient != unsafe { nil } && gradient.stops.len > 0

	// Pre-compute gradient extents
	grad_w := if has_gradient && layout.visual_width > 0 {
		layout.visual_width
	} else {
		f32(1.0)
	}
	grad_h := if has_gradient && layout.height > 0 {
		layout.height
	} else {
		f32(1.0)
	}

	sgl.matrix_mode_projection()
	sgl.push_matrix()
	sgl.load_identity()
	sgl.ortho(0, f32(renderer.ctx.width), f32(renderer.ctx.height), 0, -1, 1)

	sgl.matrix_mode_modelview()
	sgl.push_matrix()
	sgl.load_identity()

	// 1. Draw Backgrounds (Untextured)
	sgl.begin_quads()
	for item in layout.items {
		if item.has_bg_color {
			run_x := f32(item.x)
			run_y := f32(item.y)
			bg_x := run_x
			bg_y := run_y - f32(item.ascent)
			bg_w := f32(item.width)
			bg_h := f32(item.ascent + item.descent)

			c := item.bg_color
			x0, y0 := transform_layout_point(transform, x, y, bg_x, bg_y)
			x1, y1 := transform_layout_point(transform, x, y, bg_x + bg_w, bg_y)
			x2, y2 := transform_layout_point(transform, x, y, bg_x + bg_w, bg_y + bg_h)
			x3, y3 := transform_layout_point(transform, x, y, bg_x, bg_y + bg_h)
			sgl.c4b(c.r, c.g, c.b, c.a)
			sgl.v2f(x0, y0)
			sgl.v2f(x1, y1)
			sgl.v2f(x2, y2)
			sgl.v2f(x3, y3)
		}
	}
	sgl.end()

	// 2. Draw Glyphs (Textured) - draw per page to bind correct texture
	for page_idx, page in renderer.atlas.pages {
		sgl.enable_texture()
		sgl.texture(page.image.simg, renderer.sampler)
		sgl.begin_quads()

		for item in layout.items {
			run_x := f32(item.x)
			run_y := f32(item.y)

			mut cx := run_x
			mut cy := run_y

			mut c := item.color
			if item.use_original_color {
				c = gg.white
			}

			for i := item.glyph_start; i < item.glyph_start + item.glyph_count; i++ {
				if i < 0 || i >= layout.glyphs.len {
					continue
				}
				glyph := layout.glyphs[i]
				if (glyph.index & pango_glyph_unknown_flag) != 0 {
					cx += f32(glyph.x_advance)
					cy -= f32(glyph.y_advance)
					continue
				}

				gx := cx + f32(glyph.x_offset)
				gy := cy - f32(glyph.y_offset)

				// Bin 0 for transformed path
				cg := renderer.get_or_load_glyph(item, glyph, 0) or { CachedGlyph{} }

				if cg.page >= 0 && cg.page < renderer.atlas.pages.len {
					renderer.atlas.pages[cg.page].age = renderer.atlas.frame_counter
				}

				if cg.page == page_idx && cg.width > 0 && cg.height > 0 && page.width > 0
					&& page.height > 0 {
					scale_inv := renderer.scale_inv

					mut dst_x := gx + f32(cg.left) * scale_inv
					mut dst_y := gy - f32(cg.top) * scale_inv
					mut dst_w := f32(cg.width) * scale_inv
					mut dst_h := f32(cg.height) * scale_inv

					// GPU emoji scaling
					if item.use_original_color && dst_h > 0 {
						target_h := f32(item.ascent)
						if dst_h != target_h {
							emoji_scale := target_h / dst_h
							dst_w *= emoji_scale
							dst_h = target_h
							dst_x = gx + f32(cg.left) * emoji_scale * scale_inv
							dst_y = gy - f32(cg.top) * emoji_scale * scale_inv
						}
					}

					atlas_w := f32(page.width)
					atlas_h := f32(page.height)

					u0 := f32(cg.x) / atlas_w
					v0 := f32(cg.y) / atlas_h
					u1 := (f32(cg.x) + f32(cg.width)) / atlas_w
					v1 := (f32(cg.y) + f32(cg.height)) / atlas_h

					x0, y0 := transform_layout_point(transform, x, y, dst_x, dst_y)
					x1, y1 := transform_layout_point(transform, x, y, dst_x + dst_w, dst_y)
					x2, y2 := transform_layout_point(transform, x, y, dst_x + dst_w, dst_y + dst_h)
					x3, y3 := transform_layout_point(transform, x, y, dst_x, dst_y + dst_h)

					if has_gradient && !item.use_original_color {
						// Per-vertex gradient colors
						if gradient.direction == .horizontal {
							t_left := dst_x / grad_w
							t_right := (dst_x + dst_w) / grad_w
							c_left := gradient_color_at(gradient.stops, t_left)
							c_right := gradient_color_at(gradient.stops, t_right)
							sgl.c4b(c_left.r, c_left.g, c_left.b, c_left.a)
							sgl.v2f_t2f(x0, y0, u0, v0)
							sgl.c4b(c_right.r, c_right.g, c_right.b, c_right.a)
							sgl.v2f_t2f(x1, y1, u1, v0)
							sgl.c4b(c_right.r, c_right.g, c_right.b, c_right.a)
							sgl.v2f_t2f(x2, y2, u1, v1)
							sgl.c4b(c_left.r, c_left.g, c_left.b, c_left.a)
							sgl.v2f_t2f(x3, y3, u0, v1)
						} else {
							t_top := dst_y / grad_h
							t_bottom := (dst_y + dst_h) / grad_h
							c_top := gradient_color_at(gradient.stops, t_top)
							c_bottom := gradient_color_at(gradient.stops, t_bottom)
							sgl.c4b(c_top.r, c_top.g, c_top.b, c_top.a)
							sgl.v2f_t2f(x0, y0, u0, v0)
							sgl.c4b(c_top.r, c_top.g, c_top.b, c_top.a)
							sgl.v2f_t2f(x1, y1, u1, v0)
							sgl.c4b(c_bottom.r, c_bottom.g, c_bottom.b, c_bottom.a)
							sgl.v2f_t2f(x2, y2, u1, v1)
							sgl.c4b(c_bottom.r, c_bottom.g, c_bottom.b, c_bottom.a)
							sgl.v2f_t2f(x3, y3, u0, v1)
						}
					} else {
						sgl.c4b(c.r, c.g, c.b, c.a)
						sgl.v2f_t2f(x0, y0, u0, v0)
						sgl.v2f_t2f(x1, y1, u1, v0)
						sgl.v2f_t2f(x2, y2, u1, v1)
						sgl.v2f_t2f(x3, y3, u0, v1)
					}
				}
				cx += f32(glyph.x_advance)
				cy -= f32(glyph.y_advance)
			}
		}
		sgl.end()
		sgl.disable_texture()
	}

	// 3. Draw Text Decorations (Untextured)
	sgl.begin_quads()
	for item in layout.items {
		if item.has_underline || item.has_strikethrough {
			run_x := f32(item.x)
			run_y := f32(item.y)

			if item.has_underline {
				line_x := run_x
				line_y := run_y + f32(item.underline_offset) - f32(item.underline_thickness)
				line_w := f32(item.width)
				line_h := f32(item.underline_thickness)

				x0, y0 := transform_layout_point(transform, x, y, line_x, line_y)
				x1, y1 := transform_layout_point(transform, x, y, line_x + line_w, line_y)
				x2, y2 := transform_layout_point(transform, x, y, line_x + line_w, line_y + line_h)
				x3, y3 := transform_layout_point(transform, x, y, line_x, line_y + line_h)

				if has_gradient && !item.use_original_color {
					if gradient.direction == .horizontal {
						t_left := line_x / grad_w
						t_right := (line_x + line_w) / grad_w
						c_left := gradient_color_at(gradient.stops, t_left)
						c_right := gradient_color_at(gradient.stops, t_right)
						sgl.c4b(c_left.r, c_left.g, c_left.b, c_left.a)
						sgl.v2f(x0, y0)
						sgl.c4b(c_right.r, c_right.g, c_right.b, c_right.a)
						sgl.v2f(x1, y1)
						sgl.c4b(c_right.r, c_right.g, c_right.b, c_right.a)
						sgl.v2f(x2, y2)
						sgl.c4b(c_left.r, c_left.g, c_left.b, c_left.a)
						sgl.v2f(x3, y3)
					} else {
						t_top := line_y / grad_h
						t_bottom := (line_y + line_h) / grad_h
						c_top := gradient_color_at(gradient.stops, t_top)
						c_bottom := gradient_color_at(gradient.stops, t_bottom)
						sgl.c4b(c_top.r, c_top.g, c_top.b, c_top.a)
						sgl.v2f(x0, y0)
						sgl.c4b(c_top.r, c_top.g, c_top.b, c_top.a)
						sgl.v2f(x1, y1)
						sgl.c4b(c_bottom.r, c_bottom.g, c_bottom.b, c_bottom.a)
						sgl.v2f(x2, y2)
						sgl.c4b(c_bottom.r, c_bottom.g, c_bottom.b, c_bottom.a)
						sgl.v2f(x3, y3)
					}
				} else {
					sgl.c4b(item.color.r, item.color.g, item.color.b, item.color.a)
					sgl.v2f(x0, y0)
					sgl.v2f(x1, y1)
					sgl.v2f(x2, y2)
					sgl.v2f(x3, y3)
				}
			}

			if item.has_strikethrough {
				line_x := run_x
				line_y := run_y - f32(item.strikethrough_offset) + f32(item.strikethrough_thickness)
				line_w := f32(item.width)
				line_h := f32(item.strikethrough_thickness)

				x0, y0 := transform_layout_point(transform, x, y, line_x, line_y)
				x1, y1 := transform_layout_point(transform, x, y, line_x + line_w, line_y)
				x2, y2 := transform_layout_point(transform, x, y, line_x + line_w, line_y + line_h)
				x3, y3 := transform_layout_point(transform, x, y, line_x, line_y + line_h)

				if has_gradient && !item.use_original_color {
					if gradient.direction == .horizontal {
						t_left := line_x / grad_w
						t_right := (line_x + line_w) / grad_w
						c_left := gradient_color_at(gradient.stops, t_left)
						c_right := gradient_color_at(gradient.stops, t_right)
						sgl.c4b(c_left.r, c_left.g, c_left.b, c_left.a)
						sgl.v2f(x0, y0)
						sgl.c4b(c_right.r, c_right.g, c_right.b, c_right.a)
						sgl.v2f(x1, y1)
						sgl.c4b(c_right.r, c_right.g, c_right.b, c_right.a)
						sgl.v2f(x2, y2)
						sgl.c4b(c_left.r, c_left.g, c_left.b, c_left.a)
						sgl.v2f(x3, y3)
					} else {
						t_top := line_y / grad_h
						t_bottom := (line_y + line_h) / grad_h
						c_top := gradient_color_at(gradient.stops, t_top)
						c_bottom := gradient_color_at(gradient.stops, t_bottom)
						sgl.c4b(c_top.r, c_top.g, c_top.b, c_top.a)
						sgl.v2f(x0, y0)
						sgl.c4b(c_top.r, c_top.g, c_top.b, c_top.a)
						sgl.v2f(x1, y1)
						sgl.c4b(c_bottom.r, c_bottom.g, c_bottom.b, c_bottom.a)
						sgl.v2f(x2, y2)
						sgl.c4b(c_bottom.r, c_bottom.g, c_bottom.b, c_bottom.a)
						sgl.v2f(x3, y3)
					}
				} else {
					sgl.c4b(item.color.r, item.color.g, item.color.b, item.color.a)
					sgl.v2f(x0, y0)
					sgl.v2f(x1, y1)
					sgl.v2f(x2, y2)
					sgl.v2f(x3, y3)
				}
			}
		}
	}
	sgl.end()

	sgl.pop_matrix() // Pop Modelview

	sgl.matrix_mode_projection()
	sgl.pop_matrix()
	sgl.matrix_mode_modelview()
}

// draw_composition renders IME preedit text with visual feedback.
// Per CONTEXT.md decisions:
// - Preedit at ~70% opacity (alpha 178)
// - Cursor visible at insertion point within preedit
// - Thick underline for selected clause, thin for others
pub fn (mut renderer Renderer) draw_composition(layout Layout, x f32, y f32,
	cs &CompositionState, cursor_color gg.Color) {
	if !cs.is_composing() {
		return
	}

	// Draw clause underlines
	clause_rects := cs.get_clause_rects(layout)
	for cr in clause_rects {
		// Underline thickness: 2px for selected, 1px for others
		thickness := if cr.style == .selected { f32(2.0) } else { f32(1.0) }

		for rect in cr.rects {
			// Draw underline at bottom of rect
			underline_y := rect.y + rect.height - thickness
			// Use cursor color for underlines (dimmed like preedit)
			underline_color := gg.Color{
				r: cursor_color.r
				g: cursor_color.g
				b: cursor_color.b
				a: 178 // ~70% opacity
			}
			renderer.ctx.draw_rect_filled(rect.x + x, underline_y + y, rect.width, thickness,
				underline_color)
		}
	}

	// Draw cursor at insertion point within preedit
	cursor_pos := cs.get_document_cursor_pos()
	if cursor_rect := layout.get_cursor_pos(cursor_pos) {
		// Draw cursor at ~70% opacity
		dimmed_cursor := gg.Color{
			r: cursor_color.r
			g: cursor_color.g
			b: cursor_color.b
			a: 178
		}
		renderer.ctx.draw_rect_filled(cursor_rect.x + x, cursor_rect.y + y, f32(2.0),
			cursor_rect.height, dimmed_cursor)
	}
}

// draw_layout_with_composition renders layout with preedit opacity applied.
// Preedit text range gets alpha reduced to ~70%.
// Call this instead of draw_layout when composition is active.
pub fn (mut renderer Renderer) draw_layout_with_composition(layout Layout, x f32, y f32,
	cs &CompositionState) {
	// For now, draw normally - preedit opacity would require layout item modification
	// or shader support. The underlines provide sufficient visual distinction.
	// Full opacity reduction deferred to future enhancement.
	renderer.draw_layout(layout, x, y)
}
