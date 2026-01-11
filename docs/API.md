# vglyph API Reference

This document provides a detailed reference for the public API of the `vglyph`
library.

## Table of Contents

- [TextSystem](#textsystem) - High-level API for easy rendering.
- [TextConfig](#textconfig) - Configuration for styling/layout.
- [Context](#context-struct) - Low-level text layout engine.
- [Layout](#layout-struct) - Result of text shaping.
- [Renderer](#renderer-struct) - Low-level rendering engine.
- [Font Management](#font-management)

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
`draw_text` calls). Uploads the modified glyph atlas texture to the GPU. If
omitted, new characters will appear as empty rectangles.

➡️ `fn (mut ts TextSystem) draw_text(x f32, y f32, text string, cfg TextConfig) !`

Renders text at the specified coordinates.

- **Parameters**:
    - `x`, `y`: Screen coordinates (top-left of the layout box).
    - `text`: The string to render.
    - `cfg`: Configuration for font, alignment, color, etc.
- **Note**: This method checks the internal cache. If the layout exists, it
  draws immediately. If not, it performs shaping (expensive) and caches the
  result.

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

---

## TextConfig

➡️ `struct TextConfig`

Configuration struct for defining how text should be laid out and styled.

| Field           | Type        | Default       | Description                                          |
|:----------------|:------------|:--------------|:-----------------------------------------------------|
| `font_name`     | `string`    | -             | Pango font description (e.g. `'Sans Bold 12'`).      |
| `width`         | `int`       | `-1`          | Wrapping width in pixels. `-1` denotes no wrapping.  |
| `align`         | `Alignment` | `.left`       | Horizontal alignment (`.left`, `.center`, `.right`). |
| `wrap`          | `WrapMode`  | `.word`       | Wrapping strategy (`.word`, `.char`, `.word_char`).  |
| `use_markup`    | `bool`      | `false`       | Enable [Pango Markup](./GUIDES.md#rich-text-markup). |
| `color`         | `gg.Color`  | `black`       | Default text color.                                  |
| `bg_color`      | `gg.Color`  | `transparent` | Background color (highlight).                        |
| `underline`       | `bool`             | `false`       | Draw a single underline.                             |
| `strikethrough`   | `bool`             | `false`       | Draw a strikethrough line.                           |
| `tabs`            | `[]int`            | `[]`          | Custom tab stops in pixels.                          |
| `opentype_features`| `map[string]int`  | `{}`          | OpenType feature tags (e.g., `{'smcp': 1}`).         |


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

➡️ `fn new_context() !&Context`

Creates a new Pango context.

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

➡️ `fn new_renderer(mut ctx gg.Context) &Renderer`

Creates a renderer with default settings.

---

## Font Management

For details on loading and using fonts, please refer to the
[Guides](./GUIDES.md#font-management).
