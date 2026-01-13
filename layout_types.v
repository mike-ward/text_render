module vglyph

import gg

pub struct Layout {
pub mut:
	items         []Item
	char_rects    []CharRect
	lines         []Line
	width         f32 // Logical Width
	height        f32 // Logical Height
	visual_width  f32 // Ink Width
	visual_height f32 // Ink Height
}

pub struct CharRect {
pub:
	rect  gg.Rect
	index int // Byte index
}

pub struct Line {
pub:
	start_index        int
	length             int
	rect               gg.Rect // Logical bounding box of the line (relative to layout)
	is_paragraph_start bool
}

pub struct Item {
pub:
	run_text string @[if debug] // Useful for debugging or if we need original text
	ft_face  &C.FT_FaceRec
	glyphs   []Glyph
	width    f64
	x        f64 // Run position relative to layout (x)
	y        f64 // Run position relative to layout (baseline y)

	start_index int
	length      int

	color gg.Color = gg.black

	// Text Decoration
	has_underline           bool
	has_strikethrough       bool
	underline_offset        f64
	underline_thickness     f64
	strikethrough_offset    f64
	strikethrough_thickness f64

	// Background
	has_bg_color       bool
	bg_color           gg.Color
	ascent             f64
	descent            f64
	use_original_color bool // If true, do not tint the item color (e.g. for Emojis)
}

pub struct Glyph {
pub:
	index     u32
	x_offset  f64
	y_offset  f64
	x_advance f64
	y_advance f64
	codepoint u32 // Optional, might be 0 if not easily tracking back
}

// Alignment specifies the horizontal alignment of the text within its layout box.
pub enum Alignment {
	left   // left aligns the text to the left.
	center // center aligns the text to the center.
	right  // right aligns the text to the right.
}

// WrapMode defines how text should wrap when it exceeds the maximum width.
pub enum WrapMode {
	word      // wrap at word boundaries (e.g. spaces).
	char      // wrap at character boundaries.
	word_char // wrap at word, fallback to char if word too long.
}

// TextConfig holds configuration for text layout and rendering.
pub struct TextConfig {
pub:
	// font_name is a Pango font description string properly formatted as:
	// "[FAMILY-LIST] [STYLE-OPTIONS] [SIZE] [VARIATIONS] [FEATURES]"
	//
	// FAMILY-LIST: Comma-separated list (e.g. "Sans, Helvetica, monospace").
	//
	// STYLE-OPTIONS: Space-separated words from:
	//   Styles:   Normal, Roman, Oblique, Italic
	//   Variants: Small-Caps, All-Small-Caps, Unicase, Title-Caps, etc.
	//   Weights:  Thin, Light, Regular, Medium, Bold, Heavy, Black, etc.
	//   Stretch:  Ultra-Condensed, Condensed, Expanded, Ultra-Expanded, etc.
	//   Gravity:  South, North, East, West, Rotated-Left, Rotated-Right
	//
	// SIZE: Points (decimal e.g. "12") or pixels (e.g. "20px").
	//
	// VARIATIONS: Comma-separated OpenType axis "@axis=value"
	//
	// FEATURES: Comma-separated OpenType features "@feature=value"
	//
	// Example: "Sans Italic Light 15"
	// Ref: https://docs.gtk.org/Pango/type_func.FontDescription.from_string.html
	font_name string
	width     int       = -1    // width is the wrapping width in pixels. Set to -1 or 0 for no wrapping.
	align     Alignment = .left // align controls the horizontal alignment of the text (left, center, right).
	wrap      WrapMode  = .word // wrap controls how text lines are broken (word, char, etc.).
	// use_markup enables Pango markup syntax.
	//
	// Supported tags:
	//   <b>, <i>, <s>, <u>, <tt>, <sub>, <sup>, <small>, <big>
	//
	// The <span> tag supports the following attributes:
	//   font_family (or face), font_desc, size (e.g. "small", "xx-large", "100"), style,
	//   weight, variant, stretch, foreground (or color/fgcolor), background (or bgcolor),
	//   alpha, background_alpha, underline ("none", "single", "double", "low"), underline_color,
	//   rise (vertical offset), strikethrough ("true"/"false"), strikethrough_color,
	//   fallback ("true"/"false"), lang, letter_spacing, gravity, gravity_hint.
	//
	// Example: <span foreground="blue" size="x-large">Blue Text</span>
	//
	// Also see: https://developer.gnome.org/pango/stable/PangoMarkupFormat.html
	use_markup bool

	// Style Overrides (applied to the whole text if checked)
	color         gg.Color = gg.black
	bg_color      gg.Color = gg.Color{0, 0, 0, 0}
	underline     bool
	strikethrough bool

	// Advanced Typography
	tabs              []int          // Tab stops in pixels
	opentype_features map[string]int // e.g. {"smcp": 1, "tnum": 1}
	variation_axes    map[string]f32 // e.g. {"wght": 700, "wdth": 100}
}

// RichTextStyle represents the visual style of a run of text.
// It is a subset of TextConfig, focusing on character-level attributes.
pub struct RichTextStyle {
pub:
	font_name string
	color     gg.Color = gg.black
	bg_color  gg.Color = gg.Color{0, 0, 0, 0}

	// Decorations
	underline     bool
	strikethrough bool

	// Advanced Typography
	opentype_features map[string]int
	variation_axes    map[string]f32
}

pub struct StyleRun {
pub:
	text  string
	style RichTextStyle
}

pub struct RichText {
pub:
	runs []StyleRun
}
