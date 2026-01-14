module vglyph

// Stub implementation for non-macOS platforms.
// This ensures that the code compiles on Windows and Linux without
// requiring platform-specific dependencies.

@[if !darwin]
struct StubAccessibilityBackend {}

fn (mut b StubAccessibilityBackend) update_tree(nodes map[int]AccessibilityNode, root_id int) {
	// Do nothing on unsupported platforms.
}

fn (mut b StubAccessibilityBackend) set_focus(node_id int) {
	// Do nothing
}
