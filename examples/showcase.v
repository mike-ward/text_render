module main

import gg
import vglyph
import math

// =============================================================================
// VGlyph Showcase ShowcaseApplication
// -----------------------------------------------------------------------------
// This application demonstrates the capabilities of the vglyph text rendering
// library. It serves as both a visual gallery and a code reference for
// developers.
// =============================================================================

const window_width = 1000
const window_height = 800
const bg_color = gg.Color{20, 20, 25, 255} // Dark premium background
const text_color = gg.Color{220, 220, 230, 255} // Off-white text

struct ShowcaseApp {
mut:
	ctx           &gg.Context
	ts            &vglyph.TextSystem
	sections      []ShowcaseSection
	scroll_y      f32
	max_scroll    f32
	window_w      int
	window_h      int
	last_layout_w int

	// Interactive Demo State
	interactive_layout vglyph.Layout
	cursor_idx         int
	select_start       int = -1
	is_dragging        bool
	interactive_y      f32

	// Subpixel Demo State
	subpixel_x f32
}

struct ShowcaseSection {
mut:
	title       string
	description string
	layouts     []vglyph.Layout
	height      f32
}

fn main() {
	mut app := &ShowcaseApp{
		ctx:      unsafe { nil }
		ts:       unsafe { nil }
		window_w: window_width
		window_h: window_height
	}

	app.ctx = gg.new_context(
		width:         window_width
		height:        window_height
		bg_color:      bg_color
		window_title:  'VGlyph Showcase'
		init_fn:       init
		frame_fn:      frame
		event_fn:      on_event
		user_data:     app
		create_window: true
		ui_mode:       true
	)

	app.ctx.run()
}

fn init(mut app ShowcaseApp) {
	// Initialize the TextSystem. This sets up the underlying Pango context
	// and the font atlas renderer.
	app.ts = vglyph.new_text_system(mut app.ctx) or { panic(err) }

	// Example: Loading a local font file
	// We load 'feathericon.ttf' from the assets folder.
	if !app.ts.add_font_file('assets/feathericon.ttf') {
		println('Failed to load font file: assets/feathericon.ttf')
	}

	// Create our showcase content
	app.create_content()
}

