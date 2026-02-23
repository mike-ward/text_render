module accessibility

// AT-SPI bindings for Linux accessibility.
// Uses ATK + atk-bridge to publish the accessibility tree over D-Bus.
// Conditionally compiled only when ATK dev packages are installed.

$if $pkgconfig('atk') {
	#pkgconfig atk
	#pkgconfig atk-bridge-2.0
	#flag -I @VMODROOT/accessibility
	#flag linux @VMODROOT/accessibility/atspi_helpers.c

	#include "atspi_helpers.h"

	// Lifecycle
	fn C.vglyph_atspi_init()
	fn C.vglyph_atspi_flush()

	// Object creation / property setters
	fn C.vglyph_accessible_new(node_id int, role_ordinal int) voidptr
	fn C.vglyph_accessible_set_name(obj voidptr, name &char)
	fn C.vglyph_accessible_set_extents(obj voidptr, x int, y int, w int, h int)
	fn C.vglyph_accessible_set_focused(obj voidptr, focused int)
	fn C.vglyph_accessible_set_selected(obj voidptr, selected int)
	fn C.vglyph_accessible_set_parent(obj voidptr, parent voidptr)
	fn C.vglyph_accessible_set_children(obj voidptr, kids &voidptr, n int)

	// Signal / notification helpers
	fn C.vglyph_accessible_notify_focus(obj voidptr)
	fn C.vglyph_accessible_notify_value_changed(obj voidptr)
	fn C.vglyph_accessible_notify_text_changed(obj voidptr)

	// Text field support
	fn C.vglyph_accessible_set_text_value(obj voidptr, text &char)
	fn C.vglyph_accessible_set_selection(obj voidptr, start int, end int)
	fn C.vglyph_accessible_set_cursor_pos(obj voidptr, pos int)

	// Root / announce
	fn C.vglyph_atspi_set_root(root voidptr)
	fn C.vglyph_atspi_announce(message &char)
}
