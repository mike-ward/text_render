# VGlyph

> **Note:** VGlyph is in active development (v0.1.0). The API is stabilizing
> but may change.

A high-performance text rendering engine for the V programming language, built
on **Pango**, **HarfBuzz**, **FreeType**, and **Sokol**.

![demo](assets/screenshot.png)

VGlyph provides production-grade text layout—including bidirectional text,
complex scripts, and rich text markup—while remaining easy to use.

## 📚 Documentation

- [**API Reference**](docs/API.md): Detailed API documentation for `TextSystem`,
  `TextConfig`, etc.
- [**Guides**](docs/GUIDES.md): Rich Text Markup, Font Loading, and Performance
  tips.
- [**Architecture**](docs/ARCHITECTURE.md): High-level design and data flow.


## ✨ Features

- **Complex Layout**: Proper support for Arabic, Hebrew, and advanced typography
  via Pango.
- **Advanced Typography**: Support for OpenType features (small caps, old-style
  nums) and custom tab stops.
- **Rich Text**: Use `<span>` tags for colors, fonts, and styles within a single
  string.
- **High Performance**: Automatic layout caching (10,000+ entry LRU cache),
  batched GPU rendering, and dynamic glyph atlas resizing.
- **Local Fonts**: Load `.ttf` / `.otf` files directly from your assets folder.
- **Hit Testing**: Efficiently retrieve character indices or bounding boxes from
  mouse coordinates.
- **Font Fallback**: Automatic multilingual support with robust font fallback
  for emojis and complex scripts.
- **Text Decorations**: Built-in underline and strikethrough support via
  `TextConfig`.
- **High-DPI Support**: Automatic DPI scaling for crisp rendering on all
  displays.
- **LCD Subpixel Antialiasing**: Exploits LCD subpixel structure for sharper
  text rendering, combined with **Subpixel Positioning** for smooth animations.
- **Text Measurement**: Query text dimensions (`text_width`, `text_height`,
  `font_height`) for precise layout calculations.

## 📦 Prerequisites

You must have **Pango** and **FreeType** installed.

### macOS (Homebrew)
```bash
brew install pango freetype pkg-config
```

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install libpango1.0-dev libfreetype6-dev pkg-config
# For comprehensive emoji and multilingual support
sudo apt-get install fonts-noto fonts-noto-color-emoji
```

### Windows (vcpkg or MSYS2)
```bash
# vcpkg
vcpkg install pango freetype

# Or MSYS2
pacman -S mingw-w64-x86_64-pango mingw-w64-x86_64-freetype
```

## 🚀 Quickstart

Use the `TextSystem` for the easiest integration. It handles initialization,
caching, and rendering.

```v
import vglyph
import gg

struct App {
mut:
	gg &gg.Context        = unsafe { nil }
	ts &vglyph.TextSystem = unsafe { nil }
}

fn main() {
	mut app := &App{}
	app.gg = gg.new_context(
		bg_color:     gg.white
		width:        800
		height:       600
		window_title: 'VGlyph Demo'
		init_fn:      init
		frame_fn:     frame
		user_data:    app
	)
	app.gg.run()
}

fn init(mut app App) {
	// 1. Initialize TextSystem
	app.ts = vglyph.new_text_system(mut app.gg) or { panic(err) }
}

fn frame(mut app App) {
	app.gg.begin()

	// 2. Draw Text
	// Coordinates are (x, y)
	app.ts.draw_text(100, 100, 'Hello VGlyph!', vglyph.TextConfig{
		font_name: 'Sans Bold 30'
		color:     gg.black
	}) or { println(err) }

	app.gg.end()

	// 3. Commit Texture Uploads (Important!)
	app.ts.commit()
}
```

## 📖 Examples

The `examples/` directory contains several demonstrations:

- **`demo.v`** - Multilingual text, wrapping, and rich text markup
- **`emoji_demo.v`** - Emoji and color bitmap rendering
- **`editor_demo.v`** - Interactive text editing with cursor placement
- **`typography_demo.v`** - OpenType features and custom tab stops
- **`stress_demo.v`** - Performance testing with thousands of glyphs

Run any example with:
```bash
v run examples/demo.v
```

## 🔧 Common Operations

### Measuring Text
```oksyntax
width := app.ts.text_width('Hello', cfg)!
height := app.ts.text_height('Hello', cfg)!
font_h := app.ts.font_height(cfg)
```

### Font Introspection
```oksyntax
// Check which font Pango actually resolved
actual_font := app.ts.resolve_font_name('Sans Bold 30')
println('Using font: ${actual_font}')
```

### Advanced Layout Access
```oksyntax
// Get layout for hit testing or custom rendering
layout := app.ts.layout_text('Click me', cfg)!
char_idx := layout.hit_test(mouse_x, mouse_y)
rects := layout.get_selection_rects(0, 5)
```

## 🔧 Troubleshooting

### Text appears blurry or incorrectly sized
Ensure you're calling `commit()` at the end of each frame. Without it, new
glyphs won't upload to the GPU.

### Missing characters (tofu/boxes)
Install comprehensive fallback fonts:
- **macOS**: System fonts should cover most cases
- **Linux**: `sudo apt-get install fonts-noto fonts-noto-color-emoji`
- **Windows**: Install Noto fonts from Google Fonts

### Font not loading from file
Use the font's **family name**, not the filename. Check with:
```oksyntax
println(app.ts.resolve_font_name('YourFont'))
```

### Performance issues with dynamic text
`TextSystem` automatically caches layouts. If text changes every frame (e.g.,
FPS counter), consider using a monospace font and fixed-width formatting to
minimize layout variations.

## License

MIT