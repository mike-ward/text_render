module text_render

pub struct Context {
	ft_lib &C.FT_LibraryRec
mut:
	fonts map[string]&Font
}

pub fn new_context() !&Context {
	// Initialize pointer to null
	mut ft_lib := &C.FT_LibraryRec(unsafe { nil })
	if C.FT_Init_FreeType(&ft_lib) != 0 {
		return error('Failed to initialize FreeType library')
	}
	return &Context{
		ft_lib: ft_lib
		fonts:  map[string]&Font{}
	}
}

pub fn (mut ctx Context) free() {
	for _, mut font in ctx.fonts {
		font.free()
	}
	if voidptr(ctx.ft_lib) != unsafe { nil } {
		C.FT_Done_FreeType(ctx.ft_lib)
	}
}
