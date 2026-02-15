# Placed Glyph Rendering API

Per-glyph positioned rendering for text-on-curve and similar effects.

## Problem

Frameworks rendering text along paths (SVG, canvas, UI toolkits) need
per-glyph control over position and rotation. vglyph currently only
supports transforms at the layout level. Adding per-glyph placement
as a helper API makes vglyph a convenient backend for path-based text
rendering without pulling path geometry into vglyph itself.

## Design Decisions

- **Layout-based input** — caller shapes text via `layout_text()`,
  then provides per-glyph transforms. Preserves shaping, font
  fallback, and colors.
- **Position + angle only** — no full affine per glyph. Covers the
  text-on-curve use case without unnecessary complexity.
- **Glyphs only** — decorations (underline, strikethrough, background)
  skipped. Curved decorations are complex and rarely needed.
- **Layout colors preserved** — each glyph retains its Item's
  color/stroke settings. No per-placement color override.

## Data Types

```v nofmt
pub struct GlyphPlacement {
pub:
	x     f32 // absolute screen position x
	y     f32 // absolute screen position y (baseline)
	angle f32 // rotation in radians, 0 = normal orientation
}
```

`[]GlyphPlacement` maps 1:1 to `layout.glyphs`. If lengths mismatch,
the method returns early (no-op).

### Glyph Position Query

```v ignore
pub struct GlyphInfo {
pub:
	x       f32 // absolute x position within layout
	y       f32 // baseline y position within layout
	advance f32 // horizontal advance width
	index   int // index into layout.glyphs
}

pub fn (l Layout) glyph_positions() []GlyphInfo
```

Flattens the item/glyph hierarchy into a simple list. Frameworks
accumulate advances along a curve to compute `[]GlyphPlacement`.

## Public API

```v ignore
// TextSystem (api.v)
pub fn (mut ts TextSystem) draw_layout_placed(
	layout Layout, placements []GlyphPlacement)

// Renderer (renderer.v)
pub fn (mut r Renderer) draw_layout_placed(
	layout Layout, placements []GlyphPlacement)
```

TextSystem delegates to Renderer, same pattern as existing
`draw_layout_transformed`.

No gradient, composition, or decoration variants.

## Rendering Implementation

`Renderer.draw_layout_placed` inner loop:

1. Iterate items and glyphs for atlas lookup/caching (unchanged).
2. Replace position calculation: use `placements[glyph_idx].x/y`
   instead of `item.x + glyph.x_offset`.
3. Per-glyph rotation: build `AffineTransform` from
   `placement.angle`, rotate quad vertices around placement point.
4. Stroke pass: if `item.has_stroke`, two-pass rendering (outline
   first, fill second) with per-glyph placement.
5. Subpixel positioning: computed from fractional part of
   `placement.x`, same 4-bin system.

## Example

New `examples/path_text.v` — text along a circular arc:

1. `layout = ts.layout_text("Hello, Curve!", cfg)`
2. `positions = layout.glyph_positions()`
3. Walk positions along arc: accumulate advances as arc-length,
   compute `(x, y)` and tangent angle on circle.
4. `ts.draw_layout_placed(layout, placements)`

## Files Modified

- `layout_types.v` — add `GlyphPlacement`, `GlyphInfo` structs
- `layout_types.v` — add `glyph_positions()` method
- `renderer.v` — add `draw_layout_placed()` method
- `api.v` — add `draw_layout_placed()` method on TextSystem
- `examples/path_text.v` — new example

## Unresolved Questions

None.
