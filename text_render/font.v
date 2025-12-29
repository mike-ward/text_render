module text_render

pub struct Font {
pub:
	name  string
	path  string
	size  int
	scale f32 = 1
mut:
	ft_face &C.FT_FaceRec
	hb_font &C.hb_font_t
}

pub fn (mut ctx Context) load_font(name string, path string, size int) !&Font {
	if name in ctx.fonts {
		return ctx.fonts[name] or { panic('unreachable') }
	}

	mut ft_face := &C.FT_FaceRec(unsafe { nil })

	err_code := C.FT_New_Face(ctx.ft_lib, path.str, 0, &ft_face)
	if err_code != 0 {
		eprintln('FT_New_Face failed with error code: ${err_code} for path: ${path}')
		return error('Failed to load font: ${path}')
	}

	C.FT_Set_Pixel_Sizes(ft_face, 0, u32(size))

	hb_font := C.hb_ft_font_create_referenced(ft_face)
	C.hb_font_set_scale(hb_font, size * 64, size * 64)

	mut font := &Font{
		name:    name
		path:    path
		size:    size
		ft_face: ft_face
		hb_font: hb_font
	}
	ctx.fonts[name] = font
	return font
}

pub fn (mut f Font) free() {
	if f.hb_font != 0 {
		C.hb_font_destroy(f.hb_font)
	}
	if f.ft_face != 0 {
		C.FT_Done_Face(f.ft_face)
	}
}

pub fn (f &Font) has_glyph(codepoint u32) bool {
	index := C.FT_Get_Char_Index(f.ft_face, codepoint)
	return index != 0
}
