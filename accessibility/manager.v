module accessibility

import gg

// AccessibilityManager manages the lifecycle of the accessibility tree.
pub struct AccessibilityManager {
mut:
	backend  AccessibilityBackend
	nodes    map[int]AccessibilityNode
	next_id  int = 1
	root_id  int = 1
	is_dirty bool
}

// new_accessibility_manager creates a manager with platform-specific backend.
pub fn new_accessibility_manager() &AccessibilityManager {
	backend := new_accessibility_backend()
	return &AccessibilityManager{
		backend: backend
		nodes:   map[int]AccessibilityNode{}
	}
}

// add_text_node adds a text node to the current accessibility tree.
pub fn (mut am AccessibilityManager) add_text_node(text string, rect gg.Rect) {
	// Ensure root exists if first call in frame/session
	if am.nodes.len == 0 {
		am.reset()
	}

	id := am.next_node_id()
	node := AccessibilityNode{
		id:     id
		role:   .text
		rect:   rect
		text:   text
		parent: am.root_id
	}

	am.nodes[id] = node

	// Append to root children
	// In the future, we might support nested containers, but for now flat list under root.
	mut parent_node := am.nodes[am.root_id]
	parent_node.children << id
	am.nodes[am.root_id] = parent_node
}

// create_text_field_node creates a text field accessibility node.
pub fn (mut am AccessibilityManager) create_text_field_node(rect gg.Rect) int {
	// Ensure root exists
	if am.nodes.len == 0 {
		am.reset()
	}
	id := am.next_node_id()
	node := AccessibilityNode{
		id:     id
		role:   .text_field
		rect:   rect
		parent: am.root_id
	}
	am.nodes[id] = node
	// Add to root children
	mut parent_node := am.nodes[am.root_id]
	parent_node.children << id
	am.nodes[am.root_id] = parent_node
	return id
}

// update_text_field updates text field attributes via backend.
pub fn (mut am AccessibilityManager) update_text_field(node_id int, value string,
	selected_range Range, cursor_line int) {
	am.backend.update_text_field(node_id, value, selected_range, cursor_line)
}

// set_focus notifies the backend that a specific node has received focus.
pub fn (mut am AccessibilityManager) set_focus(node_id int) {
	am.backend.set_focus(node_id)
}

// post_notification posts an accessibility notification for a node.
pub fn (mut am AccessibilityManager) post_notification(node_id int,
	notification AccessibilityNotification) {
	am.backend.post_notification(node_id, notification)
}

// commit pushes accumulated accessibility updates to the platform backend.
pub fn (mut am AccessibilityManager) commit() {
	if am.nodes.len == 0 {
		return
	}
	am.push_updates()
	am.reset()
}

fn (mut am AccessibilityManager) reset() {
	am.nodes.clear()
	am.next_id = 1

	// Create Root Node (Window/Container)
	am.root_id = am.next_node_id()
	mut root := AccessibilityNode{
		id:   am.root_id
		role: .container
		// Root rect should ideally cover the window or be dynamic.
		rect: gg.Rect{
			x:      0
			y:      0
			width:  0 // TODO: Pass window size?
			height: 0
		}
		text: 'Content'
	}
	am.nodes[am.root_id] = root
}

fn (mut am AccessibilityManager) next_node_id() int {
	id := am.next_id
	am.next_id++
	return id
}

fn (mut am AccessibilityManager) push_updates() {
	am.backend.update_tree(am.nodes, am.root_id)
}
