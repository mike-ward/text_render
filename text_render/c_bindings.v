module text_render

#flag -I@VMODROOT/text_render
#flag -I@VEXEROOT/thirdparty/freetype/include
#pkgconfig freetype2
#pkgconfig harfbuzz
#pkgconfig fribidi

// FreeType
#include "ft_compat.h"

@[typedef]
pub struct C.FT_LibraryRec {
}

@[typedef]
pub struct C.FT_SizeRec {
pub:
	face    &C.FT_FaceRec
	generic voidptr
	metrics C.FT_Size_Metrics
}

@[typedef]
pub struct C.FT_FaceRec {
pub mut:
	num_faces           i64
	face_index          i64
	face_flags          i64
	style_flags         i64
	num_glyphs          i64
	family_name         &char
	style_name          &char
	num_fixed_sizes     i32
	available_sizes     voidptr
	num_charmaps        i32
	charmaps            voidptr
	generic             voidptr
	bbox                voidptr
	units_per_EM        u16
	ascender            i16
	descender           i16
	height              i16
	max_advance_width   i16
	max_advance_height  i16
	underline_position  i16
	underline_thickness i16
	glyph               &C.FT_GlyphSlotRec
	size                &C.FT_SizeRec
	charmap             C.FT_CharMap
}

@[typedef]
pub struct C.FT_GlyphSlotRec {
pub:
	bitmap      C.FT_Bitmap
	bitmap_left i32
	bitmap_top  i32
	advance     C.FT_Vector
	metrics     C.FT_Glyph_Metrics
}

@[typedef]
pub struct C.FT_Bitmap {
pub:
	rows         u32
	width        u32
	pitch        int
	buffer       &u8
	num_grays    u16
	pixel_mode   u8
	palette_mode u8
	palette      voidptr
}

@[typedef]
pub struct C.FT_Vector {
pub:
	x i64
	y i64
}

@[typedef]
pub struct C.FT_Glyph_Metrics {
pub:
	width        i64
	height       i64
	horiBearingX i64
	horiBearingY i64
	horiAdvance  i64
	vertBearingX i64
	vertBearingY i64
	vertAdvance  i64
}

@[typedef]
pub struct C.FT_Size_Metrics {
pub:
	x_ppem      u16
	y_ppem      u16
	x_scale     i64
	y_scale     i64
	ascender    i64
	descender   i64
	height      i64
	max_advance i64
}

@[typedef]
pub struct C.FT_CharMap {
}

fn C.FT_Init_FreeType(&&C.FT_LibraryRec) int
fn C.FT_Done_FreeType(&C.FT_LibraryRec) int
fn C.FT_New_Face(&C.FT_LibraryRec, &char, i64, &&C.FT_FaceRec) int
fn C.FT_Done_Face(&C.FT_FaceRec) int
fn C.FT_Set_Pixel_Sizes(&C.FT_FaceRec, u32, u32) int
fn C.FT_Load_Char(&C.FT_FaceRec, u32, i32) int
fn C.FT_Load_Glyph(&C.FT_FaceRec, u32, i32) int
fn C.FT_Get_Char_Index(&C.FT_FaceRec, u32) u32
fn C.FT_Render_Glyph(&C.FT_GlyphSlotRec, i32) int

pub const ft_render_mode_normal = 0

// Pango & GObject & GLib
#pkgconfig pango
#pkgconfig pangoft2
#pkgconfig gobject-2.0
#pkgconfig glib-2.0

#include <pango/pango.h>
#include <pango/pangoft2.h>
#include <glib-object.h>
#include <glib.h>

// GObject / GLib Types
@[typedef]
pub struct C.GObject {}

pub type GCallback = fn ()

fn C.g_object_unref(obj voidptr)
fn C.g_object_ref(obj voidptr) voidptr

// Pango Types
@[typedef]
pub struct C.PangoContext {}

@[typedef]
pub struct C.PangoLayout {}

@[typedef]
pub struct C.PangoFontDescription {}

@[typedef]
pub struct C.PangoFontMap {}

@[typedef]
pub struct C.PangoFont {}

@[typedef]
pub struct C.PangoLayoutIter {}

@[typedef]
pub struct C.PangoAttrList {}

@[typedef]
pub struct C.PangoAttribute {}

// Pango Structs with accessible fields

