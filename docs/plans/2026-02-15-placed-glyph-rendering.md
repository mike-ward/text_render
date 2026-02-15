# Placed Glyph Rendering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> to implement this plan task-by-task.

**Goal:** Add per-glyph positioned rendering so frameworks can render
text along curves without vglyph owning path geometry.

**Architecture:** New `GlyphPlacement` struct holds per-glyph screen
position + rotation angle. `glyph_positions()` on Layout flattens the
item/glyph hierarchy for callers. `draw_layout_placed()` on Renderer
and TextSystem renders each glyph at its placement using per-glyph
`AffineTransform` built from the angle.

**Tech Stack:** V, Sokol SGL (textured quads), FreeType (glyph
atlas), existing `AffineTransform` helpers.

**Design doc:**
`docs/plans/2026-02-15-placed-glyph-rendering-design.md`

---

### Task 1: Add GlyphPlacement and GlyphInfo structs

**Files:**
- Modify: `layout_types.v` (append after `AffineTransform` block,
  ~line 221)

**Step 1: Add structs to layout_types.v**

Append after the `affine_skew` function (after line 221):

```v ignore
// GlyphPlacement specifies absolute screen position and rotation
// for a single glyph. Used with draw_layout_placed() for
// text-on-curve rendering.
pub struct GlyphPlacement {
pub:
	x     f32 // absolute screen x
	y     f32 // absolute screen y (baseline)
	angle f32 // rotation in radians, 0 = upright
}

// GlyphInfo provides the absolute position and advance of a
// glyph within a Layout. Returned by glyph_positions() so
// callers can compute path placements from advance widths.
pub struct GlyphInfo {
pub:
	x       f32 // absolute x within layout
	y       f32 // baseline y within layout
	advance f32 // horizontal advance width
	index   int // index into layout.glyphs
}
```

**Step 2: Format and check syntax**

Run: `v fmt -w layout_types.v && v -check-syntax layout_types.v`
Expected: no errors

**Step 3: Commit**

```
git add layout_types.v
git commit -m "add GlyphPlacement and GlyphInfo structs"
```

---

### Task 2: Add glyph_positions() method on Layout

**Files:**
- Modify: `layout_types.v` (append after GlyphInfo struct)
- Test: `_placed_test.v`

**Step 1: Write the failing test**

Create `_placed_test.v`:

```v ignore
module vglyph

// Test glyph_positions returns correct count and ordering
fn test_glyph_positions_count() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	layout := ctx.layout_text('ABC', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!

	positions := layout.glyph_positions()

	// Should have one GlyphInfo per glyph
	assert positions.len == layout.glyphs.len
	// 'ABC' = 3 single-glyph chars
	assert positions.len == 3
}

// Test advances are positive and x increases
fn test_glyph_positions_advances() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	layout := ctx.layout_text('AB', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!

	positions := layout.glyph_positions()

	assert positions.len == 2
	// First glyph starts at or near 0
	assert positions[0].x >= 0
	// Advances should be positive
	assert positions[0].advance > 0
	assert positions[1].advance > 0
	// Second glyph x > first glyph x
	assert positions[1].x > positions[0].x
}

// Test empty layout returns empty positions
fn test_glyph_positions_empty() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	layout := ctx.layout_text('', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!

	positions := layout.glyph_positions()
	assert positions.len == 0
}

// Test index field matches layout.glyphs array index
fn test_glyph_positions_index() {
	mut ctx := new_context(1.0)!
	defer { ctx.free() }

	layout := ctx.layout_text('Hello', TextConfig{
		style: TextStyle{
			font_name: 'Sans 20'
		}
	})!

	positions := layout.glyph_positions()

	for i, pos in positions {
		assert pos.index == i
	}
}
```

**Step 2: Run test to verify it fails**

Run: `v test _placed_test.v`
Expected: FAIL — `glyph_positions` not defined

**Step 3: Implement glyph_positions()**

Append to `layout_types.v` after the `GlyphInfo` struct:

