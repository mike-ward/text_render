module vglyph

import strings

// MutationResult contains the result of applying a text mutation.
// All mutation functions return this struct to enable undo support and change events.
pub struct MutationResult {
pub:
	new_text     string // Result of applying mutation
	cursor_pos   int    // New cursor position after mutation
	deleted_text string // Text removed (empty for insert)
	range_start  int    // Start of affected range (for change event)
	range_end    int    // End of affected range (for change event)
}

// delete_backward removes one grapheme cluster before cursor (Backspace).
// Uses layout.move_cursor_left to find grapheme boundary.
pub fn delete_backward(text string, layout Layout, cursor_ int) MutationResult {
	cursor := clamp_index(cursor_, text.len)
	if cursor == 0 {
		return MutationResult{
			new_text:   text
			cursor_pos: 0
		}
	}

	// Find previous valid cursor position (grapheme boundary)
	prev_pos := layout.move_cursor_left(cursor)

	// Build new string
	mut sb := strings.new_builder(text.len)
	sb.write_string(text[..prev_pos])
	sb.write_string(text[cursor..])

	return MutationResult{
		new_text:     sb.str()
		cursor_pos:   prev_pos
		deleted_text: text[prev_pos..cursor]
		range_start:  prev_pos
		range_end:    cursor
	}
}

// delete_forward removes one grapheme cluster after cursor (Delete key).
// Uses layout.move_cursor_right to find grapheme boundary.
pub fn delete_forward(text string, layout Layout, cursor int) MutationResult {
	// Find next valid cursor position (grapheme boundary)
	next_pos := layout.move_cursor_right(cursor)

	// At text end - nothing to delete
	if next_pos == cursor {
		return MutationResult{
			new_text:   text
			cursor_pos: cursor
		}
	}

	// Build new string
	mut sb := strings.new_builder(text.len)
	sb.write_string(text[..cursor])
	sb.write_string(text[next_pos..])

	return MutationResult{
		new_text:     sb.str()
		cursor_pos:   cursor
		deleted_text: text[cursor..next_pos]
		range_start:  cursor
		range_end:    next_pos
	}
}

// insert_text inserts a string at cursor position.
// Does not handle selection - use insert_replacing_selection for that.
pub fn insert_text(text string, cursor_ int, insert string) MutationResult {
	cursor := clamp_index(cursor_, text.len)
	// Build new string
	mut sb := strings.new_builder(text.len + insert.len)
	sb.write_string(text[..cursor])
	sb.write_string(insert)
	sb.write_string(text[cursor..])

	return MutationResult{
		new_text:    sb.str()
		cursor_pos:  cursor + insert.len
		range_start: cursor
		range_end:   cursor + insert.len
	}
}

// delete_to_word_boundary removes text from cursor to previous word boundary (Option+Backspace).
// Per user decision: "to boundary, not whole word"
pub fn delete_to_word_boundary(text string, layout Layout, cursor int) MutationResult {
	if cursor == 0 {
		return MutationResult{
			new_text:   text
			cursor_pos: 0
		}
	}

	// Find word start via layout
	word_start := layout.move_cursor_word_left(cursor)

	// Build new string
	mut sb := strings.new_builder(text.len)
	sb.write_string(text[..word_start])
	sb.write_string(text[cursor..])

	return MutationResult{
		new_text:     sb.str()
		cursor_pos:   word_start
		deleted_text: text[word_start..cursor]
		range_start:  word_start
		range_end:    cursor
	}
}

// delete_to_line_start removes text from cursor to line start (Cmd+Backspace).
pub fn delete_to_line_start(text string, layout Layout, cursor int) MutationResult {
	// Find line start via layout
	line_start := layout.move_cursor_line_start(cursor)

	// Nothing to delete if already at line start
	if line_start == cursor {
		return MutationResult{
			new_text:   text
			cursor_pos: cursor
		}
	}

	// Build new string
	mut sb := strings.new_builder(text.len)
	sb.write_string(text[..line_start])
	sb.write_string(text[cursor..])

	return MutationResult{
		new_text:     sb.str()
		cursor_pos:   line_start
		deleted_text: text[line_start..cursor]
		range_start:  line_start
		range_end:    cursor
	}
}

// delete_to_line_end removes text from cursor to line end (Cmd+Delete).
pub fn delete_to_line_end(text string, layout Layout, cursor int) MutationResult {
	// Find line end via layout
	line_end := layout.move_cursor_line_end(cursor)

	// Nothing to delete if already at line end
	if line_end == cursor {
		return MutationResult{
			new_text:   text
			cursor_pos: cursor
		}
	}

	// Build new string
	mut sb := strings.new_builder(text.len)
	sb.write_string(text[..cursor])
	sb.write_string(text[line_end..])

	return MutationResult{
		new_text:     sb.str()
		cursor_pos:   cursor
		deleted_text: text[cursor..line_end]
		range_start:  cursor
		range_end:    line_end
	}
}

