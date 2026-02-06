module vglyph

import gg

// CompositionPhase tracks IME composition lifecycle.
// none: no active composition. composing: preedit text being edited by IME.
pub enum CompositionPhase {
	none      // No active composition
	composing // Preedit text being edited
}

// ClauseStyle differentiates underline thickness for multi-clause IME
pub enum ClauseStyle {
	raw       // Unconverted input (thin underline)
	converted // Converted text (thin underline)
	selected  // Currently selected for conversion (thick underline)
}

// Clause represents a segment in multi-clause CJK composition
pub struct Clause {
pub:
	start  int // Byte offset within preedit_text
	length int // Byte length of clause
	style  ClauseStyle
}

// CompositionState tracks IME composition for preedit display and candidate positioning.
// Per CONTEXT.md decisions:
// - Single underline for preedit (thick for selected clause)
// - Cursor visible inside composition for navigation
// - Focus loss: auto-commit; Escape: cancel; Click outside: commit then move
pub struct CompositionState {
pub mut:
	phase           CompositionPhase
	preedit_text    string   // Current composition string
	preedit_start   int      // Byte offset in document where preedit inserted
	cursor_offset   int      // Cursor position within preedit (0 = start)
	clauses         []Clause // Segment info for multi-segment CJK input
	selected_clause int      // Currently selected clause index (-1 if none)
}

// is_composing returns true if composition is active
pub fn (cs &CompositionState) is_composing() bool {
	return cs.phase == .composing
}

// start begins composition at document cursor position
pub fn (mut cs CompositionState) start(cursor_pos int) {
	cs.phase = .composing
	cs.preedit_start = cursor_pos
	cs.preedit_text = ''
	cs.cursor_offset = 0
	cs.clauses.clear()
	cs.selected_clause = -1
}

// set_marked_text updates preedit from IME (called by native bridge).
// cursor_in_preedit is byte offset within preedit where cursor should be.
pub fn (mut cs CompositionState) set_marked_text(text string, cursor_in_preedit int) {
	cs.preedit_text = text
	cs.cursor_offset = cursor_in_preedit
}

// set_clauses updates clause segmentation from IME attributes
pub fn (mut cs CompositionState) set_clauses(clauses []Clause, selected int) {
	cs.clauses = clauses
	cs.selected_clause = selected
}

// commit finalizes composition, returns text to insert.
// Resets state to none phase.
pub fn (mut cs CompositionState) commit() string {
	result := cs.preedit_text
	cs.reset()
	return result
}

// reset discards composition without inserting text.
// Per CONTEXT.md: Escape cancels composition entirely.
pub fn (mut cs CompositionState) reset() {
	cs.phase = .none
	cs.preedit_text = ''
	cs.preedit_start = 0
	cs.cursor_offset = 0
	cs.clauses.clear()
	cs.selected_clause = -1
}

// get_document_cursor_pos returns absolute cursor position in document.
// Used for cursor rendering during composition.
pub fn (cs &CompositionState) get_document_cursor_pos() int {
	return cs.preedit_start + cs.cursor_offset
}

// get_preedit_end returns byte offset where preedit ends in document
pub fn (cs &CompositionState) get_preedit_end() int {
	return cs.preedit_start + cs.preedit_text.len
}

// get_composition_bounds returns bounding rect covering entire preedit text.
// Per CONTEXT.md: "API reports full composition bounds (rect covering entire preedit)"
// Used by native bridge for firstRectForCharacterRange to position candidate window.
// Returns none if not composing.
pub fn (cs &CompositionState) get_composition_bounds(layout Layout) ?gg.Rect {
	if !cs.is_composing() || cs.preedit_text.len == 0 {
		return none
	}

	preedit_end := cs.get_preedit_end()
	rects := layout.get_selection_rects(cs.preedit_start, preedit_end)

	if rects.len == 0 {
		return none
	}

	// Return bounding rect of all selection rects
	mut min_x := f32(1e9)
	mut min_y := f32(1e9)
	mut max_x := f32(-1e9)
	mut max_y := f32(-1e9)

	for r in rects {
		if r.x < min_x {
			min_x = r.x
		}
		if r.y < min_y {
			min_y = r.y
		}
		if r.x + r.width > max_x {
			max_x = r.x + r.width
		}
		if r.y + r.height > max_y {
			max_y = r.y + r.height
		}
	}

	return gg.Rect{
		x:      min_x
		y:      min_y
		width:  max_x - min_x
		height: max_y - min_y
	}
}

