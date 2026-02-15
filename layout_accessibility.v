module vglyph

import gg
import accessibility

// update_accessibility takes a Layout and converts it into accessibility nodes,
// essentially "publishing" the visual structure to the screen reader.
// This accumulates nodes for the current frame. Call am.commit() to push changes.
pub fn update_accessibility(mut am accessibility.AccessibilityManager, l Layout, origin_x f32,
	origin_y f32) {
	// Process Lines
	for line in l.lines {
		// Only create nodes for lines that have content
		if line.length == 0 {
			continue
		}

		line_text := extract_text(l, line.start_index, line.length)

		rect := gg.Rect{
			x:      origin_x + line.rect.x
			y:      origin_y + line.rect.y
			width:  line.rect.width
			height: line.rect.height
		}

		am.add_text_node(line_text, rect)
	}
}

// extract_text returns the substring of the layout's original text
// for the byte range [start, start+length). Uses the stored text
// rather than per-item run_text which is only set in debug builds.
fn extract_text(l Layout, start int, length int) string {
	if start < 0 || length <= 0 {
		return ''
	}
	end := start + length
	if end > l.text.len {
		return ''
	}
	return l.text[start..end]
}
