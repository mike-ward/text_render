/*
 * atspi_helpers.c — AT-SPI accessibility backend for vglyph (Linux).
 *
 * Implements a VGlyphAccessible GObject extending AtkObject with
 * AtkComponent interface, plus helpers for atk-bridge initialisation,
 * D-Bus flushing, and live announcements.
 */

#include "atspi_helpers.h"
#include <atk-bridge.h>
#include <string.h>

/* ── Forward declarations ──────────────────────────────────────── */

static void vglyph_accessible_component_init(AtkComponentIface *iface);
static void vglyph_accessible_text_init(AtkTextIface *iface);

/* ── Globals ───────────────────────────────────────────────────── */

static VGlyphAccessible *vglyph_app_root = NULL;  /* ATK_ROLE_APPLICATION */
static AtkObject        *vglyph_root     = NULL;  /* Points to app_root  */
static gboolean          vglyph_atspi_initialized = FALSE;

/* ── Role mapping (VGlyph enum ordinal → ATK) ──────────────────── */

/*
 * AccessibilityRole ordinals (must match accessibility_types.v):
 *   0 = text         → ATK_ROLE_LABEL
 *   1 = static_text  → ATK_ROLE_LABEL
 *   2 = container    → ATK_ROLE_PANEL
 *   3 = group        → ATK_ROLE_PANEL
 *   4 = window       → ATK_ROLE_FRAME
 *   5 = prose        → ATK_ROLE_PARAGRAPH
 *   6 = list         → ATK_ROLE_LIST
 *   7 = list_item    → ATK_ROLE_LIST_ITEM
 *   8 = text_field   → ATK_ROLE_ENTRY
 */
static AtkRole map_role(gint ordinal) {
    switch (ordinal) {
    case 0:  return ATK_ROLE_LABEL;      /* text        */
    case 1:  return ATK_ROLE_LABEL;      /* static_text */
    case 2:  return ATK_ROLE_PANEL;      /* container   */
    case 3:  return ATK_ROLE_PANEL;      /* group       */
    case 4:  return ATK_ROLE_FRAME;      /* window      */
    case 5:  return ATK_ROLE_PARAGRAPH;  /* prose       */
    case 6:  return ATK_ROLE_LIST;       /* list        */
    case 7:  return ATK_ROLE_LIST_ITEM;  /* list_item   */
    case 8:  return ATK_ROLE_ENTRY;      /* text_field  */
    default: return ATK_ROLE_UNKNOWN;
    }
}

/* ══════════════════════════════════════════════════════════════════
 *  GObject / AtkObject boilerplate
 * ══════════════════════════════════════════════════════════════════ */

G_DEFINE_TYPE_WITH_CODE(VGlyphAccessible, vglyph_accessible, ATK_TYPE_OBJECT,
    G_IMPLEMENT_INTERFACE(ATK_TYPE_COMPONENT, vglyph_accessible_component_init)
    G_IMPLEMENT_INTERFACE(ATK_TYPE_TEXT, vglyph_accessible_text_init))

/* ── AtkObject vfunc overrides ─────────────────────────────────── */

static const gchar *va_get_name(AtkObject *obj) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(obj);
    return self->name ? self->name : "";
}

static AtkRole va_get_role(AtkObject *obj) {
    return VGLYPH_ACCESSIBLE(obj)->role;
}

static AtkObject *va_get_parent(AtkObject *obj) {
    return VGLYPH_ACCESSIBLE(obj)->parent_obj;
}

static gint va_get_n_children(AtkObject *obj) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(obj);
    return self->children ? (gint)self->children->len : 0;
}

static AtkObject *va_ref_child(AtkObject *obj, gint i) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(obj);
    if (!self->children || i < 0 || (guint)i >= self->children->len)
        return NULL;
    AtkObject *child = g_ptr_array_index(self->children, i);
    if (child) g_object_ref(child);
    return child;
}

