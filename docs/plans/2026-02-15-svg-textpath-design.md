# SVG `<textPath>` Support Design

## Problem

The gui framework's SVG parser ignores `<textPath>` elements. The
"Text with Fonts" sample in `examples/svg_viewer.v` contains:

```xml
<path id="curvePath" d="M40 220 Q200 160 360 220" fill="none"/>
<text><textPath href="#curvePath" startOffset="50%"
  text-anchor="middle">Text Following a Curved Path</textPath></text>
```

This text silently disappears because `parse_text_element` strips
everything from the first `<` via `extract_plain_text`.

## Approach

**Approach A: New `DrawLayoutPlaced` Renderer.** Parse `<textPath>`
into a new struct, compute arc-length parameterized glyph placements,
render via vglyph's existing `draw_layout_placed()`.

All new code lives in gui. No vglyph changes needed.

## Data Structures

### `SvgTextPath` (new, in `svg_vector.v`)

```v ignore
pub struct SvgTextPath {
pub:
    text             string
    path_id          string // references defs_paths key
    start_offset     f32    // 0.0-1.0 for %, absolute for length
    is_percent       bool   // true if startOffset was percentage
    anchor           u8     // 0=start, 1=middle, 2=end
    spacing          u8     // 0=auto, 1=exact
    method           u8     // 0=align, 1=stretch
    side             u8     // 0=left, 1=right
    font_family      string
    font_size        f32
    bold             bool
    italic           bool
    color            Color
    opacity          f32 = 1.0
    filter_id        string
    fill_gradient_id string
    letter_spacing   f32
    stroke_color     Color = color_transparent
    stroke_width     f32
}
```

### `VectorGraphic` changes

Add `defs_paths: map[string]string` (id -> raw `d` attribute).
Populated during the existing `<defs>` pre-pass.

### `ParseState` changes

Add `text_paths: []SvgTextPath`.

### `CachedSvg` changes

Add `text_paths: []SvgTextPath` and `defs_paths: map[string]string`.

### `SvgFilteredGroup` / `CachedFilteredGroup` changes

Add `text_paths: []SvgTextPath`.

### `DrawLayoutPlaced` (new renderer variant)

```v ignore
struct DrawLayoutPlaced {
    layout     &vglyph.Layout
    placements []vglyph.GlyphPlacement
}
```

Added to the `Renderer` sumtype.

## Parsing

### Defs path extraction

New function `parse_defs_paths(content) map[string]string` extracts
`<path id="..." d="..."/>` from `<defs>` blocks. Parallels
existing `parse_defs_clip_paths()` pattern. Called from
`parse_svg()`.

### textPath parsing

In `parse_text_element`, before the tspan check, detect `<textPath`
in body. If found, call `parse_textpath_element()` which:

1. Extracts `href` (or `xlink:href`) -> strip `#` -> path_id
2. Extracts `startOffset` (% or absolute)
3. Extracts `text-anchor` (overrides parent)
4. Extracts `spacing`, `method`, `side`
5. Extracts text content
6. Inherits font/color/stroke from parent `<text>`
7. Appends to `state.text_paths`

### Filter group propagation

Same partitioning pattern as texts: `SvgFilteredGroup` gains
`text_paths` field. Filter partitioning in `parse_svg()` handles
text_paths alongside texts.

## Arc-Length Parameterization

New file: `svg_textpath.v`

### Pipeline

1. **Flatten to polyline** -- reuse `parse_path_d()` +
   `flatten_path()` to convert `d` attribute to polyline. Handles
   all SVG path commands (arcs already converted to cubics).

2. **Build cumulative arc-length table** -- walk polyline, compute
   segment lengths, store cumulative distances. `table[i]` =
   distance from start to point `i`.

3. **Sample at distance** -- binary search table for enclosing
   segment, linearly interpolate position. Returns `(x, y)`.

