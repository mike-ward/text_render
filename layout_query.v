module vglyph

import gg
import math

// hit_test_rect returns the bounding box of the character at (x, y) relative to the layout origin.
// Returns none if no character is found close enough.
pub fn (l Layout) hit_test_rect(x f32, y f32) ?gg.Rect {
	for cr in l.char_rects {
		if x >= cr.rect.x && x <= cr.rect.x + cr.rect.width && y >= cr.rect.y
			&& y <= cr.rect.y + cr.rect.height {
			return cr.rect
		}
	}
	return none
}

// get_char_rect returns the bounding box for a character at byte index.
// Returns none if index is not a valid character position or out of bounds.
pub fn (l Layout) get_char_rect(index int) ?gg.Rect {
	rect_idx := l.char_rect_by_index[index] or { return none }
	return l.char_rects[rect_idx].rect
}

// hit_test returns the byte index of the character at (x, y) relative to origin.
// Returns -1 if no character is found.
//
// Algorithm:
// Linear search (O(N)) over baked char rects.
// Trade-offs:
// - Efficiency: Faster than spatial structures for typical N < 1000.
// - Accuracy: Returns first matching index (logical order).
pub fn (l Layout) hit_test(x f32, y f32) int {
	// Simple linear search.
	// We could optimize with spatial partitioning if needed.
	for cr in l.char_rects {
		if x >= cr.rect.x && x <= cr.rect.x + cr.rect.width && y >= cr.rect.y
			&& y <= cr.rect.y + cr.rect.height {
			return cr.index
		}
	}
	return -1
}

// get_closest_offset returns the byte index of the character closest to (x, y).
// Handles clicks outside bounds (returns nearest edge/line).
// Only returns valid cursor positions (won't return indices in middle of multi-byte chars).
pub fn (l Layout) get_closest_offset(x f32, y f32) int {
	if l.lines.len == 0 {
		return 0
	}

	// 1. Find the closest line vertically
	mut closest_line_idx := 0
	mut min_dist_y := f32(1e9)

	for i, line in l.lines {
		// Check containment or distance
		// Simple distance to vertical center of line
		line_mid_y := line.rect.y + line.rect.height / 2
		dist := match true {
			y >= line.rect.y && y <= line.rect.y + line.rect.height { 0.0 } // Inside
			else { math.abs(y - line_mid_y) }
		}

		if dist < min_dist_y {
			min_dist_y = dist
			closest_line_idx = i
		}
	}

	target_line := l.lines[closest_line_idx]

	// 2. Resolve X using cached CharRects
	// Only consider indices that have char_rects (valid cursor positions)

	// Linear search within the line's range
	line_end := target_line.start_index + target_line.length
	mut closest_char_idx := target_line.start_index
	mut min_dist_x := f32(1e9)
	mut found_any := false

	// Scan chars in this line using O(1) index lookup
	for i in target_line.start_index .. line_end {
		rect_idx := l.char_rect_by_index[i] or { continue }
		cr := l.char_rects[rect_idx]
		char_mid_x := cr.rect.x + cr.rect.width / 2
		dist := math.abs(x - char_mid_x)
		if dist < min_dist_x {
			min_dist_x = dist
			closest_char_idx = i
			found_any = true
		}
	}

	// If x is past the last character on the line, return line_end
	if found_any {
		// Find the actual last character on this line (rightmost)
		mut last_char_right := f32(-1e9)
		for i in target_line.start_index .. line_end {
			rect_idx := l.char_rect_by_index[i] or { continue }
			cr := l.char_rects[rect_idx]
			char_right := cr.rect.x + cr.rect.width
			if char_right > last_char_right {
				last_char_right = char_right
			}
		}

		// If click is past the rightmost character's edge
		if last_char_right > 0 && x > last_char_right {
			// Check if line_end is a valid cursor position
			if _ := l.log_attr_by_index[line_end] {
				return line_end
			}
		}
	}

	// If no chars found in range (empty line), return line start
	if !found_any {
		return target_line.start_index
	}

	return closest_char_idx
}