// delete_to_word_end removes text from cursor to next word boundary (Option+Delete).
pub fn delete_to_word_end(text string, layout Layout, cursor int) MutationResult {
	// Find word end via layout
	word_end := layout.move_cursor_word_right(cursor)

	// Nothing to delete if already at word end
	if word_end == cursor {
		return MutationResult{
			new_text:   text
			cursor_pos: cursor
		}
	}

	// Build new string
	mut sb := strings.new_builder(text.len)
	sb.write_string(text[..cursor])
	sb.write_string(text[word_end..])

	return MutationResult{
		new_text:     sb.str()
		cursor_pos:   cursor
		deleted_text: text[cursor..word_end]
		range_start:  cursor
		range_end:    word_end
	}
}

// delete_selection removes the text between cursor and anchor.
// Handles both cursor > anchor and cursor < anchor.
// Returns unchanged if no selection (cursor == anchor).
pub fn delete_selection(text string, cursor_ int, anchor_ int) MutationResult {
	cursor := clamp_index(cursor_, text.len)
	anchor := clamp_index(anchor_, text.len)
	// No selection - nothing to delete
	if cursor == anchor {
		return MutationResult{
			new_text:   text
			cursor_pos: cursor
		}
	}

	// Calculate selection bounds
	sel_start := if cursor < anchor { cursor } else { anchor }
	sel_end := if cursor < anchor { anchor } else { cursor }

	// Build new string
	mut sb := strings.new_builder(text.len - (sel_end - sel_start))
	sb.write_string(text[..sel_start])
	sb.write_string(text[sel_end..])

	return MutationResult{
		new_text:     sb.str()
		cursor_pos:   sel_start
		deleted_text: text[sel_start..sel_end]
		range_start:  sel_start
		range_end:    sel_start // Selection collapsed
	}
}

// insert_replacing_selection inserts text, replacing any selection.
// Per user decision: "Typing with selection active replaces selection (standard behavior)"
// Delegates to insert_text if no selection.
pub fn insert_replacing_selection(text string, cursor_ int, anchor_ int,
	insert string) MutationResult {
	cursor := clamp_index(cursor_, text.len)
	anchor := clamp_index(anchor_, text.len)
	// No selection - delegate to simple insert
	if cursor == anchor {
		return insert_text(text, cursor, insert)
	}

	// Calculate selection bounds
	sel_start := if cursor < anchor { cursor } else { anchor }
	sel_end := if cursor < anchor { anchor } else { cursor }

	// Build new string
	mut sb := strings.new_builder(text.len - (sel_end - sel_start) + insert.len)
	sb.write_string(text[..sel_start])
	sb.write_string(insert)
	sb.write_string(text[sel_end..])

	return MutationResult{
		new_text:     sb.str()
		cursor_pos:   sel_start + insert.len
		deleted_text: text[sel_start..sel_end]
		range_start:  sel_start
		range_end:    sel_start + insert.len
	}
}

// get_selected_text returns the text between cursor and anchor positions.
// Per user decision: "VGlyph copy API returns plain text only"
// Returns empty string if no selection (cursor == anchor).
pub fn get_selected_text(text string, cursor_ int, anchor_ int) string {
	cursor := clamp_index(cursor_, text.len)
	anchor := clamp_index(anchor_, text.len)
	if cursor == anchor {
		return ''
	}
	sel_start := if cursor < anchor { cursor } else { anchor }
	sel_end := if cursor < anchor { anchor } else { cursor }
	return text[sel_start..sel_end]
}

// cut_selection removes selected text and returns it for clipboard.
// Per user decision: "Cut returns selection text + deletes it"
// Returns empty string and unchanged text if no selection.
pub fn cut_selection(text string, cursor int, anchor int) (string, MutationResult) {
	if cursor == anchor {
		return '', MutationResult{
			new_text:   text
			cursor_pos: cursor
		}
	}
	cut_text := get_selected_text(text, cursor, anchor)
	result := delete_selection(text, cursor, anchor)
	return cut_text, result
}

// clamp_index restricts a byte index to [0, max].
fn clamp_index(val int, max int) int {
	if val < 0 {
		return 0
	}
	if val > max {
		return max
	}
	return val
}

// TextChange captures mutation info for undo support and change events.
// Per user decision: "Callback receives: range (start/end offset) + new text"
pub struct TextChange {
pub:
	range_start int    // Byte offset where change begins
	range_end   int    // Byte offset where change ends (in original text)
	new_text    string // Text that was inserted
	old_text    string // Text that was removed
}

// to_change converts a MutationResult to a TextChange for change events.
pub fn (m MutationResult) to_change(inserted string) TextChange {
	return TextChange{
		range_start: m.range_start
		range_end:   m.range_end
		new_text:    inserted
		old_text:    m.deleted_text
	}
}
