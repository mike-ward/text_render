// IME Overlay Stub for Non-Darwin Platforms
// Linux: delegates to IBus bridge. Other platforms: no-op.

#ifndef __APPLE__

#include <stddef.h>
#include "ime_overlay_darwin.h"

#ifdef __linux__

#ifdef VGLYPH_HAS_IBUS
#include "ime_bridge_linux.h"

// Sentinel value returned as "handle" to indicate active bridge
static int ime_linux_sentinel = 1;

void* vglyph_create_ime_overlay(void* mtk_view) {
    (void)mtk_view;
    vglyph_ime_linux_init();
    return &ime_linux_sentinel;
}

void vglyph_set_focused_field(void* handle, const char* field_id) {
    if (!handle) return;
    if (field_id)
        vglyph_ime_linux_focus_in();
    else
        vglyph_ime_linux_focus_out();
}

void vglyph_overlay_free(void* handle) {
    if (!handle) return;
    vglyph_ime_linux_shutdown();
}

void vglyph_overlay_register_callbacks(void* handle,
                                       VGlyphIMECallbacks callbacks) {
    if (!handle) return;
    vglyph_ime_linux_register_callbacks(callbacks);
}

void* vglyph_discover_mtkview_from_window(void* ns_window) {
    (void)ns_window;
    return NULL;
}

void* vglyph_create_ime_overlay_auto(void* ns_window) {
    (void)ns_window;
    vglyph_ime_linux_init();
    return &ime_linux_sentinel;
}

#else /* Linux without IBus */

void* vglyph_create_ime_overlay(void* mtk_view) {
    (void)mtk_view;
    return NULL;
}

void vglyph_set_focused_field(void* handle, const char* field_id) {
    (void)handle; (void)field_id;
}

void vglyph_overlay_free(void* handle) {
    (void)handle;
}

void vglyph_overlay_register_callbacks(void* handle,
                                       VGlyphIMECallbacks callbacks) {
    (void)handle; (void)callbacks;
}

void* vglyph_discover_mtkview_from_window(void* ns_window) {
    (void)ns_window;
    return NULL;
}

void* vglyph_create_ime_overlay_auto(void* ns_window) {
    (void)ns_window;
    return NULL;
}

#endif /* VGLYPH_HAS_IBUS */

#else /* Non-Linux, non-Darwin */

void* vglyph_create_ime_overlay(void* mtk_view) {
    (void)mtk_view;
    return NULL;
}

void vglyph_set_focused_field(void* handle, const char* field_id) {
    (void)handle; (void)field_id;
}

void vglyph_overlay_free(void* handle) {
    (void)handle;
}

void vglyph_overlay_register_callbacks(void* handle,
                                       VGlyphIMECallbacks callbacks) {
    (void)handle; (void)callbacks;
}

void* vglyph_discover_mtkview_from_window(void* ns_window) {
    (void)ns_window;
    return NULL;
}

void* vglyph_create_ime_overlay_auto(void* ns_window) {
    (void)ns_window;
    return NULL;
}

#endif /* __linux__ */

#endif /* !__APPLE__ */