fn (mut app ShowcaseApp) create_content() {
	// Clear existing layouts if we are re-creating (e.g. on resize)
	app.sections.clear()

	// Calculate content width with some padding
	content_width := f32(app.window_w - 100)
	if content_width < 300 {
		return
	}
	// Safety check

	// =========================================================================
	// Section 1: Introduction
	// =========================================================================
	{
		mut section := ShowcaseSection{
			description: 'High-performance, beautiful text rendering for V.'
		}

		// Large Hero Text
		// We use a large font size and bold weight for impact.
		section.layouts << app.ts.layout_text('VGlyph', vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 80'
				color:     gg.Color{100, 150, 255, 255} // V Blue
			}
			block: vglyph.BlockStyle{
				align: .center
				width: content_width
			}
		}) or { panic(err) }

		// Subtitle
		section.layouts << app.ts.layout_text('High-performance, beautiful text rendering for V',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Light 32'
				color:     gg.Color{180, 180, 190, 255}
			}
			block: vglyph.BlockStyle{
				align: .center
				width: content_width
			}
		}) or { panic(err) }

		// Features Description
		section.layouts << app.ts.layout_text('Ligatures, Bidirectional Text, Emojis, Complex Scripts and more',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 20'
				color:     gg.Color{160, 160, 170, 255}
			}
			block: vglyph.BlockStyle{
				align: .center
				width: content_width
			}
		}) or { panic(err) }

		app.sections << section
	}

	// =========================================================================
	// Section 2: Typography Essentials
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Typography Essentials'
			description: 'Full control over font families, weights, and styles.'
		}

		// Font Families
		families := [
			'Sans-Serif (Default)',
			'Serif',
			'Monospace',
		]
		for family in families {
			font_spec := if family.contains('Sans') {
				'Sans'
			} else if family.contains('Serif') {
				'Times New Roman, Serif'
			} else if family.contains('Mono') {
				'Menlo, Courier New, Monospace'
			} else {
				family
			}
			section.layouts << app.ts.layout_text(family, vglyph.TextConfig{
				style: vglyph.TextStyle{
					font_name: '${font_spec} 24'
					color:     text_color
				}
			}) or { panic(err) }
		}

		// Weights and Slants
		styles := [
			'Thin (100)',
			'Light (300)',
			'Regular (400)',
			'Medium (500)',
			'Bold (700)',
			'Black (900)',
			'Italic',
			'Bold Italic',
		]

		// For different weights in one line, we use Rich Text.
		// Constructing a RichText object allows mixing styles.
		mut runs := []vglyph.StyleRun{}
		for s in styles {
			// Parse the font name from the description
			mut f_name := 'Sans 20'
			if s.contains('Thin') {
				f_name = 'Sans Thin 20'
			} else if s.contains('Light') {
				f_name = 'Sans Light 20'
			} else if s.contains('Medium') {
				f_name = 'Sans Medium 20'
			} else if s.contains('Bold') {
				f_name = 'Sans Bold 20'
			} else if s.contains('Black') {
				f_name = 'Sans Black 20'
			}

			if s.contains('Italic') {
				f_name += ' Italic'
			}

			runs << vglyph.StyleRun{
				text:  s + '   '
				style: vglyph.TextStyle{
					font_name: f_name
					color:     text_color
				}
			}
		}

		section.layouts << app.ts.layout_rich_text(vglyph.RichText{ runs: runs }, vglyph.TextConfig{
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// ---------------------------------------------------------------------
		// New Features: Decorations & Styling
		// ---------------------------------------------------------------------
		// Divider for visual separation
		section.layouts << app.ts.layout_text('Decorations & Styling:', vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 18'
				color:     gg.Color{200, 200, 255, 255}
			}
			block: vglyph.BlockStyle{
				align: .left
			}
		}) or { panic(err) }

		mut deco_runs := []vglyph.StyleRun{}

		// Underline
		deco_runs << vglyph.StyleRun{
			text:  'Underlines '
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     text_color
				underline: true
			}
		}
		deco_runs << vglyph.StyleRun{
			text: ', '
		}

		// Strikethrough
		deco_runs << vglyph.StyleRun{
			text:  'Strikethroughs'
			style: vglyph.TextStyle{
				font_name:     'Sans 24'
				color:         text_color
				strikethrough: true
			}
		}
		deco_runs << vglyph.StyleRun{
			text: ', and '
		}

		// Background Color
		deco_runs << vglyph.StyleRun{
			text:  'Background Colors'
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     gg.white
				bg_color:  gg.Color{200, 50, 100, 255} // Reddish background
			}
		}

		section.layouts << app.ts.layout_rich_text(vglyph.RichText{ runs: deco_runs },
			vglyph.TextConfig{
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// ---------------------------------------------------------------------
		// Advanced Positioning (Scripting)
		// ---------------------------------------------------------------------
		section.layouts << app.ts.layout_text('Subscripts & Superscripts (via OpenType):',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 18'
				color:     gg.Color{200, 200, 255, 255}
			}
		}) or { panic(err) }

		mut script_runs := []vglyph.StyleRun{}

		// Normal
		script_runs << vglyph.StyleRun{
			text:  'Chemical formulas: H'
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     text_color
			}
		}
		// Subscript 2
		script_runs << vglyph.StyleRun{
			text:  '2'
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     text_color
				features:  &vglyph.FontFeatures{
					opentype_features: [
						vglyph.FontFeature{
							tag:   'subs'
							value: 1
						},
					]
				}
			}
		}
		script_runs << vglyph.StyleRun{
			text:  'O.  Physics: E = mc'
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     text_color
			}
		}
		// Superscript 2
		script_runs << vglyph.StyleRun{
			text:  '2'
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     text_color
				features:  &vglyph.FontFeatures{
					opentype_features: [
						vglyph.FontFeature{
							tag:   'sups'
							value: 1
						},
					]
				}
			}
		}

		section.layouts << app.ts.layout_rich_text(vglyph.RichText{ runs: script_runs },
			vglyph.TextConfig{
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// ---------------------------------------------------------------------
		// Mixed Directionality & Scripts
		// ---------------------------------------------------------------------
		section.layouts << app.ts.layout_text('Mixed Directionality:', vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 18'
				color:     gg.Color{200, 200, 255, 255}
			}
		}) or { panic(err) }

		// Note: The visual order should be correct automatically due to bidirectional algorithm.
		// "The word 'سلام' means Hello in Arabic."
		// 'سلام' (Salaam) is RTL.

		bidi_text := 'The word "سلام" means Hello in Arabic.'
		section.layouts << app.ts.layout_text(bidi_text, vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     text_color
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// ---------------------------------------------------------------------
		// Mixed Scripts
		// ---------------------------------------------------------------------
		section.layouts << app.ts.layout_text('Mixed Scripts: Latin, Greek (Γειά σου), Cyrillic (Привет)',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     text_color
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		app.sections << section
	}

	// =========================================================================
	// Section 3: Paragraph Layout
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Layout & Alignment'
			description: 'Powerful paragraph formatting with wrapping and alignment.'
		}

		lorem := 'The quick brown fox jumps over the lazy dog. VGlyph handles long paragraphs with ease, automatically wrapping text to fit the container width. It supports standard alignment modes including Left, Center, and Right.'

		alignments := [
			vglyph.Alignment.left,
			vglyph.Alignment.center,
			vglyph.Alignment.right,
		]
		align_names := ['Left Aligned', 'Center Aligned', 'Right Aligned']

		for i, align in alignments {
			// Header
			section.layouts << app.ts.layout_text(align_names[i], vglyph.TextConfig{
				style: vglyph.TextStyle{
					font_name: 'Sans Bold 16'
					color:     gg.Color{100, 200, 255, 255}
				}
			}) or { panic(err) }

			// Body
			section.layouts << app.ts.layout_text(lorem, vglyph.TextConfig{
				style: vglyph.TextStyle{
					font_name: 'Sans 18'
					color:     gg.Color{200, 200, 200, 255}
				}
				block: vglyph.BlockStyle{
					width: content_width / 2 // Use half width to show alignment better
					align: align
					wrap:  .word
				}
			}) or { panic(err) }
		}

		// RTL Example
		section.layouts << app.ts.layout_text('Right-to-Left, Left Aligned (Arabic)',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 16'
				color:     gg.Color{100, 200, 255, 255}
			}
		}) or { panic(err) }

		arabic_text := 'استمتع بقوة vglyph مع دعم كامل للنص العربي واتجاه الكتابة من اليمين إلى اليسار. هذا مثال على نص طويل لتوضيح كيفية التفاف الأسطر. تظهر هذه الفقرة كيف يتعامل المحرك مع الكلمات والجمل في تخطيط من اليمين لليسار.'
		section.layouts << app.ts.layout_text(arabic_text, vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     gg.Color{200, 200, 200, 255}
			}
			block: vglyph.BlockStyle{
				width: content_width / 2
				align: .left
				wrap:  .word
			}
		}) or { panic(err) }

		// Hanging Indent (Lists)
		// Negative indent creates a hanging indent.
		section.layouts << app.ts.layout_text('Bullet Lists', vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 16'
				color:     gg.Color{100, 200, 255, 255}
			}
		}) or { panic(err) }

		list_items := [
			'•\tFirst item with a hanging indent that wraps nicely to the next line.',
			'•\tSecond item is also quite long to demonstrate the effect of the negative indent value.',
			'•\tThird item.',
		]
		for item in list_items {
			section.layouts << app.ts.layout_text(item, vglyph.TextConfig{
				style: vglyph.TextStyle{
					font_name: 'Sans 18'
					color:     gg.Color{220, 220, 220, 255}
				}
				block: vglyph.BlockStyle{
					width:  content_width / 2
					indent: -20 // Negative value for hanging indent
					tabs:   [20]
					wrap:   .word
				}
			}) or { panic(err) }
		}

		section.layouts << app.ts.layout_text('Numbered Lists', vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 16'
				color:     gg.Color{100, 200, 255, 255}
			}
		}) or { panic(err) }

		numbered_items := [
			'1.\tFirst step in the process involves setting up the environment variable correctly.',
			'2.\tSecond step is to run the compiler with the optimization flags enabled.',
			'3.\tFinally, execute the binary.',
		]
		for item in numbered_items {
			section.layouts << app.ts.layout_text(item, vglyph.TextConfig{
				style: vglyph.TextStyle{
					font_name: 'Sans 18'
					color:     gg.Color{220, 220, 220, 255}
				}
				block: vglyph.BlockStyle{
					width:  content_width / 2
					indent: -20
					tabs:   [20]
					wrap:   .word
				}
			}) or { panic(err) }
		}

		app.sections << section
	}

	// =========================================================================
	// Section 4: Rich Text & Markup
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Rich Text & Markup'
			description: 'Mix styles easily layout objects or simple markup strings.'
		}

		// Option A: Markup String (Pango Markup)
		// This is the easiest way for simple styling.
		markup := '<span size="24pt" foreground="#88AAFF">Markup Support</span>\n' +
			'We support <span weight="bold" foreground="white">bold colors</span>, ' +
			'<i>italics</i>, <s>strikethrough</s>, and <u>underline</u>.\n' +
			'You can even change <span font_family="Monospace" background="#333333"> fonts </span> mid-stream.'

		section.layouts << app.ts.layout_text(markup, vglyph.TextConfig{
			style:      vglyph.TextStyle{
				font_name: 'Sans 20'
				color:     text_color
			}
			use_markup: true
			block:      vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		app.sections << section
	}

	// =========================================================================
	// Section 5: Internationalization
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Internationalization (i18n)'
			description: 'Rendering for complex scripts and Emojis.'
		}

		// Unicode & Emojis
		// VGlyph relies on Pango/HarfBuzz, providing industry-standard shaping.
		samples := [
			'English: Hello World',
			'Japanese: こんにちは 世界 (Konnichiwa Sekai)',
			'Korean: 안녕하세요 세계 (Annyeonghaseyo Segye)',
			'Russian: Привет мир (Privet Mir)',
			'Emoji: 🚀 🎨 🍦 🦊 🔥 ✨',
		]

		// Calculate max label width for alignment
		mut max_label_w := f32(0)
		for sample in samples {
			parts := sample.split(':')
			if parts.len > 0 {
				label := parts[0] + ':'
				// Measure label width
				layout := app.ts.layout_text(label, vglyph.TextConfig{
					style: vglyph.TextStyle{
						font_name: 'Sans 24'
					}
				}) or { panic(err) }
				if layout.width > max_label_w {
					max_label_w = layout.width
				}
			}
		}

		tab_stop := int(max_label_w) + 20

		for sample in samples {
			parts := sample.split(':')
			label := parts[0] + ':'
			content := parts[1..].join(':').trim_space()

			section.layouts << app.ts.layout_text('${label}\t${content}', vglyph.TextConfig{
				style: vglyph.TextStyle{
					font_name: 'Sans 24'
					color:     text_color
				}
				block: vglyph.BlockStyle{
					tabs: [tab_stop]
				}
			}) or { panic(err) }
		}

		app.sections << section
	}

	// =========================================================================
	// Section 6: Advanced Features
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Advanced Features'
			description: 'Inline objects, Variable Fonts, and OpenType features.'
		}

		// Inline Objects
		// We can embed arbitrary content into the text flow. The layout engine
		// reserves space for it, and we draw it manually.

		// Define the object
		obj_id := 'v_logo_placeholder'

		mut runs := []vglyph.StyleRun{}
		runs << vglyph.StyleRun{
			text: 'Text flows around '
		}
		runs << vglyph.StyleRun{
			text:  'OBJECT' // Placeholder text (ignored for size, but useful for debug)
			style: vglyph.TextStyle{
				object: &vglyph.InlineObject{
					id:     obj_id
					width:  40
					height: 40
					offset: 5 // Adjust vertical alignment
				}
			}
		}
		runs << vglyph.StyleRun{
			text: ' seamlessly. You can render icons, images, or UI controls here.'
		}

		section.layouts << app.ts.layout_rich_text(vglyph.RichText{ runs: runs }, vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     text_color
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// OpenType Features & Variable Fonts
		// If a font supports it, we can tweak axes like Weight (wght) or Width (wdth),
		// and enable features like Ligatures (liga), Small Caps (smcp), etc.

		// Example: Enabling discretionary ligatures (dlig) and oldstyle figures (onum)
		// Note: This depends on the font having these features.
		section.layouts << app.ts.layout_text('OpenType: 1234567890 (Oldstyle Figures enabled if supported)',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Georgia 24'
				color:     text_color
				features:  &vglyph.FontFeatures{
					opentype_features: [
						vglyph.FontFeature{
							tag:   'onum'
							value: 1
						},
						vglyph.FontFeature{
							tag: 'dlig'
						},
					]
				}
			}
		}) or { panic(err) }

		// Small Caps (smcp)
		section.layouts << app.ts.layout_text('Small Caps: vglyph renders text beautifully.',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Hoefler Text 24'
				color:     text_color
				features:  &vglyph.FontFeatures{
					opentype_features: [
						vglyph.FontFeature{
							tag:   'smcp'
							value: 1
						},
					]
				}
			}
		}) or { panic(err) }

		section.layouts << app.ts.layout_text('Notice how Old Style figures vary in height (like lowercase text), while standard "lining" figures are uniform height (like ALL CAPS).',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 18'
				color:     gg.Color{180, 180, 180, 255}
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		app.sections << section
	}

	// =========================================================================
	// Section 6: Local Fonts
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Local Fonts'
			description: 'Loading custom font files from the application directory.'
		}

		// Description
		section.layouts << app.ts.layout_text('Custom fonts can be loaded at runtime. Here is "feathericon.ttf" loaded from assets:',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 18'
				color:     text_color
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// Icons
		mut icon_text := ''
		start_code := 0xF100
		for i in 0 .. 16 {
			icon_text += rune(start_code + i).str() + '  '
		}

		section.layouts << app.ts.layout_text(icon_text, vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'feathericon 32'
				color:     gg.Color{100, 255, 150, 255}
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		app.sections << section
	}

	// =========================================================================
	// Section 7: LCD Subpixel Antialiasing
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'LCD Subpixel Antialiasing'
			description: 'Exploits LCD subpixel structure for sharper text rendering, combined with Subpixel Positioning for smooth animations.'
		}

		section.layouts << app.ts.layout_text('Standard engines snap to integers. VGlyph supports subpixel precision, enabling buttery smooth slow-motion:',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 18'
				color:     text_color
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// Layouts for animation
		// 1. Smooth
		section.layouts << app.ts.layout_text('Smooth Subpixel Motion (Float Positions)',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     gg.Color{100, 255, 150, 255}
			}
		}) or { panic(err) }

		// 2. Integer
		section.layouts << app.ts.layout_text('Integer Snapped Motion (Jittery Test)',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 24'
				color:     gg.Color{255, 100, 100, 255}
			}
		}) or { panic(err) }

		app.sections << section
	}

	// =========================================================================
	// Section 8: Hit Testing & Interaction
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Hit Testing'
			description: 'Interactive text selection and cursor positioning.'
		}
		// We don't add layouts here; we render the interactive layout manually in frame()
		// to handle the dynamic state drawing (cursor/selection).
		app.sections << section

		// Initialize the interactive layout
		interactive_text := 'Try clicking and dragging here!\n' +
			'VGlyph supports precise hit testing for cursors and selection ranges.\n' +
			'Multiline text, variable widths, and mixed scripts are all handled correctly.'

		app.interactive_layout = app.ts.layout_text(interactive_text, vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 20'
				color:     text_color
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }
	}

	// =========================================================================
	// Section 9: Direct Text Rendering API
	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Direct Text Rendering'
			description: 'Simpler API for immediate mode text rendering (like standard gg.draw_text).'
		}

		// Description
		section.layouts << app.ts.layout_text('For many simple applications, you might not need the full power of layouts. VGlyph provides a direct API for rendering text strings with styles, similar to how you would use standard draw functions.',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 18'
				color:     text_color
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// Syntax Highlighted Code Example
		mut code_runs := []vglyph.StyleRun{}

		// Helper for syntax highlighting

		fn_color := gg.Color{120, 220, 255, 255} // Blue (Functions/Types)
		str_color := gg.Color{150, 255, 150, 255} // Green (Strings)
		num_color := gg.Color{180, 160, 255, 255} // Purple (Numbers/Consts)
		code_font := 'Mono 16'

		// Line 1: ts.draw_text(100, 100, 'Hello V!', vglyph.TextConfig{
		code_runs << vglyph.StyleRun{
			text:  'app.ts.'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  'draw_text'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     fn_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '('
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '100'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     num_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  ', '
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '100'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     num_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  ', '
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  "'Hello V!'"
			style: vglyph.TextStyle{
				font_name: code_font
				color:     str_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  ', vglyph.'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  'TextConfig'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     fn_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '{\n'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}

		// Line 2:     style: vglyph.TextStyle{
		code_runs << vglyph.StyleRun{
			text:  '    style: vglyph.'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  'TextStyle'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     fn_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '{\n'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}

		// Line 3:         font_name: 'Sans Bold Italic 24'
		code_runs << vglyph.StyleRun{
			text:  '        font_name: '
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  "'Sans Bold Italic 24'"
			style: vglyph.TextStyle{
				font_name: code_font
				color:     str_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '\n'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}

		// Line 4:         color: gg.Color{255, 200, 100, 255}
		code_runs << vglyph.StyleRun{
			text:  '        color: gg.'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  'Color'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     fn_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '{'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '255'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     num_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  ', '
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '200'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     num_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  ', '
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '100'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     num_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  ', '
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '255'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     num_color
			}
		}
		code_runs << vglyph.StyleRun{
			text:  '}\n'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}

		// Line 6:     }
		code_runs << vglyph.StyleRun{
			text:  '    }\n'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}
		// Line 7: })
		code_runs << vglyph.StyleRun{
			text:  '})'
			style: vglyph.TextStyle{
				font_name: code_font
				color:     text_color
			}
		}

		section.layouts << app.ts.layout_rich_text(vglyph.RichText{ runs: code_runs },
			vglyph.TextConfig{
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		// The Result
		section.layouts << app.ts.layout_text('Hello V! (Result)', vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold Italic 24'
				color:     gg.Color{255, 200, 100, 255}
			}
		}) or { panic(err) }

		app.sections << section
	}

	// =========================================================================
	// Section 10: Accessibility

	// =========================================================================
	{
		mut section := ShowcaseSection{
			title:       'Accessibility'
			description: 'Future support for screen readers and assistive technologies.'
		}

		section.layouts << app.ts.layout_text('Accessibility support is planned for VGlyph. The goal is to provide deep integration with platform APIs (such as NSAccessibility on macOS) to ensure that all rendered text is exposed to screen readers and navigation tools.',
			vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans 18'
				color:     text_color
			}
			block: vglyph.BlockStyle{
				width: content_width
				wrap:  .word
			}
		}) or { panic(err) }

		app.sections << section
	}

	// Recalculate total height
	app.last_layout_w = app.window_w
}

