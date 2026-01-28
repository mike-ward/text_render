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

// get_char_rect returns the bounding box for a specific character byte index.
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

	// 2. Resolve X using Pango (requires recalculation or stored PangoLayout... wait)
	// We don't have the PangoLayout stored in V struct Layout (it's transient).
	// So we must rely on our cached data (CharRects).

	// Linear search within the line's range
	line_end := target_line.start_index + target_line.length
	mut closest_char_idx := target_line.start_index
	mut min_dist_x := f32(1e9)

	// If x is before line start
	if x < target_line.rect.x {
		return target_line.start_index
	}
	// If x is after line end
	if x > target_line.rect.x + target_line.rect.width {
		// Return end of line (but we need to know if it's newline char or not)
		// Usually target_line.start_index + target_line.length
		return line_end
	}

	// Scan chars in this line using O(1) index lookup
	for i in target_line.start_index .. line_end {
		rect_idx := l.char_rect_by_index[i] or { continue }
		cr := l.char_rects[rect_idx]
		char_mid_x := cr.rect.x + cr.rect.width / 2
		dist := math.abs(x - char_mid_x)
		if dist < min_dist_x {
			min_dist_x = dist
			closest_char_idx = i
		}
	}

	// Edge case: if we are closer to the right edge of the last char
	// we should probably return index + char_len?
	// Simplified: return index of char center closest to mouse.
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
