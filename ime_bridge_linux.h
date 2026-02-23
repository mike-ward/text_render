/*
 * ime_bridge_linux.h — IBus IME bridge for vglyph (Linux).
 *
 * Provides the same callback-based interface as the macOS IME
 * bridge so the V-side integration is symmetrical.
 */

#ifndef VGLYPH_IME_BRIDGE_LINUX_H
#define VGLYPH_IME_BRIDGE_LINUX_H

#include <stdbool.h>
#include "ime_overlay_darwin.h"  /* VGlyphIMECallbacks */

#ifdef __cplusplus
extern "C" {
#endif

/* Lifecycle */
void  vglyph_ime_linux_init(void);
void  vglyph_ime_linux_shutdown(void);

/* Callback registration (mirrors overlay API) */
void  vglyph_ime_linux_register_callbacks(VGlyphIMECallbacks cb);

/* Key event filtering — true if IBus consumed the key */
bool  vglyph_ime_linux_filter_key(unsigned int keyval,
                                  unsigned int keycode,
                                  unsigned int state,
                                  bool is_release);

/* Candidate window positioning */
void  vglyph_ime_linux_set_cursor_location(int x, int y,
                                           int w, int h);

/* Focus management */
void  vglyph_ime_linux_focus_in(void);
void  vglyph_ime_linux_focus_out(void);

/* Query preedit state */
bool  vglyph_ime_linux_has_preedit(void);

#ifdef __cplusplus
}
#endif

#endif /* VGLYPH_IME_BRIDGE_LINUX_H */