```v ignore
// glyph_positions returns the absolute position, advance, and
// index of every glyph in the layout. Flattens the item/glyph
// hierarchy so callers can walk advances to place glyphs on a
// path.
pub fn (l Layout) glyph_positions() []GlyphInfo {
	if l.glyphs.len == 0 {
		return []
	}
	mut result := []GlyphInfo{cap: l.glyphs.len}
	for item in l.items {
		mut cx := f32(item.x)
		mut cy := f32(item.y)
		for i := item.glyph_start; i < item.glyph_start + item.glyph_count; i++ {
			if i < 0 || i >= l.glyphs.len {
				continue
			}
			glyph := l.glyphs[i]
			result << GlyphInfo{
				x:       cx + f32(glyph.x_offset)
				y:       cy - f32(glyph.y_offset)
				advance: f32(glyph.x_advance)
				index:   i
			}
			cx += f32(glyph.x_advance)
			cy -= f32(glyph.y_advance)
		}
	}
	return result
}
```

**Step 4: Format and run tests**

Run: `v fmt -w layout_types.v && v test _placed_test.v`
Expected: PASS

**Step 5: Commit**

```
git add layout_types.v _placed_test.v
git commit -m "add glyph_positions() method on Layout"
```

---

### Task 3: Add draw_layout_placed() on Renderer

**Files:**
- Modify: `renderer.v` (add new public method)

**Step 1: Implement draw_layout_placed**

Add after the `draw_layout_rotated_with_gradient` method
(~line 585) in `renderer.v`:

```v ignore
// draw_layout_placed renders each glyph at its individual
// placement. Decorations (underline, strikethrough, background)
// are skipped. Each GlyphPlacement provides absolute screen
// position and rotation angle.
//
// placements must have the same length as layout.glyphs.
// If lengths differ, returns immediately (no-op).
pub fn (mut renderer Renderer) draw_layout_placed(layout Layout,
	placements []GlyphPlacement) {
	if placements.len != layout.glyphs.len {
		return
	}
	if layout.glyphs.len == 0 {
		return
	}

	$if profile ? {
		start := time.sys_mono_now()
		defer {
			renderer.draw_time_ns += time.sys_mono_now() - start
		}
	}

	renderer.atlas.cleanup(renderer.ctx.frame)
	renderer.atlas.frame_counter++

	// Ensure stroker if any item has stroke
	for item in layout.items {
		if item.has_stroke && !item.use_original_color {
			renderer.ensure_stroker(item.ft_face)
			break
		}
	}

	// Setup projection for SGL quad rendering
	sgl.matrix_mode_projection()
	sgl.push_matrix()
	sgl.load_identity()
	sgl.ortho(0, f32(renderer.ctx.width),
		f32(renderer.ctx.height), 0, -1, 1)

	sgl.matrix_mode_modelview()
	sgl.push_matrix()
	sgl.load_identity()

	// Pass 1: Stroke outlines
	for page_idx, page in renderer.atlas.pages {
		sgl.enable_texture()
		sgl.texture(page.image.simg, renderer.sampler)
		sgl.begin_quads()

		for item in layout.items {
			if !item.has_stroke || item.use_original_color {
				continue
			}

			phys_w := item.stroke_width * renderer.scale_factor
			s_radius := i64(phys_w * 0.5 * 64)
			C.FT_Stroker_Set(renderer.ft_stroker, s_radius,
				ft_stroker_linecap_round,
				ft_stroker_linejoin_round, 0)

			for i := item.glyph_start; i < item.glyph_start +
				item.glyph_count; i++ {
				if i < 0 || i >= layout.glyphs.len {
					continue
				}
				glyph := layout.glyphs[i]
				if (glyph.index & pango_glyph_unknown_flag) != 0 {
					continue
				}
				placement := placements[i]

				cg := renderer.get_or_load_glyph(item, glyph,
					0, s_radius) or { CachedGlyph{} }

				if cg.page >= 0
					&& cg.page < renderer.atlas.pages.len {
					renderer.atlas.pages[cg.page].age = renderer.atlas.frame_counter
				}

				if cg.page == page_idx && cg.width > 0
					&& cg.height > 0 && page.width > 0
					&& page.height > 0 {
					renderer.emit_placed_quad(cg, placement,
						page, item.stroke_color)
				}
			}
		}
		sgl.end()
		sgl.disable_texture()
	}

	// Pass 2: Fill glyphs
	for page_idx, page in renderer.atlas.pages {
		sgl.enable_texture()
		sgl.texture(page.image.simg, renderer.sampler)
		sgl.begin_quads()

		for item in layout.items {
			if item.has_stroke && item.color.a == 0 {
				continue
			}

			mut c := item.color
			if item.use_original_color {
				c = gg.white
			}

			for i := item.glyph_start; i < item.glyph_start +
				item.glyph_count; i++ {
				if i < 0 || i >= layout.glyphs.len {
					continue
				}
				glyph := layout.glyphs[i]
				if (glyph.index & pango_glyph_unknown_flag) != 0 {
					continue
				}
				placement := placements[i]

				// Subpixel bin from placement x
				scale := renderer.scale_factor
				phys_x := placement.x * scale
				snapped := math.round(phys_x * 4.0) / 4.0
				frac := snapped - math.floor(snapped)
				bin := int(frac * f32(subpixel_bins) + 0.1) & (subpixel_bins - 1)

				cg := renderer.get_or_load_glyph(item, glyph,
					bin, 0) or { CachedGlyph{} }

				if cg.page >= 0
					&& cg.page < renderer.atlas.pages.len {
					renderer.atlas.pages[cg.page].age = renderer.atlas.frame_counter
				}

				if cg.page == page_idx && cg.width > 0
					&& cg.height > 0 && page.width > 0
					&& page.height > 0 {
					renderer.emit_placed_quad(cg, placement,
						page, c)
				}
			}
		}
		sgl.end()
		sgl.disable_texture()
	}

	sgl.pop_matrix()
	sgl.matrix_mode_projection()
	sgl.pop_matrix()
	sgl.matrix_mode_modelview()
}

// emit_placed_quad draws a single textured glyph quad at the
// given placement with optional rotation.
fn (renderer &Renderer) emit_placed_quad(cg CachedGlyph,
	placement GlyphPlacement, page AtlasPage, color gg.Color) {
	scale_inv := renderer.scale_inv

	// Quad offset relative to placement origin
	dx := f32(cg.left) * scale_inv
	dy := -f32(cg.top) * scale_inv
	w := f32(cg.width) * scale_inv
	h := f32(cg.height) * scale_inv

	// UV coordinates
	atlas_w := f32(page.width)
	atlas_h := f32(page.height)
	u0 := f32(cg.x) / atlas_w
	v0 := f32(cg.y) / atlas_h
	u1 := (f32(cg.x) + f32(cg.width)) / atlas_w
	v1 := (f32(cg.y) + f32(cg.height)) / atlas_h

	// Quad corners relative to placement point
	mut x0 := dx
	mut y0 := dy
	mut x1 := dx + w
	mut y1 := dy
	mut x2 := dx + w
	mut y2 := dy + h
	mut x3 := dx
	mut y3 := dy + h

	if placement.angle != 0 {
		transform := affine_rotation(placement.angle)
		x0, y0 = transform.apply(x0, y0)
		x1, y1 = transform.apply(x1, y1)
		x2, y2 = transform.apply(x2, y2)
		x3, y3 = transform.apply(x3, y3)
	}

	// Translate to screen position
	x0 += placement.x
	y0 += placement.y
	x1 += placement.x
	y1 += placement.y
	x2 += placement.x
	y2 += placement.y
	x3 += placement.x
	y3 += placement.y

	sgl.c4b(color.r, color.g, color.b, color.a)
	sgl.v2f_t2f(x0, y0, u0, v0)
	sgl.v2f_t2f(x1, y1, u1, v0)
	sgl.v2f_t2f(x2, y2, u1, v1)
	sgl.v2f_t2f(x3, y3, u0, v1)
}
```

**Step 2: Format and check syntax**

Run: `v fmt -w renderer.v && v -check-syntax renderer.v`
Expected: no errors

**Step 3: Commit**

```
git add renderer.v
git commit -m "add draw_layout_placed() on Renderer"
```

---

### Task 4: Add draw_layout_placed() on TextSystem

**Files:**
- Modify: `api.v` (add after `draw_layout_rotated_with_gradient`,
  ~line 389)

**Step 1: Add TextSystem method**

```v ignore
// draw_layout_placed renders glyphs at individual placements.
// Each GlyphPlacement provides absolute screen position and
// rotation. Decorations are skipped. placements.len must equal
// layout.glyphs.len.
pub fn (mut ts TextSystem) draw_layout_placed(l Layout,
	placements []GlyphPlacement) {
	if ts.renderer == unsafe { nil } {
		return
	}
	ts.renderer.draw_layout_placed(l, placements)
}
```