static gint va_get_index_in_parent(AtkObject *obj) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(obj);
    AtkObject *parent = self->parent_obj;
    if (!parent) return -1;

    if (VGLYPH_TYPE_ACCESSIBLE == G_OBJECT_TYPE(parent)) {
        VGlyphAccessible *p = VGLYPH_ACCESSIBLE(parent);
        if (p->children) {
            for (guint i = 0; i < p->children->len; i++) {
                if (g_ptr_array_index(p->children, i) == obj)
                    return (gint)i;
            }
        }
    }
    return -1;
}

static AtkStateSet *va_ref_state_set(AtkObject *obj) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(obj);
    AtkStateSet *set = atk_state_set_new();

    atk_state_set_add_state(set, ATK_STATE_VISIBLE);
    atk_state_set_add_state(set, ATK_STATE_SHOWING);
    atk_state_set_add_state(set, ATK_STATE_ENABLED);

    if (self->focused)
        atk_state_set_add_state(set, ATK_STATE_FOCUSED);
    if (self->selected)
        atk_state_set_add_state(set, ATK_STATE_SELECTED);
    if (self->role == ATK_ROLE_ENTRY) {
        atk_state_set_add_state(set, ATK_STATE_EDITABLE);
        atk_state_set_add_state(set, ATK_STATE_FOCUSABLE);
    }

    return set;
}

/* ── AtkComponent interface ────────────────────────────────────── */

static void va_get_extents(AtkComponent *component,
                           gint *x, gint *y, gint *width, gint *height,
                           AtkCoordType coord_type) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(component);
    (void)coord_type; /* We always report window-relative coordinates */
    if (x)      *x = self->x;
    if (y)      *y = self->y;
    if (width)  *width = self->width;
    if (height) *height = self->height;
}

static void vglyph_accessible_component_init(AtkComponentIface *iface) {
    iface->get_extents = va_get_extents;
}

/* ── AtkText interface ─────────────────────────────────────────── */

static gchar *va_text_get_text(AtkText *text, gint start, gint end) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(text);
    if (!self->text_value)
        return g_strdup("");
    glong len = g_utf8_strlen(self->text_value, -1);
    if (end == -1 || end > len)
        end = (gint)len;
    if (start < 0) start = 0;
    if (start >= end)
        return g_strdup("");
    const gchar *s = g_utf8_offset_to_pointer(self->text_value, start);
    const gchar *e = g_utf8_offset_to_pointer(self->text_value, end);
    return g_strndup(s, e - s);
}

static gint va_text_get_character_count(AtkText *text) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(text);
    if (!self->text_value)
        return 0;
    return (gint)g_utf8_strlen(self->text_value, -1);
}

static gunichar va_text_get_character_at_offset(AtkText *text, gint offset) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(text);
    if (!self->text_value)
        return 0;
    glong len = g_utf8_strlen(self->text_value, -1);
    if (offset < 0 || offset >= (gint)len)
        return 0;
    const gchar *p = g_utf8_offset_to_pointer(self->text_value, offset);
    return g_utf8_get_char(p);
}

static gint va_text_get_caret_offset(AtkText *text) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(text);
    return self->cursor_pos;
}

static gint va_text_get_n_selections(AtkText *text) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(text);
    return (self->sel_start != self->sel_end) ? 1 : 0;
}

static gchar *va_text_get_selection(AtkText *text, gint selection_num,
                                    gint *start_offset, gint *end_offset) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(text);
    if (selection_num != 0 || self->sel_start == self->sel_end) {
        if (start_offset) *start_offset = 0;
        if (end_offset) *end_offset = 0;
        return NULL;
    }
    if (start_offset) *start_offset = self->sel_start;
    if (end_offset) *end_offset = self->sel_end;
    return va_text_get_text(text, self->sel_start, self->sel_end);
}

static void vglyph_accessible_text_init(AtkTextIface *iface) {
    iface->get_text               = va_text_get_text;
    iface->get_character_count    = va_text_get_character_count;
    iface->get_character_at_offset = va_text_get_character_at_offset;
    iface->get_caret_offset       = va_text_get_caret_offset;
    iface->get_n_selections       = va_text_get_n_selections;
    iface->get_selection          = va_text_get_selection;
}