4. **Tangent at distance** -- `atan2(dy, dx)` of enclosing segment.
   For `side=right`, add pi.

### Functions

```
fn flatten_defs_path(d string, scale f32) []f32
fn build_arc_length_table(polyline []f32) []f32
fn sample_path_at(polyline []f32, table []f32, dist f32) (f32, f32, f32)
```

### startOffset resolution

- Percentage: `offset = start_offset * total_length`
- Absolute: `offset = start_offset * scale`

### text-anchor adjustment

After computing total advance from `glyph_positions()`:
- `start`: begin at offset
- `middle`: begin at `offset - total_advance/2`
- `end`: begin at `offset - total_advance`

### method=stretch

Scale glyph advances so total width equals remaining path length.

### spacing=exact

Place each glyph at exact computed distance (no curvature
adjustment). With polyline sampling both modes produce similar
results.

## Glyph Placement & Rendering

### `render_svg_text_path`

New function called from `render_svg` alongside `render_svg_text`:

```
fn render_svg_text_path(tp SvgTextPath,
    defs_paths map[string]string,
    shape_x f32, shape_y f32, scale f32,
    gradients map[string]SvgGradientDef,
    mut window Window)
```

Steps:
1. Look up `defs_paths[tp.path_id]`. Return if not found.
2. Flatten path via `flatten_defs_path(d, scale)`.
3. Build arc-length table.
4. Create Layout via `window.text_system.layout_text()`.
5. Get glyph advances via `layout.glyph_positions()`.
6. Compute total advance. Apply anchor adjustment.
7. If stretch, scale advances to fit path.
8. For each glyph: sample `(x, y, angle)` at
   `offset + glyph_center`, shift back by half advance.
   Build `GlyphPlacement`.
9. Emit `DrawLayoutPlaced{ layout, placements }`.

### Renderer flush

```v ignore
DrawLayoutPlaced {
    window.text_system.draw_layout_placed(
        renderer.layout, renderer.placements)
}
```

### render_svg integration

After existing text loop:
```v ignore
for tp in cached.text_paths {
    render_svg_text_path(tp, cached.defs_paths, ...)
}
```

Same in filtered groups loop.

### PDF

`DrawLayoutPlaced` in `print_pdf.v` -- no-op initially.

## Testing

### `_svg_textpath_test.v`

**Arc-length math:**
- `test_build_arc_length_table` -- straight line distances
- `test_sample_path_at_midpoint` -- midpoint coords
- `test_sample_path_at_endpoints` -- boundary conditions
- `test_sample_path_at_angle` -- L-shaped polyline angles

**Parsing:**
- `test_parse_textpath_href` -- `href="#id"` extraction
- `test_parse_textpath_xlink_href` -- `xlink:href` fallback
- `test_parse_textpath_start_offset_percent` -- 50% -> 0.5
- `test_parse_textpath_start_offset_absolute` -- absolute length
- `test_parse_textpath_attributes` -- spacing, method, side
- `test_parse_textpath_inherits_font` -- parent inheritance

**Integration:**
- `test_parse_svg_with_textpath` -- full SVG round-trip

**Manual verification:**
Run `v run examples/svg_viewer.v`, select "Text with Fonts" --
curved text should render along the Bezier.

## Files Modified

| File | Change |
|------|--------|
| `svg_vector.v` | Add `SvgTextPath`, `defs_paths` to `VectorGraphic` |
| `svg.v` | `parse_defs_paths()`, textPath detection in `parse_text_element`, filter partitioning |
| `svg_textpath.v` | **New.** Arc-length math + `render_svg_text_path` |
| `svg_load.v` | Propagate `text_paths`/`defs_paths` to `CachedSvg` |
| `render.v` | `DrawLayoutPlaced` variant + flush case + `render_svg` calls |
| `print_pdf.v` | `DrawLayoutPlaced` no-op case |
| `_svg_textpath_test.v` | **New.** Tests |
