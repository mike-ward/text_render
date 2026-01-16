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
	run_text string
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

	// Inline Objects
	is_object bool
	object_id string
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

pub struct InlineObject {
pub:
	id     string // User identifier for the object
	width  f32    // Point size
	height f32
	offset f32 // Baseline offset
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
	style          TextStyle
	block          BlockStyle
	use_markup     bool
	no_hit_testing bool
}

// BlockStyle defines the layout properties of a block of text.
pub struct BlockStyle {
pub:
	align Alignment = .left
	wrap  WrapMode  = .word
	width f32       = -1.0
	// indent determines the indentation of the first line.
	// Negative values create a hanging indent (lines 2+ are indented).
	indent f32
	tabs   []int
}

// TextStyle represents the visual style of a run of text.
// It contains font, color, and decoration attributes.
pub struct TextStyle {
pub:
	// font_name is a Pango font description string properly formatted as:
	// "[FAMILY-LIST] [STYLE-OPTIONS] [SIZE] [VARIATIONS] [FEATURES]"
	// Example: "Sans Italic Light 15"
	font_name string
	// size overrides the size specified in font_name.
	// It is specified in points.
	size     f32
	color    gg.Color = gg.black
	bg_color gg.Color = gg.Color{0, 0, 0, 0}

	// Decorations
	underline     bool
	strikethrough bool

	// Advanced Typography
	features &FontFeatures = unsafe { nil }
	object   &InlineObject = unsafe { nil }
}

pub struct FontFeature {
pub:
	tag   string
	value int
}

pub struct FontAxis {
pub:
	tag   string
	value f32
}

pub struct FontFeatures {
pub:
	opentype_features []FontFeature
	variation_axes    []FontAxis
}

pub struct StyleRun {
pub:
	text  string
	style TextStyle
}

pub struct RichText {
pub:
	runs []StyleRun
}