@[typedef]
pub struct C.PangoRectangle {
pub:
	x      int
	y      int
	width  int
	height int
}

@[typedef]
pub struct C.PangoGlyphGeometry {
pub:
	width    i32
	x_offset i32
	y_offset i32
}

@[typedef]
pub struct C.PangoGlyphVisAttr {
pub:
	is_cluster_start u32 // bitfield in C, simplified here (might need care if accessing)
}

@[typedef]
pub struct C.PangoGlyphInfo {
pub:
	glyph    u32
	geometry C.PangoGlyphGeometry
	attr     C.PangoGlyphVisAttr
}

@[typedef]
pub struct C.PangoGlyphString {
pub:
	num_glyphs   int
	glyphs       &C.PangoGlyphInfo
	log_clusters &int
}

@[typedef]
pub struct C.PangoAnalysis {
pub:
	shape_engine voidptr
	lang_engine  voidptr
	font         &C.PangoFont
	level        u8
	gravity      u8
	flags        u8
	script       u8
	language     voidptr
	extra_attrs  voidptr
}

@[typedef]
pub struct C.PangoItem {
pub:
	offset    int
	length    int
	num_chars int
	analysis  C.PangoAnalysis
}

@[typedef]
pub struct C.PangoGlyphItem {
pub:
	item   &C.PangoItem
	glyphs &C.PangoGlyphString
}

// Global Pango Constants
pub const pango_scale = 1024

// Functions

// Pango FT2
fn C.pango_ft2_font_map_new() &C.PangoFontMap
fn C.pango_font_map_create_context(&C.PangoFontMap) &C.PangoContext
fn C.pango_ft2_font_get_face(&C.PangoFont) &C.FT_FaceRec

// Pango Context / Layout
fn C.pango_layout_new(&C.PangoContext) &C.PangoLayout
fn C.pango_layout_set_text(&C.PangoLayout, &char, int)
fn C.pango_layout_set_font_description(&C.PangoLayout, &C.PangoFontDescription)
fn C.pango_layout_get_iter(&C.PangoLayout) &C.PangoLayoutIter
fn C.pango_layout_get_extents(&C.PangoLayout, &C.PangoRectangle, &C.PangoRectangle)

// Pango Iter
fn C.pango_layout_iter_free(&C.PangoLayoutIter)
fn C.pango_layout_iter_next_run(&C.PangoLayoutIter) bool
fn C.pango_layout_iter_get_run_readonly(&C.PangoLayoutIter) &C.PangoGlyphItem

// Pango Font Description
fn C.pango_font_description_new() &C.PangoFontDescription
fn C.pango_font_description_from_string(&char) &C.PangoFontDescription
fn C.pango_font_description_free(&C.PangoFontDescription)
fn C.pango_font_description_set_family(&C.PangoFontDescription, &char)
fn C.pango_font_description_set_size(&C.PangoFontDescription, int) // size in Pango units
fn C.pango_font_description_set_absolute_size(&C.PangoFontDescription, f64)

// Pango Enums
pub enum PangoAlignment {
	pango_align_left   = 0
	pango_align_center = 1
	pango_align_right  = 2
}

pub enum PangoWrapMode {
	pango_wrap_word      = 0
	pango_wrap_char      = 1
	pango_wrap_word_char = 2
}

pub enum PangoEllipsizeMode {
	pango_ellipsize_none   = 0
	pango_ellipsize_start  = 1
	pango_ellipsize_middle = 2
	pango_ellipsize_end    = 3
}

// Pango Layout Configuration
fn C.pango_layout_set_width(&C.PangoLayout, int)
fn C.pango_layout_set_height(&C.PangoLayout, int)
fn C.pango_layout_set_alignment(&C.PangoLayout, PangoAlignment)
fn C.pango_layout_set_wrap(&C.PangoLayout, PangoWrapMode)
fn C.pango_layout_set_ellipsize(&C.PangoLayout, PangoEllipsizeMode)
fn C.pango_layout_get_width(&C.PangoLayout) int
fn C.pango_layout_get_height(&C.PangoLayout) int

// Pango Iterator Extended
fn C.pango_layout_iter_get_run_extents(&C.PangoLayoutIter, &C.PangoRectangle, &C.PangoRectangle)
fn C.pango_layout_iter_get_baseline(&C.PangoLayoutIter) int