// get_selection_rects returns a list of rectangles covering the text range [start, end).
pub fn (l Layout) get_selection_rects(start int, end int) []gg.Rect {
	if start >= end || l.lines.len == 0 {
		return []gg.Rect{}
	}

	mut rects := []gg.Rect{}
	mut s := start
	mut e := end

	// Clamp
	if s < 0 {
		s = 0
	}
	// Max index? approximation
	// if e > max_len { ... }

	for line in l.lines {
		line_end := line.start_index + line.length

		// Check intersection
		// Range 1: [line.start, line_end)
		// Range 2: [s, e)

		overlap_start := if s > line.start_index { s } else { line.start_index }
		overlap_end := if e < line_end { e } else { line_end }

		if overlap_start < overlap_end {
			// Calculate visual rect for this overlap using O(1) index lookup
			mut min_x := f32(1e9)
			mut max_x := f32(-1e9)
			mut found := false

			for i in overlap_start .. overlap_end {
				rect_idx := l.char_rect_by_index[i] or { continue }
				cr := l.char_rects[rect_idx]
				if cr.rect.x < min_x {
					min_x = cr.rect.x
				}
				if cr.rect.x + cr.rect.width > max_x {
					max_x = cr.rect.x + cr.rect.width
				}
				found = true
			}

			if found {
				rects << gg.Rect{
					x:      min_x
					y:      line.rect.y
					width:  max_x - min_x
					height: line.rect.height
				}
			}
		}
	}
	return rects
}

// get_font_name_at_index returns the family name of the font used to render
// the character at the given byte index.
pub fn (l Layout) get_font_name_at_index(index int) string {
	for item in l.items {
		if index >= item.start_index && index < item.start_index + item.length {
			if item.ft_face != unsafe { nil } {
				return unsafe { cstring_to_vstring(item.ft_face.family_name) }
			}
		}
	}
	return 'Unknown'
}

// get_cursor_pos returns the geometry for rendering a cursor at the given byte index.
// Returns none if index is not a valid cursor position.
//
// Algorithm:
// 1. Check if byte_index is a valid cursor position (exists in log_attr_by_index)
// 2. Try exact char_rect lookup for index
// 3. If at line end, use line rect right edge
// 4. Return x (left edge of char or line end), y (line top), height (line height)
//
// Note: This uses cached char_rects/lines. For precise bidi cursor positioning,
// a future version could store cursor_pos during layout build from Pango.
pub fn (l Layout) get_cursor_pos(byte_index int) ?CursorPosition {
	// Bounds check - must be a valid cursor position
	if byte_index < 0 {
		return none
	}

	// Check if this is a valid cursor position
	// Must exist in log_attr_by_index mapping
	attr_idx := l.log_attr_by_index[byte_index] or {
		// Special case: byte_index 0 is always valid even if not in mapping
		if byte_index != 0 {
			return none
		}
		-1 // Will be handled below
	}
	// Verify it's actually marked as cursor position (unless it's position 0)
	if attr_idx >= 0 && attr_idx < l.log_attrs.len {
		if !l.log_attrs[attr_idx].is_cursor_position {
			return none
		}
	}

	// Try exact char rect lookup
	if rect := l.get_char_rect(byte_index) {
		return CursorPosition{
			x:      rect.x
			y:      rect.y
			height: rect.height
		}
	}

	// Fallback: find containing line (for line end positions)
	for line in l.lines {
		line_end := line.start_index + line.length
		if byte_index >= line.start_index && byte_index <= line_end {
			if byte_index == line_end {
				// At end of line - cursor at right edge
				return CursorPosition{
					x:      line.rect.x + line.rect.width
					y:      line.rect.y
					height: line.rect.height
				}
			}
			// Index is at line start (no char rect but valid position)
			if byte_index == line.start_index {
				return CursorPosition{
					x:      line.rect.x
					y:      line.rect.y
					height: line.rect.height
				}
			}
		}
	}

	// Ultimate fallback for position 0
	if byte_index == 0 && l.lines.len > 0 {
		first_line := l.lines[0]
		return CursorPosition{
			x:      first_line.rect.x
			y:      first_line.rect.y
			height: first_line.rect.height
		}
	}

	return none
}

// get_log_attr returns the LogAttr for the given byte index, or none if not found.
fn (l Layout) get_log_attr(byte_index int) ?LogAttr {
	attr_idx := l.log_attr_by_index[byte_index] or { return none }
	if attr_idx < 0 || attr_idx >= l.log_attrs.len {
		return none
	}
	return l.log_attrs[attr_idx]
}

// get_valid_cursor_positions returns sorted list of byte indices that are valid cursor positions.
pub fn (l Layout) get_valid_cursor_positions() []int {
	mut positions := []int{cap: l.log_attr_by_index.len}
	for byte_idx, attr_idx in l.log_attr_by_index {
		if attr_idx >= 0 && attr_idx < l.log_attrs.len {
			if l.log_attrs[attr_idx].is_cursor_position {
				positions << byte_idx
			}
		}
	}
	positions.sort()
	return positions
}

