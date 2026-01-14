module vglyph

import gg
import strings

// AccessibilityManager manages the lifecycle of the accessibility tree.
pub struct AccessibilityManager {
mut:
	backend     AccessibilityBackend
	nodes       map[int]AccessibilityNode
	next_id     int = 1
	root_id     int = 1
	is_dirty    bool
}

pub fn new_accessibility_manager() &AccessibilityManager {
	backend := new_accessibility_backend()
	return &AccessibilityManager{
		backend: backend
		nodes:   map[int]AccessibilityNode{}
	}
}

// update_layout takes a Layout and converts it into accessibility nodes,
// essentially "publishing" the visual structure to the screen reader.
pub fn (mut am AccessibilityManager) update_layout(l Layout, origin_x f32, origin_y f32) {
	am.reset()

	// Create Root Node (Window/Container)
	am.root_id = am.next_node_id()
	mut root := AccessibilityNode{
		id:   am.root_id
		role: .container
		rect: gg.Rect{x: origin_x, y: origin_y, width: l.width, height: l.height}
		text: "Text Content"
	}
	am.nodes[am.root_id] = root

	// Process Lines
	for line in l.lines {
		// Only create nodes for lines that have content
		if line.length == 0 { continue }
		
		line_text := am.extract_text(l, line.start_index, line.length)
		
		id := am.next_node_id()
		node := AccessibilityNode{
			id:     id
			role:   .text
			rect:   gg.Rect{
				x: origin_x + line.rect.x, 
				y: origin_y + line.rect.y, 
				width: line.rect.width, 
				height: line.rect.height
			}
			text:   line_text
			parent: am.root_id
		}
		
		am.nodes[id] = node
		
		mut parent_node := am.nodes[am.root_id]
		parent_node.children << id
		am.nodes[am.root_id] = parent_node
	}

	am.push_updates()
}

fn (mut am AccessibilityManager) reset() {
	am.nodes.clear()
	am.next_id = 1
}

fn (mut am AccessibilityManager) next_node_id() int {
	id := am.next_id
	am.next_id++
	return id
}

fn (mut am AccessibilityManager) push_updates() {
	am.backend.update_tree(am.nodes, am.root_id)
}

// Helper to extract text string from layout items
fn (am AccessibilityManager) extract_text(l Layout, start int, length int) string {
	mut res := strings.new_builder(length)
	end := start + length
	
	for item in l.items {
		item_end := item.start_index + item.length
		
		if item_end <= start { continue }
		if item.start_index >= end { break }
		
		res.write_string(item.run_text)
	}
	return res.str()
}
