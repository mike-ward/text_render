/*
 * ime_bridge_linux.c — IBus IME bridge for vglyph (Linux).
 *
 * Uses libibus-1.0 client API.  IBus communicates over D-Bus so
 * no X11/Wayland window handles are needed for basic operation.
 * The GLib main context (already pumped for AT-SPI) delivers
 * commit/preedit callbacks.
 */

#include "ime_bridge_linux.h"
#include <ibus.h>
#include <string.h>

/* ── State ─────────────────────────────────────────────────────── */

static IBusBus          *ibus_bus     = NULL;
static IBusInputContext *ibus_ctx     = NULL;
static VGlyphIMECallbacks callbacks  = {0};
static gboolean          has_preedit = FALSE;
static gboolean          initialized = FALSE;

/* ── IBus signal handlers ──────────────────────────────────────── */

static void on_commit_text(IBusInputContext *ctx,
                           IBusText *text,
                           gpointer user_data) {
    (void)ctx; (void)user_data;
    if (!text || !text->text)
        return;
    /* Clear preedit state before commit */
    has_preedit = FALSE;
    if (callbacks.on_insert_text)
        callbacks.on_insert_text(text->text, callbacks.user_data);
}

static void on_update_preedit_text(IBusInputContext *ctx,
                                   IBusText *text,
                                   guint cursor_pos,
                                   gboolean visible,
                                   gpointer user_data) {
    (void)ctx; (void)user_data;
    if (!visible || !text || !text->text || text->text[0] == '\0') {
        /* Hidden or empty preedit — treat as unmark */
        if (has_preedit) {
            has_preedit = FALSE;
            if (callbacks.on_unmark_text)
                callbacks.on_unmark_text(callbacks.user_data);
        }
        return;
    }
    has_preedit = TRUE;

    /* Clause extraction from IBus attributes */
    if (callbacks.on_clauses_begin)
        callbacks.on_clauses_begin(callbacks.user_data);

    if (text->attrs) {
        IBusAttrList *attrs = text->attrs;
        guint i;
        for (i = 0; i < attrs->attributes->len; i++) {
            IBusAttribute *a = g_array_index(attrs->attributes,
                                             IBusAttribute*, i);
            if (a->type == IBUS_ATTR_TYPE_UNDERLINE) {
                int style = 0; /* raw */
                if (a->value == IBUS_ATTR_UNDERLINE_DOUBLE)
                    style = 2; /* selected */
                else if (a->value == IBUS_ATTR_UNDERLINE_SINGLE)
                    style = 1; /* converted */
                if (callbacks.on_clause)
                    callbacks.on_clause((int)a->start_index,
                                       (int)(a->end_index - a->start_index),
                                       style, callbacks.user_data);
            }
        }
    }

    if (callbacks.on_clauses_end)
        callbacks.on_clauses_end(callbacks.user_data);

    if (callbacks.on_marked_text)
        callbacks.on_marked_text(text->text, (int)cursor_pos,
                                 callbacks.user_data);
}

static void on_hide_preedit_text(IBusInputContext *ctx,
                                 gpointer user_data) {
    (void)ctx; (void)user_data;
    if (has_preedit) {
        has_preedit = FALSE;
        if (callbacks.on_unmark_text)
            callbacks.on_unmark_text(callbacks.user_data);
    }
}

/* ── Public API ────────────────────────────────────────────────── */

void vglyph_ime_linux_init(void) {
    if (initialized)
        return;
    initialized = TRUE;

    ibus_init();

    ibus_bus = ibus_bus_new();
    if (!ibus_bus || !ibus_bus_is_connected(ibus_bus)) {
        /* IBus daemon not running — IME silently unavailable */
        ibus_bus = NULL;
        return;
    }

    ibus_ctx = ibus_bus_create_input_context(ibus_bus, "vglyph");
    if (!ibus_ctx)
        return;

    /* Request capabilities: preedit + cursor location */
    ibus_input_context_set_capabilities(ibus_ctx,
        IBUS_CAP_PREEDIT_TEXT | IBUS_CAP_FOCUS |
        IBUS_CAP_SURROUNDING_TEXT);

    /* Connect signals */
    g_signal_connect(ibus_ctx, "commit-text",
                     G_CALLBACK(on_commit_text), NULL);
    g_signal_connect(ibus_ctx, "update-preedit-text",
                     G_CALLBACK(on_update_preedit_text), NULL);
    g_signal_connect(ibus_ctx, "hide-preedit-text",
                     G_CALLBACK(on_hide_preedit_text), NULL);
}

void vglyph_ime_linux_shutdown(void) {
    if (ibus_ctx) {
        g_object_unref(ibus_ctx);
        ibus_ctx = NULL;
    }
    if (ibus_bus) {
        g_object_unref(ibus_bus);
        ibus_bus = NULL;
    }
    has_preedit = FALSE;
    initialized = FALSE;
    memset(&callbacks, 0, sizeof(callbacks));
}

void vglyph_ime_linux_register_callbacks(VGlyphIMECallbacks cb) {
    callbacks = cb;
}

bool vglyph_ime_linux_filter_key(unsigned int keyval,
                                 unsigned int keycode,
                                 unsigned int state,
                                 bool is_release) {
    if (!ibus_ctx)
        return false;
    return ibus_input_context_process_key_event(
        ibus_ctx, keyval, keycode,
        state | (is_release ? IBUS_RELEASE_MASK : 0));
}

void vglyph_ime_linux_set_cursor_location(int x, int y,
                                           int w, int h) {
    if (!ibus_ctx)
        return;
    ibus_input_context_set_cursor_location(ibus_ctx, x, y, w, h);
}

void vglyph_ime_linux_focus_in(void) {
    if (!ibus_ctx)
        return;
    ibus_input_context_focus_in(ibus_ctx);
}

void vglyph_ime_linux_focus_out(void) {
    if (!ibus_ctx)
        return;
    ibus_input_context_focus_out(ibus_ctx);
}

bool vglyph_ime_linux_has_preedit(void) {
    return has_preedit;
}
