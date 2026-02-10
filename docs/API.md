# vglyph API Reference

This document provides a detailed reference for the public API of the `vglyph`
library.

## Table of Contents

- [TextSystem](#textsystem) - High-level API for easy rendering.
- [TextConfig](#textconfig) - Configuration for styling/layout.
- [AffineTransform](#affinetransform) - 2D matrix transform for drawing.
- [TextStyle](#textstyle) - Character styling attributes.
- [BlockStyle](#blockstyle) - Paragraph layout attributes.
- [Context](#context-struct) - Low-level text layout engine.
- [Layout](#layout-struct) - Result of text shaping.
- [Renderer](#renderer-struct) - Low-level rendering engine.
- [Font Management](#font-management)
- [Rich Text API](#rich-text-api)
- [Accessibility](#accessibility)

---

## TextSystem

➡️ `struct TextSystem`

The high-level entry point for `vglyph`. It manages the `Context`, `Renderer`,
and an internal layout cache to optimize performance.

### Initialization

➡️ `fn new_text_system(mut gg_ctx gg.Context) !&TextSystem`

Creates a new `TextSystem` using the default 1024x1024 glyph atlas.

- **Parameters**:
    - `gg_ctx`: A mutable reference to your `gg.Context`.
- **Returns**: A pointer to the new `TextSystem` or an error.

➡️ `fn new_text_system_atlas_size(mut gg_ctx gg.Context, width int, height int) !&TextSystem`

Creates a new `TextSystem` with a custom-sized glyph atlas. Useful for
high-resolution displays or large character sets.

### TextSystem Methods

➡️ `fn (mut ts TextSystem) add_font_file(path string) bool`

Loads a local font file (TTF/OTF) for use.

- **Parameters**:
    - `path`: Path to the font file.
- **Returns**: `true` if successful.
- **Usage**: After loading `assets/myfont.ttf`, rely on the *Family Name*
  (e.g. "MyFont") in your `TextConfig`, not the filename.

➡️ `fn (mut ts TextSystem) commit()`

**CRITICAL**: Must be called once at the end of your frame (after all
`draw_text` calls). Uploads the modified glyph atlas texture to the GPU and
pushes any pending accessibility updates to the screen reader.

➡️ `fn (mut ts TextSystem) draw_text(x f32, y f32, text string, cfg TextConfig) !`

Renders text at the specified coordinates.

- **Parameters**:
    - `x`, `y`: Screen coordinates (top-left of the layout box).
    - `text`: The string to render.
    - `cfg`: Configuration for font, alignment, color, etc.
- **Note**: This method checks the internal cache. If the layout exists, it
  draws immediately. If not, it performs shaping (expensive) and caches the
  result.
  - **Accessibility**: If `enable_accessibility(true)` has been called, this
  automatically adds the text to the accessibility tree.

➡️ `fn (mut ts TextSystem) enable_accessibility(enabled bool)`

Enables or disables automatic accessibility updates.

- **Parameters**:
    - `enabled`: If `true`, `draw_text`, `draw_layout`, and
      `draw_layout_transformed` automatically publish to the accessibility tree.
- **Default**: `false`.

➡️ `fn (mut ts TextSystem) font_height(cfg TextConfig) f32`

Returns the true height of the font (ascent + descent) in pixels. This is the
vertical space the font claims, including descenders, regardless of the actual
text content.

➡️ `fn (ts &TextSystem) get_atlas_image() gg.Image`

Returns the underlying `gg.Image` of the glyph atlas. Useful for debugging or
custom rendering effects.

➡️ `fn (mut ts TextSystem) resolve_font_name(name string) string`

Returns the actual font family name that Pango resolves for the given font
description string.

- **Parameters**:
    - `name`: The font description name (e.g. `'Arial'`, `'Sans Bold'`).
- **Returns**: The resolved family name (e.g. `'Arial'` or `'Verdana'` if fallback happened).
- **Usage**: Useful for debugging system font loading and fallback behavior.

➡️ `fn (mut ts TextSystem) text_height(text string, cfg TextConfig) !f32`

Calculates the visual height of the text. This accounts for the actual ink
bounds of the glyphs, which may differ from logical line height.

➡️ `fn (mut ts TextSystem) text_width(text string, cfg TextConfig) !f32`

Calculates the logical width of the text without rendering it. Useful for layout
calculations (e.g., center alignment parent containers).

➡️ `fn (mut ts TextSystem) layout_text(text string, cfg TextConfig) !Layout`

Computes the layout for a string without caching.

➡️ `fn (mut ts TextSystem) layout_text_cached(text string, cfg TextConfig) !Layout`

Computes the layout for a string with caching. Returns cached result if available.

➡️ `fn (mut ts TextSystem) layout_rich_text(rt RichText, cfg TextConfig) !Layout`

Computes the layout for a `RichText` object. The `rt.runs` are concatenated to
form the full text. `cfg` provides the base paragraph style (alignment, wrapping,
default font).

➡️ `fn (mut ts TextSystem) draw_layout(l Layout, x f32, y f32)`

Renders a pre-computed layout at the specified coordinates.

➡️ `fn (mut ts TextSystem) draw_layout_transformed(l Layout, x f32, y f32, t AffineTransform)`

Renders a pre-computed layout with an affine transform matrix. Supports rotate,
translate, and skew in one call.

➡️ `fn (mut ts TextSystem) draw_layout_rotated(l Layout, x f32, y f32, angle f32)`

Renders a pre-computed layout rotated by the specified angle (radians).
Convenience wrapper around `draw_layout_transformed`.

➡️ `fn (mut ts TextSystem) font_metrics(cfg TextConfig) TextMetrics`

Returns font metrics (ascender, descender, height, line_gap) for the given config.

➡️ `fn (mut ts TextSystem) update_accessibility(l Layout, x f32, y f32)`

Manually adds a layout to the accessibility tree for the current frame.

- **Parameters**:
    - `l`: The text layout to publish.
    - `x`, `y`: Screen coordinates where the text is drawn.
- **Usage**: Call this if you are using `draw_layout` manually and haven't
  enabled automatic accessibility, or for custom controls.

---

## TextConfig

➡️ `struct TextConfig`

Configuration struct for defining how text should be laid out and styled. It composes `TextStyle`
and `BlockStyle`.

| Field            | Type              | Default       | Description                                          |
|:-----------------|:------------------|:--------------|:-----------------------------------------------------|
| `style`          | `TextStyle`       | `{}`          | Character styling attributes.                        |
| `block`          | `BlockStyle`      | `{}`          | Paragraph layout attributes.                         |
| `use_markup`     | `bool`            | `false`       | Enable [Pango Markup](./GUIDES.md#rich-text-markup). |
| `no_hit_testing` | `bool`            | `false`       | Disable hit-testing rect calculation.                |
| `orientation`    | `TextOrientation` | `.horizontal` | Text orientation (`.horizontal`, `.vertical`).       |

## AffineTransform

➡️ `struct AffineTransform`

2D affine matrix for draw transforms:
`[xx xy x0; yx yy y0; 0 0 1]`.

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `xx`  | `f32` | `1.0` | X axis scale/rotation component |
| `xy`  | `f32` | `0.0` | X axis skew/rotation component |
| `yx`  | `f32` | `0.0` | Y axis skew/rotation component |
| `yy`  | `f32` | `1.0` | Y axis scale/rotation component |
| `x0`  | `f32` | `0.0` | Translation on X |
| `y0`  | `f32` | `0.0` | Translation on Y |

➡️ `fn affine_identity() AffineTransform`

Returns identity matrix.

➡️ `fn affine_rotation(angle f32) AffineTransform`

Returns rotation matrix (radians) around origin.

➡️ `fn affine_translation(dx f32, dy f32) AffineTransform`

Returns translation matrix.

➡️ `fn affine_skew(skew_x f32, skew_y f32) AffineTransform`

Returns skew matrix using direct shear factors.

## TextStyle

➡️ `struct TextStyle`

Defines character-level styling attributes.

| Field               | Type             | Default       | Description                                          |
|:--------------------|:-----------------|:--------------|:-----------------------------------------------------|
| `font_name`         | `string`         | -             | Pango font description (e.g. `'Sans Bold 12'`).      |
| `typeface`          | `Typeface`       | `.regular`    | Bold/italic override (see Typeface enum).            |
| `size`              | `f32`            | `0.0`         | Explicit size (points). 0 = use `font_name`.         |
| `color`             | `gg.Color`       | `black`       | Default text color.                                  |
| `bg_color`          | `gg.Color`       | `transparent` | Background color (highlight).                        |
| `underline`         | `bool`           | `false`       | Draw a single underline.                             |
| `strikethrough`     | `bool`           | `false`       | Draw a strikethrough line.                           |
| `features`          | `&FontFeatures`  | `nil`         | Advanced typography settings.                        |
| `object`            | `&InlineObject`  | `nil`         | Inline object definition (reserved space).           |

## Typeface

➡️ `enum Typeface`

Programmatic control over bold/italic without modifying `font_name` string.

| Value         | Description                                      |
|:--------------|:-------------------------------------------------|
| `.regular`    | Default - preserves style from `font_name`.      |
| `.bold`       | Override weight to bold.                         |
| `.italic`     | Override style to italic.                        |
| `.bold_italic`| Override to bold + italic.                       |

**Note**: Variable font `wght` axis (in `FontFeatures`) applies after typeface and can
override the bold weight.

## FontFeatures

➡️ `struct FontFeatures`

Container for advanced OpenType features and variable font settings.

| Field               | Type            | Default | Description                                              |
|:--------------------|:----------------|:--------|:---------------------------------------------------------|
| `opentype_features` | `[]FontFeature` | `[]`    | List of OpenType features (e.g. `[{'smcp', 1}]`).        |
| `variation_axes`    | `[]FontAxis`    | `[]`    | List of Variable Font axes (e.g. `[{'wght', 700.0}]`).   |

## InlineObject

➡️ `struct InlineObject`

Defines a custom object to be inserted into the text flow. The layout engine
reserves space for it, but the user is responsible for drawing the content.

| Field    | Type     | Default | Description                                      |
|:---------|:---------|:--------|:-------------------------------------------------|
| `id`     | `string` | -       | Unique identifier for the object.                |
| `width`  | `f32`    | `0.0`   | Width of the reserved space (pixels).            |
| `height` | `f32`    | `0.0`   | Height of the reserved space (pixels).           |
| `offset` | `f32`    | `0.0`   | Vertical offset from the baseline (positive up). |

## BlockStyle

➡️ `struct BlockStyle`

Defines paragraph-level layout attributes.

| Field   | Type        | Default | Description                                          |
|:--------|:------------|:--------|:-----------------------------------------------------|
| `width` | `f32`       | `-1.0`  | Wrapping width in pixels. `-1` denotes no wrapping.  |
| `align` | `Alignment` | `.left` | Horizontal alignment (`.left`, `.center`, `.right`). |
| `wrap`  | `WrapMode`  | `.word` | Wrapping strategy (`.word`, `.char`, `.word_char`).  |
| `indent`| `f32`       | `0.0`   | Indentation of first line (neg for hanging).         |
| `tabs`  | `[]int`     | `[]`    | Custom tab stops in pixels.                          |

## Rich Text API

➡️ `struct RichText`

A container for a sequence of style runs, forming a complete paragraph.

- `runs`: `[]StyleRun`

➡️ `struct StyleRun`

A chunk of text with a specific style.

- `text`: `string`
- `style`: `TextStyle`

## TextMetrics

➡️ `struct TextMetrics`

Font metrics for a specific configuration. All values in pixels.

| Field      | Type  | Description                                           |
|:-----------|:------|:------------------------------------------------------|
| `ascender` | `f32` | Distance from baseline to top of font bounding box.   |
| `descender`| `f32` | Distance from baseline to bottom of font bounding box.|
| `height`   | `f32` | Total height (ascender + descender).                  |
| `line_gap` | `f32` | Recommended spacing between lines.                    |

---

## Context (Struct)

➡️ `struct Context`

**Advanced Usage**. Manages the connection to Pango/HarfBuzz. Most users should
use `TextSystem` instead.

### Context Methods

➡️ `fn (mut ctx Context) layout_text(text string, cfg TextConfig) !Layout`

Performs the "Shaping" process.

- Converts text into glyphs, positions them, and wraps lines.
- **Expensive Operation**: Should not be called every frame for the same text.
  Store the result if using `Context` directly.

➡️ `fn new_context(scale_factor f32) !&Context`

Creates a new Pango context.

- **Parameters**:
    - `scale_factor`: Scale factor for HiDPI displays (e.g., `2.0` for Retina).

➡️ `fn (mut ctx Context) resolve_font_name(font_desc_str string) string`

Returns the actual font family name that Pango resolves for the given font
description string.

- **Parameters**:
    - `font_desc_str`: The font description name (e.g. `'Arial'`, `'Sans Bold'`).
- **Returns**: The resolved family name (e.g. `'Arial'` or `'Verdana'` if fallback happened).
- **Usage**: Useful for debugging system font loading and fallback behavior.

---

## Layout (Struct)

➡️ `struct Layout`

A pure V struct containing the result of the shaping process. It is "baked" and
decoupled from Pango.

### Fields

- `items`: List of `Item` (runs of text with same font/style).
- `char_rects`: List of pre-calculated bounding boxes for every character.
- `width`: Logical width of the text layout. (e.g. advance width).
- `height`: Logical height of the text layout.
- `visual_width`: Ink/Visual width (actual pixels drawn).
- `visual_height`: Ink/Visual height (actual pixels drawn).

### Layout Methods

➡️ `fn (l Layout) get_closest_offset(x f32, y f32) int`

Returns the byte index of the character closest to the given coordinates. Unlike
`hit_test`, this always returns a valid index (nearest character), making it
ideal for handling cursor placement when clicking outside exact character bounds.

➡️ `fn (l Layout) get_selection_rects(start int, end int) []gg.Rect`

Returns a list of rectangles covering the text range `[start, end)`. Useful for
drawing selection highlights. Handles multi-line selections correctly.

➡️ `fn (l Layout) hit_test(x f32, y f32) int`

Returns the byte index of the character at the given local coordinates. Returns
`-1` if no character is hit.

➡️ `fn (l Layout) hit_test_rect(x f32, y f32) ?gg.Rect`

Returns the bounding box (`gg.Rect`) of the character at the given coordinates.


## Renderer (Struct)

➡️ `struct Renderer`

**Advanced Usage**. Handles the glyph atlas and low-level drawing commands.

### Renderer Methods

➡️ `fn (mut r Renderer) commit()`

Uploads the texture atlas. Same requirement as `TextSystem.commit()`.

➡️ `fn (mut r Renderer) draw_layout(layout Layout, x f32, y f32)`

Queues the draw commands for a given layout.

➡️ `fn (mut r Renderer) draw_layout_transformed(layout Layout, x f32, y f32, t AffineTransform)`

Queues transformed draw commands for a layout.

➡️ `fn (mut r Renderer) draw_layout_rotated(layout Layout, x f32, y f32, angle f32)`

Queues rotated draw commands for a layout.

➡️ `fn new_renderer(mut ctx gg.Context, scale_factor f32) &Renderer`

Creates a renderer with default settings (1024x1024 atlas).

- **Parameters**:
    - `ctx`: A mutable reference to your `gg.Context`.
    - `scale_factor`: Scale factor for HiDPI displays (e.g., `2.0` for Retina).

➡️ `fn new_renderer_atlas_size(mut ctx gg.Context, w int, h int, scale f32) &Renderer`

Creates a renderer with a custom-sized glyph atlas.

- **Parameters**:
    - `ctx`: A mutable reference to your `gg.Context`.
    - `width`, `height`: Atlas dimensions in pixels.
    - `scale_factor`: Scale factor for HiDPI displays.

---

## IME Overlay API

➡️ **macOS only** (`$if darwin`)

Overlay API for CJK IME support via transparent NSView above MTKView.

➡️ `fn ime_overlay_create_auto(ns_window voidptr) voidptr`

Creates overlay by auto-discovering MTKView from NSWindow.

- **Parameters**:
    - `ns_window`: NSWindow handle from `C.sapp_macos_get_window()`.
- **Returns**: Overlay handle or NULL on failure.

➡️ `fn ime_overlay_register_callbacks(handle voidptr, on_marked_text fn,
on_insert_text fn, on_do_command fn, on_get_rect fn, on_clause fn, user_data
voidptr)`

Registers per-overlay IME callbacks.

- **Parameters**:
    - `handle`: Overlay handle from `ime_overlay_create_auto`.
    - `on_marked_text`: Callback for preedit text updates.
    - `on_insert_text`: Callback for committed text insertion.
    - `on_do_command`: Callback for IME commands (cancel, etc).
    - `on_get_rect`: Callback to provide field bounds for candidate window.
    - `on_clause`: Callback for clause info (multi-segment underlines).
    - `user_data`: Arbitrary pointer passed to callbacks.

➡️ `fn ime_overlay_set_focused_field(handle voidptr, field_id string)`

Activates overlay for specific text field.

- **Parameters**:
    - `handle`: Overlay handle.
    - `field_id`: Text field identifier.

➡️ `fn ime_overlay_free(handle voidptr)`

Destroys overlay and cancels any active composition.

➡️ `fn ime_discover_mtkview(ns_window voidptr) voidptr`

Low-level: discovers MTKView from NSWindow view hierarchy.

- **Parameters**:
    - `ns_window`: NSWindow handle.
- **Returns**: MTKView handle or NULL if not found.

**Note:** Non-macOS platforms provide stubs returning NULL.

---

## Font Management

For details on loading and using fonts, please refer to the
[Guides](./GUIDES.md#font-management).

## Accessibility

For details on enabling and using accessibility features, please refer to the
[Accessibility Guide](./ACCESSIBILITY.md).