/* ── GObject init / finalize ───────────────────────────────────── */

static void vglyph_accessible_finalize(GObject *obj) {
    VGlyphAccessible *self = VGLYPH_ACCESSIBLE(obj);
    g_free(self->name);
    g_free(self->text_value);
    if (self->children)
        g_ptr_array_unref(self->children);
    G_OBJECT_CLASS(vglyph_accessible_parent_class)->finalize(obj);
}

static void vglyph_accessible_class_init(VGlyphAccessibleClass *klass) {
    GObjectClass *gobject_class = G_OBJECT_CLASS(klass);
    AtkObjectClass *atk_class = ATK_OBJECT_CLASS(klass);

    gobject_class->finalize = vglyph_accessible_finalize;

    atk_class->get_name            = va_get_name;
    atk_class->get_role            = va_get_role;
    atk_class->get_parent          = va_get_parent;
    atk_class->get_n_children      = va_get_n_children;
    atk_class->ref_child           = va_ref_child;
    atk_class->get_index_in_parent = va_get_index_in_parent;
    atk_class->ref_state_set       = va_ref_state_set;
}

static void vglyph_accessible_init(VGlyphAccessible *self) {
    self->node_id    = -1;
    self->name       = NULL;
    self->role       = ATK_ROLE_UNKNOWN;
    self->x = self->y = self->width = self->height = 0;
    self->focused    = FALSE;
    self->selected   = FALSE;
    self->parent_obj = NULL;
    self->children   = g_ptr_array_new_with_free_func(g_object_unref);
    self->text_value = NULL;
    self->sel_start  = 0;
    self->sel_end    = 0;
    self->cursor_pos = 0;
}

/* ══════════════════════════════════════════════════════════════════
 *  Custom root override
 * ══════════════════════════════════════════════════════════════════ */

static AtkObject *vglyph_get_root(void) {
    return vglyph_root;
}

/* ══════════════════════════════════════════════════════════════════
 *  Public API
 * ══════════════════════════════════════════════════════════════════ */

void vglyph_atspi_init(void) {
    if (vglyph_atspi_initialized)
        return;
    vglyph_atspi_initialized = TRUE;

    /* Ensure the VGlyphAccessible type is registered. */
    g_type_ensure(VGLYPH_TYPE_ACCESSIBLE);

    /* Create the application-level root object.
     * AT-SPI expects get_root() to return an ATK_ROLE_APPLICATION object;
     * the tree from the manager is attached as its child. */
    vglyph_app_root = g_object_new(VGLYPH_TYPE_ACCESSIBLE, NULL);
    vglyph_app_root->name = g_strdup("VGlyph");
    vglyph_app_root->role = ATK_ROLE_APPLICATION;
    vglyph_root = ATK_OBJECT(vglyph_app_root);

    /* Override AtkUtil.get_root so atk-bridge publishes our tree. */
    AtkUtilClass *util_class = ATK_UTIL_CLASS(g_type_class_ref(ATK_TYPE_UTIL));
    util_class->get_root = vglyph_get_root;

    /* Start the atk-bridge — this connects to the AT-SPI bus.
     * The root is already set, so the bridge will find it immediately. */
    atk_bridge_adaptor_init(NULL, NULL);
}

void vglyph_atspi_flush(void) {
    /* Pump the default GLib main context once (non-blocking) to push
     * any pending D-Bus messages to the accessibility bus. */
    g_main_context_iteration(NULL, FALSE);
}

VGlyphAccessible *vglyph_accessible_new(gint node_id, gint role_ordinal) {
    VGlyphAccessible *obj = g_object_new(VGLYPH_TYPE_ACCESSIBLE, NULL);
    obj->node_id = node_id;
    obj->role = map_role(role_ordinal);
    return obj;
}

void vglyph_accessible_set_name(VGlyphAccessible *obj, const gchar *name) {
    if (!obj) return;
    g_free(obj->name);
    obj->name = g_strdup(name);
}

void vglyph_accessible_set_extents(VGlyphAccessible *obj, gint x, gint y, gint w, gint h) {
    if (!obj) return;
    obj->x = x;
    obj->y = y;
    obj->width = w;
    obj->height = h;
}

