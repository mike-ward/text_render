// IME Overlay Stub for Non-Darwin Platforms
// No-op implementations for platforms that don't use NSTextInputClient

#ifndef __APPLE__

#include <stddef.h>
#include "ime_overlay_darwin.h"

// Create overlay (no-op on non-Darwin)
void* vglyph_create_ime_overlay(void* mtk_view) {
    return NULL;
}

// Focus management (no-op on non-Darwin)
void vglyph_set_focused_field(void* handle, const char* field_id) {
    // No-op
}

// Free overlay (no-op on non-Darwin)
void vglyph_overlay_free(void* handle) {
    // No-op
}

#endif // !__APPLE__