fn frame(mut app ShowcaseApp) {
	app.ctx.begin()

	// Handle Scrolling
	max_visible_h := f32(app.window_h)

	mut current_y := -app.scroll_y + 40.0 // Start with some padding

	for _, section in app.sections {
		// Draw Section Header
		header_cfg := vglyph.TextConfig{
			style: vglyph.TextStyle{
				font_name: 'Sans Bold 28'
				color:     gg.white
			}
		}
		if !section.title.is_blank() {
			app.ts.draw_text(50, current_y, section.title, header_cfg) or {}

			// Draw Line Divider
			app.ctx.draw_rect_filled(50, current_y + 40, f32(app.window_w - 100), 2, gg.Color{60, 60, 80, 255})

			current_y += 60
		}
		if section.title == 'LCD Subpixel Antialiasing' {
			// Animate subpixel_x
			app.subpixel_x += 0.05 // Very slow motion
			if app.subpixel_x > 50.0 {
				app.subpixel_x = 0.0
			}

			// Draw Description
			desc_layout := section.layouts[0]
			app.ts.draw_layout(desc_layout, 50, current_y)
			current_y += desc_layout.visual_height + 20

			// 1. Smooth
			layout_smooth := section.layouts[1]
			app.ts.draw_layout(layout_smooth, 50 + app.subpixel_x, current_y)
			current_y += layout_smooth.visual_height + 20

			// 2. Integer Snapped
			layout_snapped := section.layouts[2]
			snapped_x := math.round(50 + app.subpixel_x)
			app.ts.draw_layout(layout_snapped, f32(snapped_x), current_y)
			current_y += layout_snapped.visual_height + 20
		} else if section.title == 'Direct Text Rendering' {
			// standard Description
			desc_layout := section.layouts[0]
			app.ts.draw_layout(desc_layout, 50, current_y)
			current_y += desc_layout.visual_height + 40

			// Code Block with Background
			code_layout := section.layouts[1]

			// Draw nice dark code background
			padding := f32(15.0)
			bg_rect_x := f32(50) - padding
			bg_rect_y := current_y - padding
			bg_rect_w := f32(app.window_w - 100) + (padding * 2)
			bg_rect_h := code_layout.visual_height + (padding * 2)

			app.ctx.draw_rect_filled(bg_rect_x, bg_rect_y, bg_rect_w, bg_rect_h, gg.Color{30, 30, 35, 255})
			app.ctx.draw_rect_empty(bg_rect_x, bg_rect_y, bg_rect_w, bg_rect_h, gg.Color{60, 60, 70, 255})

			app.ts.draw_layout(code_layout, 50, current_y)
			current_y += code_layout.visual_height + 40 // Extra spacing after code block

			// Result
			res_layout := section.layouts[2]
			app.ts.draw_layout(res_layout, 50, current_y)
			current_y += res_layout.visual_height + 20
		} else if section.title == 'Hit Testing' {
			// Update the Y position for event handling sync
			app.interactive_y = current_y

			// Draw Selection Backgrounds
			if app.select_start != -1 && app.cursor_idx != app.select_start {
				start := if app.select_start < app.cursor_idx {
					app.select_start
				} else {
					app.cursor_idx
				}
				end := if app.select_start < app.cursor_idx {
					app.cursor_idx
				} else {
					app.select_start
				}

				rects := app.interactive_layout.get_selection_rects(start, end)
				for r in rects {
					app.ctx.draw_rect_filled(50 + r.x, current_y + r.y, r.width, r.height,
						gg.Color{50, 50, 200, 100})
				}
			}

			// Render the text
			app.ts.draw_layout(app.interactive_layout, 50, current_y)

			// Draw Cursor
			mut cx := f32(0)
			mut cy := f32(0)
			mut found := false

			for line in app.interactive_layout.lines {
				if app.cursor_idx >= line.start_index
					&& app.cursor_idx <= line.start_index + line.length {
					for cr in app.interactive_layout.char_rects {
						if cr.index == app.cursor_idx {
							cx = cr.rect.x
							cy = cr.rect.y
							found = true
							break
						}
					}
					if !found {
						// End of line fallback
						if app.cursor_idx == line.start_index + line.length {
							cx = line.rect.x + line.rect.width
							cy = line.rect.y
							found = true
						}
					}
				}
				if found {
					break
				}
			}

			if !found && app.interactive_layout.lines.len > 0 {
				last_line := app.interactive_layout.lines.last()
				if app.cursor_idx >= last_line.start_index + last_line.length {
					cx = last_line.rect.x + last_line.rect.width
					cy = last_line.rect.y
				} else if app.cursor_idx == 0 {
					first_line := app.interactive_layout.lines[0]
					cx = first_line.rect.x
					cy = first_line.rect.y
				}
			}

			if app.interactive_layout.lines.len > 0 {
				h := app.interactive_layout.lines[0].rect.height
				app.ctx.draw_rect_filled(50 + cx, current_y + cy, 2, h, gg.red)
			}

			current_y += app.interactive_layout.visual_height + 20
		} else {
			// Draw Layouts normally for all other sections
			for layout in section.layouts {
				// Culling optimization: only draw if visible
				layout_h := layout.visual_height
				if current_y + layout_h > -100 && current_y < max_visible_h {
					app.ts.draw_layout(layout, 50, current_y)
					app.draw_inline_objects(layout, 50, current_y)
				}
				current_y += layout_h + 20 // Spacing between items
			}
		}

		current_y += 60 // Spacing between sections
	}

	app.max_scroll = f32(math.max(0.0, current_y + app.scroll_y - max_visible_h + 100))

	// Scroll Bar
	if app.max_scroll > 0 {
		scroll_ratio := app.scroll_y / app.max_scroll
		thumb_h := f32(app.window_h) * (f32(app.window_h) / (app.max_scroll + f32(app.window_h)))
		thumb_y := scroll_ratio * (f32(app.window_h) - thumb_h)
		app.ctx.draw_rect_filled(f32(app.window_w) - 10, thumb_y + app.scroll_y * 0 // fixed position overlay
		 , 6, thumb_h, gg.Color{100, 100, 100, 150})
	}

	// Accessibility / Atlas Commit
	app.ts.commit()

	app.ctx.end()
}