void vglyph_accessible_set_focused(VGlyphAccessible *obj, gboolean focused) {
    if (!obj) return;
    obj->focused = focused;
}

void vglyph_accessible_set_selected(VGlyphAccessible *obj, gboolean selected) {
    if (!obj) return;
    obj->selected = selected;
}

void vglyph_accessible_set_parent(VGlyphAccessible *obj, AtkObject *parent) {
    if (!obj) return;
    obj->parent_obj = parent;
}

void vglyph_accessible_set_children(VGlyphAccessible *obj, AtkObject **kids, gint n) {
    if (!obj) return;

    /* Clear existing children. */
    g_ptr_array_set_size(obj->children, 0);

    for (gint i = 0; i < n; i++) {
        g_object_ref(kids[i]);
        g_ptr_array_add(obj->children, kids[i]);
    }
}

/* ── Signals / notifications ───────────────────────────────────── */

void vglyph_accessible_notify_focus(VGlyphAccessible *obj) {
    if (!obj) return;
    atk_object_notify_state_change(ATK_OBJECT(obj), ATK_STATE_FOCUSED, obj->focused);
    g_signal_emit_by_name(obj, "focus-event", obj->focused);
}

void vglyph_accessible_notify_value_changed(VGlyphAccessible *obj) {
    if (!obj) return;
    g_object_notify(G_OBJECT(obj), "accessible-name");
    g_signal_emit_by_name(obj, "visible-data-changed");
}

void vglyph_accessible_notify_text_changed(VGlyphAccessible *obj) {
    if (!obj) return;
    gint len = obj->text_value
        ? (gint)g_utf8_strlen(obj->text_value, -1) : 0;
    g_signal_emit_by_name(obj, "text-changed::insert", 0, len);
    g_signal_emit_by_name(obj, "text-caret-moved", obj->cursor_pos);
    g_signal_emit_by_name(obj, "text-selection-changed");
}

/* ── Text field support ────────────────────────────────────────── */

void vglyph_accessible_set_text_value(VGlyphAccessible *obj, const gchar *text) {
    if (!obj) return;
    g_free(obj->text_value);
    obj->text_value = g_strdup(text);
}

void vglyph_accessible_set_selection(VGlyphAccessible *obj, gint start, gint end) {
    if (!obj) return;
    obj->sel_start = start;
    obj->sel_end = end;
}

void vglyph_accessible_set_cursor_pos(VGlyphAccessible *obj, gint pos) {
    if (!obj) return;
    obj->cursor_pos = pos;
}

/* ── Root / announce ───────────────────────────────────────────── */

void vglyph_atspi_set_root(AtkObject *root) {
    if (!vglyph_app_root || !root)
        return;

    /* Attach the tree root as the sole child of the application object.
     * Also set its parent pointer back to the app root. */
    g_ptr_array_set_size(vglyph_app_root->children, 0);
    g_object_ref(root);
    g_ptr_array_add(vglyph_app_root->children, root);

    if (VGLYPH_TYPE_ACCESSIBLE == G_OBJECT_TYPE(root))
        VGLYPH_ACCESSIBLE(root)->parent_obj = ATK_OBJECT(vglyph_app_root);
}

void vglyph_atspi_announce(const gchar *message) {
    if (!message || message[0] == '\0' || !vglyph_app_root)
        return;

    /*
     * Emit an ATK "announcement" by notifying a name-change on the app root.
     * Screen readers such as Orca pick up object:property-change:accessible-name
     * events and will speak the new name.
     *
     * Temporarily set the app root name to the message, emit the signal,
     * then restore it.
     */
    gchar *saved = vglyph_app_root->name;
    vglyph_app_root->name = g_strdup(message);

    g_object_notify(G_OBJECT(vglyph_app_root), "accessible-name");
    g_signal_emit_by_name(vglyph_app_root, "visible-data-changed");

    /* Restore original name. */
    g_free(vglyph_app_root->name);
    vglyph_app_root->name = saved;
}
