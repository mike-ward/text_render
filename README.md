# VGlyph

A high-performance text rendering engine for the V programming language, built on
**Pango**, **FreeType**, and **Sokol**.

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
- **High Performance**: Automatic layout caching and batched GPU rendering.
- **Local Fonts**: Load `.ttf` / `.otf` files directly from your assets folder.
- **Hit Testing**: Efficiently retrieve character indices or bounding boxes from
  mouse coordinates.

## 📦 Prerequisites

You must have **Pango** and **FreeType** installed.

### macOS (Homebrew)
```bash
brew install pango freetype pkg-config
```

### Linux (Debian/Ubuntu)
```bash
sudo apt-get install libpango1.0-dev libfreetype6-dev pkg-config
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

## License

MIT