// IME Overlay for macOS
// Transparent NSView overlay that receives IME events above MTKView
// Phase 18: Infrastructure only (protocol stubs)
// Phase 19: Full NSTextInputClient implementation

#ifndef VGLYPH_IME_OVERLAY_DARWIN_H
#define VGLYPH_IME_OVERLAY_DARWIN_H

// Opaque handle to overlay view
typedef void* VGlyphOverlayHandle;

// Create overlay as sibling above MTKView
// mtk_view: Pointer to sokol's MTKView (casted from sapp_macos_get_window())
// Returns: Handle to overlay, or NULL on failure
VGlyphOverlayHandle vglyph_create_ime_overlay(void* mtk_view);

// Focus management - switches first responder
// handle: Overlay handle from vglyph_create_ime_overlay
// field_id: Field identifier (NULL = blur, non-NULL = focus)
void vglyph_set_focused_field(VGlyphOverlayHandle handle, const char* field_id);

// Free overlay and remove from view hierarchy
// handle: Overlay handle from vglyph_create_ime_overlay
void vglyph_overlay_free(VGlyphOverlayHandle handle);

#endif // VGLYPH_IME_OVERLAY_DARWIN_H
