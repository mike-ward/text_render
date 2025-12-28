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
	size                C.FT_Size
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
pub struct C.FT_Size {
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

// HarfBuzz
#include <hb.h>
#include <hb-ft.h>

@[typedef]
pub struct C.hb_buffer_t {
}

@[typedef]
pub struct C.hb_font_t {
}

@[typedef]
pub struct C.hb_blob_t {
}

@[typedef]
pub struct C.hb_face_t {
}

@[typedef]
pub struct C.hb_glyph_info_t {
pub:
	codepoint u32
	mask      u32
	cluster   u32
}

@[typedef]
pub struct C.hb_glyph_position_t {
pub:
	x_advance i32
	y_advance i32
	x_offset  i32
	y_offset  i32
}

@[typedef]
pub struct C.hb_feature_t {
	tag   u32
	value u32
	start u32
	end   u32
}

fn C.hb_buffer_create() &C.hb_buffer_t
fn C.hb_buffer_destroy(&C.hb_buffer_t)
fn C.hb_buffer_add_utf8(&C.hb_buffer_t, &char, int, u32, int)
fn C.hb_buffer_guess_segment_properties(&C.hb_buffer_t)
fn C.hb_ft_font_create_referenced(&C.FT_FaceRec) &C.hb_font_t
fn C.hb_font_destroy(&C.hb_font_t)
fn C.hb_shape(&C.hb_font_t, &C.hb_buffer_t, &C.hb_feature_t, u32)
fn C.hb_buffer_get_glyph_infos(&C.hb_buffer_t, &u32) &C.hb_glyph_info_t
fn C.hb_buffer_get_glyph_positions(&C.hb_buffer_t, &u32) &C.hb_glyph_position_t
fn C.hb_buffer_set_direction(&C.hb_buffer_t, int)
fn C.hb_buffer_set_script(&C.hb_buffer_t, int)
fn C.hb_buffer_set_language(&C.hb_buffer_t, voidptr)
fn C.hb_language_from_string(&char, int) voidptr
fn C.hb_script_from_string(&char, int) int
fn C.hb_font_set_scale(&C.hb_font_t, int, int)

// Fribidi
#include <fribidi.h>

// Fribidi constants and types
pub const fribidi_type_ltr = 0 // FRIBIDI_TYPE_LTR
pub const fribidi_type_rtl = 1 // FRIBIDI_TYPE_RTL
pub const fribidi_type_on = 0 // FRIBIDI_TYPE_ON

fn C.fribidi_log2vis(&u32, int, &u32, &u32, &int, &int, &i8) int
