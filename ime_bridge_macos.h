// IME Bridge forward declarations
// This header makes the Obj-C functions visible to V's generated C code.

#ifndef VGLYPH_IME_BRIDGE_MACOS_H
#define VGLYPH_IME_BRIDGE_MACOS_H

#include <stdbool.h>

// Callback types matching c_bindings.v
typedef void (*IMEMarkedTextCallback)(const char* text, int cursor_pos, void* user_data);
typedef void (*IMEInsertTextCallback)(const char* text, void* user_data);
typedef void (*IMEUnmarkTextCallback)(void* user_data);
typedef bool (*IMEBoundsCallback)(void* user_data, float* x, float* y, float* width, float* height);

// Register callbacks from V code
void vglyph_ime_register_callbacks(IMEMarkedTextCallback marked,
                                   IMEInsertTextCallback insert,
                                   IMEUnmarkTextCallback unmark,
                                   IMEBoundsCallback bounds,
                                   void* user_data);

// Check if IME handled the last key event (and clear the flag)
// Call this at the start of char event handling to suppress duplicate input.
bool vglyph_ime_did_handle_key(void);

// Check if IME has active marked text (composition in progress)
bool vglyph_ime_has_marked_text(void);

#endif // VGLYPH_IME_BRIDGE_MACOS_H
