module accessibility

// Stub implementation for platforms without native accessibility
// (Windows, FreeBSD, etc.). Selected by new_accessibility_backend()
// when no platform backend matches.
struct StubAccessibilityBackend {}

fn (mut b StubAccessibilityBackend) update_tree(nodes map[int]AccessibilityNode, root_id int) {
	// Do nothing on unsupported platforms.
}

fn (mut b StubAccessibilityBackend) set_focus(node_id int) {
	// Do nothing
}

fn (mut b StubAccessibilityBackend) post_notification(node_id int,
	notification AccessibilityNotification) {
	// Do nothing
}

fn (mut b StubAccessibilityBackend) update_text_field(node_id int, value string,
	selected_range Range, cursor_line int) {
	// Do nothing
}

fn (mut b StubAccessibilityBackend) flush() {
	// Do nothing
}