// ClauseRects holds clause index, rects, and style for rendering
pub struct ClauseRects {
pub:
	clause_idx int
	rects      []gg.Rect
	style      ClauseStyle
}

// get_clause_rects returns selection rects for each clause (for underline rendering).
// Returns array of (clause_index, rects) pairs.
pub fn (cs &CompositionState) get_clause_rects(layout Layout) []ClauseRects {
	mut result := []ClauseRects{}

	if !cs.is_composing() {
		return result
	}

	// If no explicit clauses, treat entire preedit as single raw clause
	if cs.clauses.len == 0 && cs.preedit_text.len > 0 {
		rects := layout.get_selection_rects(cs.preedit_start, cs.get_preedit_end())
		if rects.len > 0 {
			result << ClauseRects{
				clause_idx: 0
				rects:      rects
				style:      .raw
			}
		}
		return result
	}

	for i, clause in cs.clauses {
		clause_start := cs.preedit_start + clause.start
		clause_end := clause_start + clause.length
		rects := layout.get_selection_rects(clause_start, clause_end)
		if rects.len > 0 {
			result << ClauseRects{
				clause_idx: i
				rects:      rects
				style:      clause.style
			}
		}
	}

	return result
}

// DeadKeyState tracks pending dead key for accent composition.
// Per CONTEXT.md decisions:
// - Show dead key as placeholder with underline
// - Invalid combination inserts both separately
// - Escape cancels pending dead key
pub struct DeadKeyState {
pub mut:
	pending     ?rune // Dead key waiting for combination (none if not pending)
	pending_pos int   // Document position where dead key was typed
}

// has_pending returns true if dead key is waiting for combination
pub fn (dks &DeadKeyState) has_pending() bool {
	return dks.pending != none
}

// start_dead_key records a dead key press
pub fn (mut dks DeadKeyState) start_dead_key(dead rune, pos int) {
	dks.pending = dead
	dks.pending_pos = pos
}

// clear cancels pending dead key (Escape)
pub fn (mut dks DeadKeyState) clear() {
	dks.reset()
}

// reset zeros all fields
pub fn (mut dks DeadKeyState) reset() {
	dks.pending = none
	dks.pending_pos = 0
}

// try_combine attempts to combine pending dead key with base character.
// Returns (result_string, was_combined):
// - If combined successfully: ("è", true) for ` + e
// - If invalid combination: ("`x", false) for ` + x (inserts both)
// - If no pending: ("", false)
pub fn (mut dks DeadKeyState) try_combine(base rune) (string, bool) {
	dead := dks.pending or { return '', false }
	dks.reset()

	if combined := combine_dead_key(dead, base) {
		return combined.str(), true
	}
	// Invalid combination: insert both per CONTEXT.md
	return dead.str() + base.str(), false
}

// is_dead_key returns true if rune is a dead key (accent starter)
pub fn is_dead_key(r rune) bool {
	return r in [`\``, `'`, `^`, `~`, `"`, `:`, `,`]
}

// handle_marked_text processes setMarkedText from IME overlay.
// Called from C callback, updates preedit_text and cursor_offset.
// Starts composition if not already active.
pub fn (mut cs CompositionState) handle_marked_text(text string, cursor_in_preedit int,
	document_cursor int) {
	if !cs.is_composing() {
		cs.start(document_cursor)
	}
	cs.set_marked_text(text, cursor_in_preedit)
}