fn (mut app ShowcaseApp) draw_inline_objects(layout vglyph.Layout, x f32, y f32) {
	for item in layout.items {
		if item.is_object {
			// Simple visualizer: V Logo placeholder (Blue V)
			if item.object_id == 'v_logo_placeholder' {
				draw_x := x + f32(item.x)
				// Item.y is the baseline offset from the layout top.
				// To draw the object at the correct vertical position relative to the text:
				// The space reserved is 'above' the baseline by 'ascent'.
				draw_y := y + f32(item.y) - f32(item.ascent)

				w := f32(item.width)
				h := f32(item.ascent + item.descent)

				// Draw a nice badge
				app.ctx.draw_rect_filled(draw_x, draw_y, w, h, gg.Color{80, 120, 180, 255})
				app.ctx.draw_rect_empty(draw_x, draw_y, w, h, gg.white)

				// Draw "V" - use vglyph for consistency
				app.ts.draw_text(draw_x + 10, draw_y + 5, 'V', vglyph.TextConfig{
					style: vglyph.TextStyle{
						font_name: 'Sans Bold 24'
						color:     gg.white
					}
				}) or {}
			}
		}
	}
}

fn on_event(e &gg.Event, mut app ShowcaseApp) {
	match e.typ {
		.mouse_scroll {
			app.scroll_y -= e.scroll_y * 20.0
			if app.scroll_y < 0 {
				app.scroll_y = 0
			}
			if app.scroll_y > app.max_scroll {
				app.scroll_y = app.max_scroll
			}
		}
		.key_down {
			step := f32(40.0)
			page := f32(app.window_h) * 0.9

			match e.key_code {
				.up { app.scroll_y -= step }
				.down { app.scroll_y += step }
				.page_up { app.scroll_y -= page }
				.page_down { app.scroll_y += page }
				.home { app.scroll_y = 0 }
				.end { app.scroll_y = app.max_scroll }
				else {}
			}

			// Clamp
			if app.scroll_y < 0 {
				app.scroll_y = 0
			}
			if app.scroll_y > app.max_scroll {
				app.scroll_y = app.max_scroll
			}
		}
		.mouse_down {
			local_x := e.mouse_x - 50.0
			local_y := e.mouse_y - app.interactive_y

			if local_y >= -50 && local_y <= app.interactive_layout.visual_height + 50 {
				idx := app.interactive_layout.get_closest_offset(f32(local_x), f32(local_y))
				app.cursor_idx = idx
				app.select_start = idx
				app.is_dragging = true
			}
		}
		.mouse_up {
			app.is_dragging = false
		}
		.mouse_move {
			if app.is_dragging {
				local_x := e.mouse_x - 50.0
				local_y := e.mouse_y - app.interactive_y
				app.cursor_idx = app.interactive_layout.get_closest_offset(f32(local_x),
					f32(local_y))
			}
		}
		.resized, .restored, .resumed {
			app.window_w = e.window_width
			app.window_h = e.window_height
			if app.window_w != app.last_layout_w {
				app.create_content() // Responsive re-layout
			}
		}
		else {}
	}
}
