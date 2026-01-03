module text_render

#flag -I@VMODROOT/text_render
#flag -I@VEXEROOT/thirdparty/freetype/include
#pkgconfig freetype2
#pkgconfig harfbuzz
#pkgconfig fribidi
#pkgconfig fontconfig

// FreeType
#include "ft_compat.h"

@[typedef]
pub struct C.FcConfig {
}

pub type C.FcBool = int

pub const ft_face_flag_color = (1 << 14)

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
fn C.FT_Get_First_Char(&C.FT_FaceRec, &u32) u32
fn C.FT_Get_Next_Char(&C.FT_FaceRec, u32, &u32) u32
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

// Pango Font Description Enums
@[typedef]
pub enum PangoStyle {
	pango_style_normal  = 0
	pango_style_oblique = 1
	pango_style_italic  = 2
}

pub enum PangoVariant {
	pango_variant_normal          = 0
	pango_variant_small_caps      = 1
	pango_variant_all_small_caps  = 2
	pango_variant_petite_caps     = 3
	pango_variant_all_petite_caps = 4
	pango_variant_unicase         = 5
	pango_variant_title_caps      = 6
}

pub enum PangoWeight {
	pango_weight_thin       = 100
	pango_weight_ultralight = 200
	pango_weight_light      = 300
	pango_weight_semilight  = 350
	pango_weight_book       = 380
	pango_weight_normal     = 400
	pango_weight_medium     = 500
	pango_weight_semibold   = 600
	pango_weight_bold       = 700
	pango_weight_ultrabold  = 800
	pango_weight_heavy      = 900
	pango_weight_ultraheavy = 1000
}

pub enum PangoStretch {
	pango_stretch_ultra_condensed = 0
	pango_stretch_extra_condensed = 1
	pango_stretch_condensed       = 2
	pango_stretch_semi_condensed  = 3
	pango_stretch_normal          = 4
	pango_stretch_semi_expanded   = 5
	pango_stretch_expanded        = 6
	pango_stretch_extra_expanded  = 7
	pango_stretch_ultra_expanded  = 8
}

pub enum PangoGravity {
	pango_gravity_south = 0
	pango_gravity_east  = 1
	pango_gravity_north = 2
	pango_gravity_west  = 3
	pango_gravity_auto  = 4
}

pub enum PangoFontMask {
	pango_font_mask_family     = 1   // (1 << 0)
	pango_font_mask_style      = 2   // (1 << 1)
	pango_font_mask_variant    = 4   // (1 << 2)
	pango_font_mask_weight     = 8   // (1 << 3)
	pango_font_mask_stretch    = 16  // (1 << 4)
	pango_font_mask_size       = 32  // (1 << 5)
	pango_font_mask_gravity    = 64  // (1 << 6)
	pango_font_mask_variations = 128 // (1 << 7)
}

@[typedef]
pub struct C.PangoFontDescription {
pub mut:
	family_name            &char
	style                  PangoStyle
	variant                PangoVariant
	weight                 PangoWeight
	stretch                PangoStretch
	gravity                PangoGravity
	variations             &char
	mask                   u16 // PangoFontMask
	static_and_is_abs_size u32 // Bitfields: static_family (1), static_variations (1), size_is_absolute (1)
	size                   int
}

@[typedef]
pub struct C.PangoFontMap {}

@[typedef]
pub struct C.PangoFont {}

@[typedef]
pub struct C.PangoLayoutIter {}

@[typedef]
pub struct C.PangoAttrList {}

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

@[typedef]
pub struct C.PangoLanguage {}

// PangoLayoutRun is a typedef for PangoGlyphItem in C.
// We define it here so V knows about C.PangoLayoutRun
@[typedef]
pub struct C.PangoLayoutRun {
pub:
	item   &C.PangoItem
	glyphs &C.PangoGlyphString
}

// GLib Lists
@[typedef]
pub struct C.GSList {
pub:
	data voidptr
	next &C.GSList
}