// handle_insert_text processes insertText from IME overlay.
// Commits composition and returns text to insert into document.
// Returns empty string if not composing.
pub fn (mut cs CompositionState) handle_insert_text(text string) string {
	if cs.is_composing() {
		cs.reset() // Clear composition state
	}
	return text // Return committed text for insertion
}

// handle_unmark_text processes unmarkText from IME overlay.
// Cancels composition without committing any text.
pub fn (mut cs CompositionState) handle_unmark_text() {
	cs.reset()
}

// handle_clause processes clause info from IME overlay.
// Accumulates clauses; call clear_clauses before enumeration.
pub fn (mut cs CompositionState) handle_clause(start int, length int, style int) {
	clause_style := match style {
		2 { ClauseStyle.selected }
		1 { ClauseStyle.converted }
		else { ClauseStyle.raw }
	}
	cs.clauses << Clause{
		start:  start
		length: length
		style:  clause_style
	}
}

// clear_clauses resets clause array for fresh enumeration
pub fn (mut cs CompositionState) clear_clauses() {
	cs.clauses.clear()
	cs.selected_clause = -1
}

// combine_dead_key returns combined character or none if invalid
fn combine_dead_key(dead rune, base rune) ?rune {
	// Grave accent combinations
	if dead == `\`` {
		match base {
			`a` { return 0x00E0 } // à
			`e` { return 0x00E8 } // è
			`i` { return 0x00EC } // ì
			`o` { return 0x00F2 } // ò
			`u` { return 0x00F9 } // ù
			`A` { return 0x00C0 } // À
			`E` { return 0x00C8 } // È
			`I` { return 0x00CC } // Ì
			`O` { return 0x00D2 } // Ò
			`U` { return 0x00D9 } // Ù
			else {}
		}
	}
	// Acute accent combinations
	if dead == `'` {
		match base {
			`a` { return 0x00E1 } // á
			`e` { return 0x00E9 } // é
			`i` { return 0x00ED } // í
			`o` { return 0x00F3 } // ó
			`u` { return 0x00FA } // ú
			`A` { return 0x00C1 } // Á
			`E` { return 0x00C9 } // É
			`I` { return 0x00CD } // Í
			`O` { return 0x00D3 } // Ó
			`U` { return 0x00DA } // Ú
			else {}
		}
	}
	// Circumflex combinations
	if dead == `^` {
		match base {
			`a` { return 0x00E2 } // â
			`e` { return 0x00EA } // ê
			`i` { return 0x00EE } // î
			`o` { return 0x00F4 } // ô
			`u` { return 0x00FB } // û
			`A` { return 0x00C2 } // Â
			`E` { return 0x00CA } // Ê
			`I` { return 0x00CE } // Î
			`O` { return 0x00D4 } // Ô
			`U` { return 0x00DB } // Û
			else {}
		}
	}
	// Tilde combinations
	if dead == `~` {
		match base {
			`a` { return 0x00E3 } // ã
			`n` { return 0x00F1 } // ñ
			`o` { return 0x00F5 } // õ
			`A` { return 0x00C3 } // Ã
			`N` { return 0x00D1 } // Ñ
			`O` { return 0x00D5 } // Õ
			else {}
		}
	}
	// Diaeresis (umlaut) combinations
	if dead == `"` || dead == `:` {
		match base {
			`a` { return 0x00E4 } // ä
			`e` { return 0x00EB } // ë
			`i` { return 0x00EF } // ï
			`o` { return 0x00F6 } // ö
			`u` { return 0x00FC } // ü
			`y` { return 0x00FF } // ÿ
			`A` { return 0x00C4 } // Ä
			`E` { return 0x00CB } // Ë
			`I` { return 0x00CF } // Ï
			`O` { return 0x00D6 } // Ö
			`U` { return 0x00DC } // Ü
			else {}
		}
	}
	// Cedilla combinations
	if dead == `,` {
		match base {
			`c` { return 0x00E7 } // ç
			`C` { return 0x00C7 } // Ç
			else {}
		}
	}
	return none
}
