module accessibility

// Darwin (macOS) implementation of the AccessibilityBackend.
// This file is only compiled on macOS.

fn C.sapp_macos_get_window() voidptr

struct DarwinAccessibilityBackend {
mut:
	elements map[int]Id // node_id -> NSAccessibilityElement*
	window   Id
}

fn get_role_string(role AccessibilityRole) Id {
	match role {
		.text, .static_text { return ns_string('AXStaticText') }
		.container, .group { return ns_string('AXGroup') }
		.text_field { return ns_string('AXTextField') }
		.window { return ns_string('AXWindow') }
		.prose { return ns_string('AXGroup') } // Or AXStaticText depending on usage
		.list { return ns_string('AXList') }
		.list_item { return ns_string('AXGroup') }
	}
}

fn (mut b DarwinAccessibilityBackend) get_window() Id {
	if b.window == unsafe { nil } {
		b.window = C.sapp_macos_get_window()
	}
	return b.window
}

fn (mut b DarwinAccessibilityBackend) update_tree(nodes map[int]AccessibilityNode, root_id int) {
	window := b.get_window()
	if window == unsafe { nil } {
		return
	}

	unsafe {
		// 1. Create/Update Elements
		for node_id, node in nodes {
			if node_id !in b.elements {
				b.elements[node_id] = b.create_element(node.role)
			}
			elem := b.elements[node_id]

			// Set Label
			label_ns := ns_string(node.text)
			C.v_msgSend_void_id(elem, sel_register_name('setAccessibilityLabel:'), label_ns)

			// Set Frame
			win_frame := get_window_frame(window)
			// Flip Y coordinate: macOS screen coordinates start from bottom-left.
			// vglyph coordinates start from top-left of the window.
			h := win_frame.size.height - f64(node.rect.y) - f64(node.rect.height)
			screen_y := win_frame.origin.y + h

			ns_rect := make_ns_rect(f32(win_frame.origin.x + f64(node.rect.x)), f32(screen_y),
				f32(node.rect.width), f32(node.rect.height))
			C.v_msgSend_setFrame(elem, sel_register_name('setAccessibilityFrame:'), ns_rect)
		}

		// 2. Build Hierarchy
		for node_id, node in nodes {
			elem := b.elements[node_id]

			// Set Parent
			parent_id := node.parent
			if parent_id != -1 {
				if parent_id in b.elements {
					parent_elem := b.elements[parent_id]
					C.v_msgSend_void_id(elem, sel_register_name('setAccessibilityParent:'),
						parent_elem)
				}
			} else {
				// Root's parent is Window
				C.v_msgSend_void_id(elem, sel_register_name('setAccessibilityParent:'),
					window)
			}

			// Set Children
			if node.children.len > 0 {
				children_ns := ns_mutable_array_new()
				for child_id in node.children {
					if child_id in b.elements {
						child_elem := b.elements[child_id]
						ns_array_add_object(children_ns, child_elem)
					}
				}
				C.v_msgSend_void_id(elem, sel_register_name('setAccessibilityChildren:'),
					children_ns)
			}
		}

		// 3. Attach Root to Window
		if root_id in b.elements {
			root_elem := b.elements[root_id]
			root_array := ns_mutable_array_new()
			ns_array_add_object(root_array, root_elem)
			C.v_msgSend_void_id(window, sel_register_name('setAccessibilityChildren:'),
				root_array)
		}
	}
}

fn (mut b DarwinAccessibilityBackend) create_element(role AccessibilityRole) Id {
	unsafe {
		cls := C.v_objc_getClass(c'NSAccessibilityElement')
		if cls == nil {
			return nil
		}

		alloc_sel := sel_register_name('alloc')
		init_sel := sel_register_name('init')

		alloc_obj := C.v_msgSend_0(cls, alloc_sel)
		obj := C.v_msgSend_0(alloc_obj, init_sel)

		// Set Role
		role_val := get_role_string(role)
		role_sel := sel_register_name('setAccessibilityRole:')
		C.v_msgSend_void_id(obj, role_sel, role_val)

		// Enable accessibility for text fields
		if role == .text_field {
			enabled_sel := sel_register_name('setAccessibilityEnabled:')
			C.v_msgSend(obj, enabled_sel, voidptr(1))
		}

		return obj
	}
}

fn (mut b DarwinAccessibilityBackend) set_focus(node_id int) {
	// TODO
}

fn (mut b DarwinAccessibilityBackend) post_notification(node_id int,
	notification AccessibilityNotification) {
	// TODO: NSAccessibility notifications require element attached to window
	// For now, announcements via AccessibilityAnnouncer provide VoiceOver feedback
	// Full NSAccessibility integration deferred to future work
	_ = node_id
	_ = notification
}

fn (mut b DarwinAccessibilityBackend) update_text_field(node_id int, value string,
	selected_range Range, cursor_line int) {
	// TODO: NSAccessibility element integration requires window attachment
	// For now, announcements via AccessibilityAnnouncer provide VoiceOver feedback
	// Full NSAccessibility integration deferred to future work
	_ = node_id
	_ = value
	_ = selected_range
	_ = cursor_line
}

// Helpers
fn get_window_frame(window Id) C.NSRect {
	return C.v_msgSend_nsrect(window, sel_register_name('frame'))
}
