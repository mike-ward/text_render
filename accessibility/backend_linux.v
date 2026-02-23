module accessibility

// Linux implementation of the AccessibilityBackend.
// Uses ATK + at-spi2-atk bridge to expose the accessibility tree over D-Bus.
// This file is only compiled on Linux (suffix _linux.v).
// When ATK dev packages are not installed, all methods are no-ops.

struct LinuxAccessibilityBackend {
mut:
	elements    map[int]voidptr // node_id -> VGlyphAccessible*
	initialized bool
}

fn (mut b LinuxAccessibilityBackend) ensure_init() {
	if !b.initialized {
		b.initialized = true
		$if $pkgconfig('atk') {
			C.vglyph_atspi_init()
		}
	}
}

fn (mut b LinuxAccessibilityBackend) update_tree(nodes map[int]AccessibilityNode, root_id int) {
	$if $pkgconfig('atk') {
		b.ensure_init()

		unsafe {
			// 1. Create / update elements
			for node_id, node in nodes {
				if node_id !in b.elements {
					b.elements[node_id] = C.vglyph_accessible_new(node_id, int(node.role))
				}
				elem := b.elements[node_id]

				C.vglyph_accessible_set_name(elem, node.text.str)
				C.vglyph_accessible_set_extents(elem, int(node.rect.x), int(node.rect.y),
					int(node.rect.width), int(node.rect.height))
				C.vglyph_accessible_set_focused(elem, if node.is_focused {
					1
				} else {
					0
				})
				C.vglyph_accessible_set_selected(elem, if node.is_selected {
					1
				} else {
					0
				})
			}

			// 2. Build hierarchy
			for node_id, node in nodes {
				elem := b.elements[node_id]

				// Set parent
				if node.parent != -1 {
					if node.parent in b.elements {
						C.vglyph_accessible_set_parent(elem, b.elements[node.parent])
					}
				}

				// Set children
				if node.children.len > 0 {
					mut kids := []voidptr{cap: node.children.len}
					for child_id in node.children {
						if child_id in b.elements {
							kids << b.elements[child_id]
						}
					}
					if kids.len > 0 {
						C.vglyph_accessible_set_children(elem, kids.data, kids.len)
					}
				}
			}

			// 3. Set root
			if root_id in b.elements {
				C.vglyph_atspi_set_root(b.elements[root_id])
			}
		}
		C.vglyph_atspi_flush()
	}
}

fn (mut b LinuxAccessibilityBackend) set_focus(node_id int) {
	$if $pkgconfig('atk') {
		b.ensure_init()

		unsafe {
			if node_id !in b.elements {
				return
			}
			elem := b.elements[node_id]

			C.vglyph_accessible_set_focused(elem, 1)
			C.vglyph_accessible_notify_focus(elem)
		}
		C.vglyph_atspi_flush()
	}
}

fn (mut b LinuxAccessibilityBackend) post_notification(node_id int,
	notification AccessibilityNotification) {
	$if $pkgconfig('atk') {
		b.ensure_init()

		unsafe {
			if node_id !in b.elements {
				return
			}
			elem := b.elements[node_id]

			match notification {
				.value_changed {
					C.vglyph_accessible_notify_value_changed(elem)
				}
				.selected_text_changed {
					C.vglyph_accessible_notify_text_changed(elem)
				}
			}
		}
		C.vglyph_atspi_flush()
	}
}

fn (mut b LinuxAccessibilityBackend) update_text_field(node_id int, value string,
	selected_range Range, cursor_line int) {
	$if $pkgconfig('atk') {
		b.ensure_init()

		unsafe {
			if node_id !in b.elements {
				return
			}
			elem := b.elements[node_id]

			C.vglyph_accessible_set_text_value(elem, value.str)
			C.vglyph_accessible_set_selection(elem, selected_range.location,
				selected_range.location + selected_range.length)
			C.vglyph_accessible_set_cursor_pos(elem, selected_range.location)
		}
		C.vglyph_atspi_flush()
	}
}

fn (mut b LinuxAccessibilityBackend) flush() {
	$if $pkgconfig('atk') {
		C.vglyph_atspi_flush()
	}
}
