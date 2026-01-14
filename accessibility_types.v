module vglyph

import gg

// AccessibilityRole defines the semantic role of an element in the accessibility tree.
pub enum AccessibilityRole {
	text        // A leaf node containing text
	static_text // Label or other static text
	container   // Generic container
	group       // logical grouping of elements
	window      // The root window
	prose       // Large block of text (paragraph)
	list        // List container
	list_item   // Single item in a list
}

// AccessibilityNode represents a single node in the accessibility tree.
// It is a platform-agnostic structure that is mapped to native objects by the backend.
pub struct AccessibilityNode {
pub mut:
	id       int // Unique identifier for this node
	role     AccessibilityRole
	rect     gg.Rect // Bounding box in window coordinates (pixels)
	text     string  // Content to be read by the screen reader
	children []int   // IDs of child nodes
	parent   int = -1 // ID of parent node (-1 if root)

	// State
	is_focused  bool
	is_selected bool
}