// move_cursor_left returns the byte index of the previous valid cursor position.
// Returns current index if already at start. Respects grapheme clusters (won't land inside emoji).
pub fn (l Layout) move_cursor_left(byte_index int) int {
	if byte_index <= 0 || l.log_attrs.len == 0 {
		return 0
	}
	// Get all valid cursor positions and find the one before current
	positions := l.get_valid_cursor_positions()
	for i := positions.len - 1; i >= 0; i-- {
		if positions[i] < byte_index {
			return positions[i]
		}
	}
	return 0
}

// move_cursor_right returns the byte index of the next valid cursor position.
// Returns current index if already at end. Respects grapheme clusters.
pub fn (l Layout) move_cursor_right(byte_index int) int {
	if l.log_attrs.len == 0 {
		return byte_index
	}
	// Get all valid cursor positions and find the one after current
	positions := l.get_valid_cursor_positions()
	for pos in positions {
		if pos > byte_index {
			return pos
		}
	}
	// Return last position if at or past end
	if positions.len > 0 {
		return positions[positions.len - 1]
	}
	return byte_index
}

// get_word_starts returns sorted list of byte indices that are word starts.
fn (l Layout) get_word_starts() []int {
	mut starts := []int{cap: l.log_attr_by_index.len}
	for byte_idx, attr_idx in l.log_attr_by_index {
		if attr_idx >= 0 && attr_idx < l.log_attrs.len {
			if l.log_attrs[attr_idx].is_word_start {
				starts << byte_idx
			}
		}
	}
	starts.sort()
	return starts
}

// move_cursor_word_left returns the byte index of the previous word start.
// Skips to word boundary, not just cursor position.
pub fn (l Layout) move_cursor_word_left(byte_index int) int {
	if byte_index <= 0 || l.log_attrs.len == 0 {
		return 0
	}
	// Get all word starts and find the one before current
	starts := l.get_word_starts()
	for i := starts.len - 1; i >= 0; i-- {
		if starts[i] < byte_index {
			return starts[i]
		}
	}
	return 0
}

// move_cursor_word_right returns the byte index of the next word start.
pub fn (l Layout) move_cursor_word_right(byte_index int) int {
	if l.log_attrs.len == 0 {
		return byte_index
	}
	// Get all word starts and find the one after current
	starts := l.get_word_starts()
	for start in starts {
		if start > byte_index {
			return start
		}
	}
	// Return last valid cursor position if no more word starts
	positions := l.get_valid_cursor_positions()
	if positions.len > 0 {
		return positions[positions.len - 1]
	}
	return byte_index
}

// move_cursor_line_start returns the byte index of the start of the current line.
pub fn (l Layout) move_cursor_line_start(byte_index int) int {
	for line in l.lines {
		line_end := line.start_index + line.length
		if byte_index >= line.start_index && byte_index <= line_end {
			return line.start_index
		}
	}
	// Fallback: return 0
	return 0
}

// move_cursor_line_end returns the byte index of the end of the current line.
pub fn (l Layout) move_cursor_line_end(byte_index int) int {
	for line in l.lines {
		line_end := line.start_index + line.length
		if byte_index >= line.start_index && byte_index <= line_end {
			return line_end
		}
	}
	// Fallback: return byte_index unchanged
	return byte_index
}

// move_cursor_up returns byte index on previous line at similar x position.
// preferred_x is the x coordinate to try to maintain (pass -1 to use cursor's current x).
pub fn (l Layout) move_cursor_up(byte_index int, preferred_x f32) int {
	if l.lines.len == 0 {
		return byte_index
	}

	// Find current line index
	mut current_line_idx := -1
	mut target_x := preferred_x
	for i, line in l.lines {
		line_end := line.start_index + line.length
		if byte_index >= line.start_index && byte_index <= line_end {
			current_line_idx = i
			// If no preferred_x, use current cursor x
			if target_x < 0 {
				if pos := l.get_cursor_pos(byte_index) {
					target_x = pos.x
				} else {
					target_x = line.rect.x
				}
			}
			break
		}
	}

	if current_line_idx <= 0 {
		// Already on first line or not found
		return byte_index
	}

	// Find closest char on previous line
	prev_line := l.lines[current_line_idx - 1]
	return l.find_closest_index_in_line(prev_line, target_x)
}

// move_cursor_down returns byte index on next line at similar x position.
pub fn (l Layout) move_cursor_down(byte_index int, preferred_x f32) int {
	if l.lines.len == 0 {
		return byte_index
	}

	// Find current line index
	mut current_line_idx := -1
	mut target_x := preferred_x
	for i, line in l.lines {
		line_end := line.start_index + line.length
		if byte_index >= line.start_index && byte_index <= line_end {
			current_line_idx = i
			if target_x < 0 {
				if pos := l.get_cursor_pos(byte_index) {
					target_x = pos.x
				} else {
					target_x = line.rect.x
				}
			}
			break
		}
	}

	if current_line_idx < 0 || current_line_idx >= l.lines.len - 1 {
		// Not found or already on last line
		return byte_index
	}

	// Find closest char on next line
	next_line := l.lines[current_line_idx + 1]
	return l.find_closest_index_in_line(next_line, target_x)
}

