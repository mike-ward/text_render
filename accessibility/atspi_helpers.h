#ifndef VGLYPH_ATSPI_HELPERS_H
#define VGLYPH_ATSPI_HELPERS_H

#include <atk/atk.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── GObject type for VGlyphAccessible ─────────────────────────── */

#define VGLYPH_TYPE_ACCESSIBLE (vglyph_accessible_get_type())
#define VGLYPH_ACCESSIBLE(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), VGLYPH_TYPE_ACCESSIBLE, VGlyphAccessible))

typedef struct _VGlyphAccessible VGlyphAccessible;
typedef struct _VGlyphAccessibleClass VGlyphAccessibleClass;

struct _VGlyphAccessible {
    AtkObject parent_instance;

    gint node_id;
    gchar *name;
    AtkRole role;

    /* Geometry (screen coordinates) */
    gint x, y, width, height;

    /* State */
    gboolean focused;
    gboolean selected;

    /* Hierarchy */
    AtkObject *parent_obj;
    GPtrArray *children; /* of AtkObject* */

    /* Text field support */
    gchar *text_value;
    gint sel_start;
    gint sel_end;
    gint cursor_pos;
};

struct _VGlyphAccessibleClass {
    AtkObjectClass parent_class;
};

GType vglyph_accessible_get_type(void);

/* ── Lifecycle ─────────────────────────────────────────────────── */

/** Override atk_get_root() and initialise the atk-bridge. */
void vglyph_atspi_init(void);

/** Pump the GLib main context so D-Bus signals are flushed. */
void vglyph_atspi_flush(void);

/* ── Object creation / property setters ────────────────────────── */

/** Create a new VGlyphAccessible with the given node ID and role ordinal. */
VGlyphAccessible *vglyph_accessible_new(gint node_id, gint role_ordinal);

void vglyph_accessible_set_name(VGlyphAccessible *obj, const gchar *name);
void vglyph_accessible_set_extents(VGlyphAccessible *obj, gint x, gint y, gint w, gint h);
void vglyph_accessible_set_focused(VGlyphAccessible *obj, gboolean focused);
void vglyph_accessible_set_selected(VGlyphAccessible *obj, gboolean selected);
void vglyph_accessible_set_parent(VGlyphAccessible *obj, AtkObject *parent);
void vglyph_accessible_set_children(VGlyphAccessible *obj, AtkObject **kids, gint n);

/* ── Signal / notification helpers ─────────────────────────────── */

void vglyph_accessible_notify_focus(VGlyphAccessible *obj);
void vglyph_accessible_notify_value_changed(VGlyphAccessible *obj);
void vglyph_accessible_notify_text_changed(VGlyphAccessible *obj);

/* ── Text field support ────────────────────────────────────────── */

void vglyph_accessible_set_text_value(VGlyphAccessible *obj, const gchar *text);
void vglyph_accessible_set_selection(VGlyphAccessible *obj, gint start, gint end);
void vglyph_accessible_set_cursor_pos(VGlyphAccessible *obj, gint pos);

/* ── Root / announce ───────────────────────────────────────────── */

/** Set the application-level root accessible object. */
void vglyph_atspi_set_root(AtkObject *root);

/** Live-region announcement for screen readers. */
void vglyph_atspi_announce(const gchar *message);

#ifdef __cplusplus
}
#endif

#endif /* VGLYPH_ATSPI_HELPERS_H */
