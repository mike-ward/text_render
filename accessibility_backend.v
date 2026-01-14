module vglyph

// AccessibilityBackend is the interface that platform-specific implementations must satisfy.
// It handles the synchronization between the vglyph logical tree and the OS accessibility tree.
pub interface AccessibilityBackend {
	mut:
	// update_tree is called when the accessibility tree has changed.
	// nodes is a flat list of all nodes in the tree, keyed by their ID.
	update_tree(nodes map[int]AccessibilityNode, root_id int)

	// set_focus notifies the backend that a specific node has received focus.
	set_focus(node_id int)
}

// new_accessibility_backend creates a platform-specific backend instance.
fn new_accessibility_backend() AccessibilityBackend {
	$if darwin {
		return &DarwinAccessibilityBackend{}
	} $else {
		return &StubAccessibilityBackend{}
	}
}