**Step 2: Format and check syntax**

Run: `v fmt -w api.v && v -check-syntax api.v`
Expected: no errors

**Step 3: Commit**

```
git add api.v
git commit -m "add draw_layout_placed() on TextSystem"
```

---

### Task 5: Add path_text example

**Files:**
- Create: `examples/path_text.v`

**Step 1: Write the example**

```v ignore
// path_text.v demonstrates text rendered along a circular arc.
//
// Features shown:
// - glyph_positions() to get per-glyph advances
// - draw_layout_placed() for per-glyph positioning
// - Circular arc placement with tangent rotation
//
// Run: v run examples/path_text.v
module main

import gg
import vglyph
import math

struct PathApp {
mut:
	ctx      &gg.Context          = unsafe { nil }
	vcontext &vglyph.Context      = unsafe { nil }
	renderer &vglyph.Renderer     = unsafe { nil }
	layout   vglyph.Layout
	angle    f32 // animation offset
}

fn main() {
	mut app := &PathApp{}
	app.ctx = gg.new_context(
		bg_color:     gg.rgb(30, 30, 30)
		width:        800
		height:       600
		window_title: 'Text on Circular Path'
		init_fn:      init
		frame_fn:     frame
		user_data:    app
	)
	app.ctx.run()
}

fn init(mut app PathApp) {
	app.vcontext = vglyph.new_context(app.ctx.scale) or {
		panic(err)
	}
	app.renderer = vglyph.new_renderer(mut app.ctx, app.ctx.scale)

	cfg := vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans Bold 28'
			color:     gg.white
		}
	}
	app.layout = app.vcontext.layout_text(
		'Hello from the curve!', cfg) or {
		println('Error: ${err}')
		return
	}
}

fn frame(mut app PathApp) {
	app.ctx.begin()

	// Animate rotation
	app.angle += 0.005
	if app.angle > math.pi * 2 {
		app.angle -= math.pi * 2
	}

	// Circle parameters
	cx := f32(400) // center x
	cy := f32(300) // center y
	radius := f32(180)

	// Get glyph advances from layout
	glyph_info := app.layout.glyph_positions()
	if glyph_info.len == 0 {
		app.ctx.end()
		return
	}

	// Total advance width for centering on arc
	mut total_advance := f32(0)
	for gi in glyph_info {
		total_advance += gi.advance
	}

	// Convert total advance to arc angle
	arc_span := total_advance / radius

	// Start angle: center text on arc, offset by animation
	start_angle := app.angle - arc_span / 2.0

	// Place each glyph along the arc
	mut placements := []vglyph.GlyphPlacement{
		len: app.layout.glyphs.len
	}
	mut cur_advance := f32(0)
	for gi in glyph_info {
		// Arc-length position for glyph center
		mid := cur_advance + gi.advance * 0.5
		theta := start_angle + mid / radius

		// Position on circle
		gx := cx + radius * f32(math.cos(theta))
		gy := cy + radius * f32(math.sin(theta))

		// Tangent angle (perpendicular to radius = theta + pi/2)
		tangent := theta + f32(math.pi) / 2.0

		placements[gi.index] = vglyph.GlyphPlacement{
			x:     gx
			y:     gy
			angle: tangent
		}
		cur_advance += gi.advance
	}

	app.renderer.draw_layout_placed(app.layout, placements)
	app.renderer.commit()
	app.ctx.end()
}
```

**Step 2: Format and check syntax**

Run: `v fmt -w examples/path_text.v && v -check-syntax examples/path_text.v`
Expected: no errors

**Step 3: Run the example visually**

Run: `v run examples/path_text.v`
Expected: window showing "Hello from the curve!" rendered along a
rotating circular arc.

**Step 4: Commit**

```
git add examples/path_text.v
git commit -m "add path_text example for text-on-curve"
```

---

### Task 6: Run full test suite

**Step 1: Run all tests**

Run: `v test .`
Expected: all tests PASS, no regressions

**Step 2: Verify no formatting issues**

Run: `v fmt -w layout_types.v renderer.v api.v _placed_test.v`
Expected: no changes
