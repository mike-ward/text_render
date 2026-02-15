module vglyph

import gg
import math

pub struct Layout {
pub mut:
	cloned_object_ids  []string // Cloned inline object IDs for Pango lifetime
	items              []Item
	glyphs             []Glyph
	char_rects         []CharRect
	char_rect_by_index map[int]int // char byte index -> char_rects array index
	lines              []Line
	log_attrs          []LogAttr   // Cursor/word boundary info, indexed by byte position
	log_attr_by_index  map[int]int // byte index -> log_attrs array index
	width              f32         // Logical Width
	height             f32         // Logical Height
	visual_width       f32         // Ink Width
	visual_height      f32         // Ink Height
}

// CursorPosition represents the geometry for rendering a cursor at a byte index.
pub struct CursorPosition {
pub:
	x      f32
	y      f32
	height f32
}

// LogAttr holds character classification for cursor/word boundaries.
// Extracted from Pango's PangoLogAttr during layout build.
pub struct LogAttr {
pub:
	is_cursor_position bool
	is_word_start      bool
	is_word_end        bool
	is_line_break      bool
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
	run_text  string
	ft_face   &C.FT_FaceRec
	object_id string

	width   f64
	x       f64 // Run position relative to layout (x)
	y       f64 // Run position relative to layout (baseline y)
	ascent  f64
	descent f64

	glyph_start int
	glyph_count int
	start_index int
	length      int

	// Decorations
	underline_offset        f64
	underline_thickness     f64
	strikethrough_offset    f64
	strikethrough_thickness f64

	color    gg.Color
	bg_color gg.Color

	// Stroke
	stroke_width f32
	stroke_color gg.Color

	// Flags (grouped to pack into bytes if possible by compiler, or at least minimize gaps)
	has_underline      bool
	has_strikethrough  bool
	has_bg_color       bool
	has_stroke         bool
	use_original_color bool // If true, do not tint the item color (e.g. for Emojis)
	is_object          bool
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

// TextOrientation defines the flow and orientation of the text.
pub enum TextOrientation {
	horizontal
	vertical // Vertical flow, upright characters (for CJK)
}

// GradientDirection controls the axis of color interpolation.
pub enum GradientDirection {
	horizontal // Left to right
	vertical   // Top to bottom
}

// GradientStop defines a color at a normalized position (0.0–1.0).
pub struct GradientStop {
pub:
	color    gg.Color
	position f32
}

// GradientConfig defines an N-stop gradient for text rendering.
// Stops must be sorted by position in ascending order.
pub struct GradientConfig {
pub:
	stops     []GradientStop
	direction GradientDirection = .horizontal
}

// Typeface specifies bold/italic style programmatically without string manipulation.
pub enum Typeface {
	regular     // Default - preserves font_name style
	bold        // Override to bold
	italic      // Override to italic
	bold_italic // Override to bold+italic
}

// TextConfig holds configuration for text layout and rendering.
pub struct TextConfig {
pub mut:
	style          TextStyle
	block          BlockStyle
	use_markup     bool
	no_hit_testing bool
	orientation    TextOrientation = .horizontal
	gradient       &GradientConfig = unsafe { nil }
}

// AffineTransform encodes a 2D affine transform matrix:
// [ xx  xy  x0 ]
// [ yx  yy  y0 ]
// [  0   0   1 ]
pub struct AffineTransform {
pub:
	xx f32 = 1.0
	xy f32
	yx f32
	yy f32 = 1.0
	x0 f32
	y0 f32
}

// apply maps a point through the affine transform.
pub fn (t AffineTransform) apply(x f32, y f32) (f32, f32) {
	return t.xx * x + t.xy * y + t.x0, t.yx * x + t.yy * y + t.y0
}

// affine_identity returns an identity transform.
pub fn affine_identity() AffineTransform {
	return AffineTransform{}
}

// affine_rotation returns a rotation transform in radians around origin.
pub fn affine_rotation(angle f32) AffineTransform {
	c := f32(math.cos(angle))
	s := f32(math.sin(angle))
	return AffineTransform{
		xx: c
		xy: -s
		yx: s
		yy: c
	}
}

// affine_translation returns a translation transform.
pub fn affine_translation(dx f32, dy f32) AffineTransform {
	return AffineTransform{
		x0: dx
		y0: dy
	}
}

// affine_skew returns a shear transform with direct skew factors.
pub fn affine_skew(skew_x f32, skew_y f32) AffineTransform {
	return AffineTransform{
		xy: skew_x
		yx: skew_y
	}
}

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

// BlockStyle defines the layout properties of a block of text.
pub struct BlockStyle {
pub mut:
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
	// typeface overrides the weight/style in font_name when not .regular.
	typeface Typeface = .regular
	// size overrides the size specified in font_name.
	// It is specified in points.
	size     f32
	color    gg.Color = gg.Color{0, 0, 0, 0}
	bg_color gg.Color = gg.Color{0, 0, 0, 0}

	// Decorations
	underline      bool
	strikethrough  bool
	letter_spacing f32 // Extra spacing between characters (points)

	// Stroke (outline)
	stroke_width f32 // Width in points (0 = no stroke)
	stroke_color gg.Color = gg.Color{0, 0, 0, 0}

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

// TextMetrics contains metrics for a specific font configuration.
// All values are in pixels.
pub struct TextMetrics {
pub:
	// ascender is the distance from the baseline to the top of the font's bounding box.
	ascender f32
	// descender is the distance from the baseline to the bottom of the font's bounding box.
	descender f32
	// height is the total height of the font (ascender + descender).
	height f32
	// line_gap is the recommended partial spacing between lines.
	line_gap f32
}

// glyph_positions returns the absolute position, advance,
// and index of every glyph in the layout. Flattens the
// item/glyph hierarchy so callers can walk advances to
// place glyphs on a path.
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

// destroy frees resources owned by the Layout.
// Call when Layout is no longer needed to prevent memory leaks.
pub fn (mut l Layout) destroy() {
	for s in l.cloned_object_ids {
		if s.len > 0 {
			unsafe { free(s.str) }
		}
	}
	l.cloned_object_ids = []
}