// Pango Attributes
pub enum PangoAttrType {
	pango_attr_invalid       = 0
	pango_attr_language      = 1
	pango_attr_family        = 2
	pango_attr_style         = 3
	pango_attr_weight        = 4
	pango_attr_variant       = 5
	pango_attr_stretch       = 6
	pango_attr_size          = 7
	pango_attr_font_desc     = 8
	pango_attr_foreground    = 9
	pango_attr_background    = 10
	pango_attr_underline     = 11
	pango_attr_strikethrough = 12
}

pub enum PangoUnderline {
	pango_underline_none   = 0
	pango_underline_single = 1
	pango_underline_double = 2
	pango_underline_low    = 3
	pango_underline_error  = 4
}

@[typedef]
pub struct C.PangoAttribute {
pub mut:
	klass       &C.PangoAttrClass
	start_index u32
	end_index   u32
}

@[typedef]
pub struct C.PangoAttrClass {
pub:
	type PangoAttrType
}

@[typedef]
pub struct C.PangoColor {
pub:
	red   u16
	green u16
	blue  u16
}

@[typedef]
pub struct C.PangoAttrColor {
pub:
	attr  C.PangoAttribute
	color C.PangoColor
}

@[typedef]
pub struct C.PangoAttrInt {
pub:
	attr  C.PangoAttribute
	value int
}

@[typedef]
pub struct C.PangoFontMetrics {}

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
fn C.pango_layout_set_markup(&C.PangoLayout, &char, int)
fn C.pango_layout_set_font_description(&C.PangoLayout, &C.PangoFontDescription)
fn C.pango_layout_get_iter(&C.PangoLayout) &C.PangoLayoutIter
fn C.pango_layout_get_font_description(&C.PangoLayout) &C.PangoFontDescription
fn C.pango_layout_get_extents(&C.PangoLayout, &C.PangoRectangle, &C.PangoRectangle)
fn C.pango_layout_index_to_pos(&C.PangoLayout, int, &C.PangoRectangle)

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
fn C.pango_font_description_get_size(&C.PangoFontDescription) int
fn C.pango_font_description_get_size_is_absolute(&C.PangoFontDescription) bool
fn C.pango_layout_get_context(&C.PangoLayout) &C.PangoContext
fn C.pango_context_get_metrics(&C.PangoContext, &C.PangoFontDescription, &C.PangoLanguage) &C.PangoFontMetrics
fn C.pango_font_metrics_get_approximate_char_width(&C.PangoFontMetrics) int

// Pango Font Metrics
fn C.pango_font_get_metrics(&C.PangoFont, voidptr) &C.PangoFontMetrics
fn C.pango_font_metrics_get_underline_position(&C.PangoFontMetrics) int
fn C.pango_font_metrics_get_underline_thickness(&C.PangoFontMetrics) int
fn C.pango_font_metrics_get_strikethrough_position(&C.PangoFontMetrics) int
fn C.pango_font_metrics_get_strikethrough_thickness(&C.PangoFontMetrics) int
fn C.pango_font_metrics_get_ascent(&C.PangoFontMetrics) int
fn C.pango_font_metrics_unref(&C.PangoFontMetrics)

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

// Pango Attributes Management
fn C.pango_attr_list_new() &C.PangoAttrList
fn C.pango_attr_list_unref(&C.PangoAttrList)
fn C.pango_attr_list_insert(&C.PangoAttrList, &C.PangoAttribute)
fn C.pango_layout_set_attributes(&C.PangoLayout, &C.PangoAttrList)
fn C.pango_layout_get_attributes(&C.PangoLayout) &C.PangoAttrList

// Pango Attribute Constructors
fn C.pango_attr_list_copy(&C.PangoAttrList) &C.PangoAttrList
fn C.pango_attr_foreground_new(u16, u16, u16) &C.PangoAttribute
fn C.pango_attr_background_new(u16, u16, u16) &C.PangoAttribute
fn C.pango_attr_underline_new(PangoUnderline) &C.PangoAttribute
fn C.pango_attr_strikethrough_new(bool) &C.PangoAttribute

// FontConfig
fn C.FcInitLoadConfigAndFonts() &C.FcConfig
fn C.FcConfigGetCurrent() &C.FcConfig
fn C.FcConfigAppFontAddFile(config &C.FcConfig, file &char) C.FcBool