// get_word_at_index returns (start, end) byte indices for word containing index.
// Uses Pango word boundaries. Returns (index, index) if not in a word.
pub fn (l Layout) get_word_at_index(byte_index int) (int, int) {
	if l.log_attrs.len == 0 {
		return byte_index, byte_index
	}

	// Get all word starts and ends
	word_starts := l.get_word_starts()
	word_ends := l.get_word_ends()

	// Find word start: largest word_start <= byte_index
	mut start := byte_index
	for i := word_starts.len - 1; i >= 0; i-- {
		if word_starts[i] <= byte_index {
			start = word_starts[i]
			break
		}
	}

	// Find word end: smallest word_end >= byte_index
	mut end := byte_index
	for we in word_ends {
		if we >= byte_index {
			end = we
			break
		}
	}

	// If start > end (click on whitespace), snap to nearest word
	if start > end {
		// Find closest boundary
		mut nearest_start := -1
		mut nearest_end := -1

		// Find nearest word start after byte_index
		for ws in word_starts {
			if ws > byte_index {
				nearest_start = ws
				break
			}
		}

		// Find nearest word end before byte_index
		for i := word_ends.len - 1; i >= 0; i-- {
			if word_ends[i] < byte_index {
				nearest_end = word_ends[i]
				break
			}
		}

		// Pick the closer one
		dist_to_start := if nearest_start >= 0 { nearest_start - byte_index } else { 1000000 }
		dist_to_end := if nearest_end >= 0 { byte_index - nearest_end } else { 1000000 }

		if dist_to_start < dist_to_end && nearest_start >= 0 {
			// Snap to next word
			start = nearest_start
			for we in word_ends {
				if we >= start {
					end = we
					break
				}
			}
		} else if nearest_end >= 0 {
			// Snap to previous word
			end = nearest_end
			for i := word_starts.len - 1; i >= 0; i-- {
				if word_starts[i] <= end {
					start = word_starts[i]
					break
				}
			}
		}
	}

	// Ensure valid range
	if start > end {
		return byte_index, byte_index
	}
	return start, end
}

// get_word_ends returns sorted list of byte indices that are word ends.
fn (l Layout) get_word_ends() []int {
	mut ends := []int{cap: l.log_attr_by_index.len}
	for byte_idx, attr_idx in l.log_attr_by_index {
		if attr_idx >= 0 && attr_idx < l.log_attrs.len {
			if l.log_attrs[attr_idx].is_word_end {
				ends << byte_idx
			}
		}
	}
	ends.sort()
	return ends
}

// get_paragraph_at_index returns (start, end) byte indices for paragraph containing index.
// Paragraph = text between empty lines (consecutive newlines \n\n).
// Returns (0, text_len) if no empty lines found.
pub fn (l Layout) get_paragraph_at_index(byte_index int, text string) (int, int) {
	if text.len == 0 {
		return 0, 0
	}

	// Clamp byte_index
	idx := if byte_index < 0 {
		0
	} else if byte_index > text.len {
		text.len
	} else {
		byte_index
	}

	// Scan backwards for paragraph start (after \n\n or beginning)
	mut para_start := 0
	for i := idx - 1; i >= 1; i-- {
		if text[i] == `\n` && text[i - 1] == `\n` {
			para_start = i + 1
			break
		}
	}

	// Scan forwards for paragraph end (before \n\n or text end)
	mut para_end := text.len
	for i in idx .. text.len - 1 {
		if text[i] == `\n` && text[i + 1] == `\n` {
			para_end = i
			break
		}
	}

	return para_start, para_end
}

// find_closest_index_in_line returns the byte index closest to target_x within the given line.
fn (l Layout) find_closest_index_in_line(line Line, target_x f32) int {
	line_end := line.start_index + line.length
	mut closest_idx := line.start_index
	mut min_dist := f32(1e9)

	for i in line.start_index .. line_end {
		rect_idx := l.char_rect_by_index[i] or { continue }
		cr := l.char_rects[rect_idx]
		char_mid_x := cr.rect.x + cr.rect.width / 2
		dist := math.abs(target_x - char_mid_x)
		if dist < min_dist {
			min_dist = dist
			closest_idx = i
		}
	}

	// Check if closer to end of line
	end_x := line.rect.x + line.rect.width
	if math.abs(target_x - end_x) < min_dist {
		return line_end
	}

	return closest_idx
}
