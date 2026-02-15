module vglyph

import time
import strings

// OperationType classifies text mutations for coalescing rules.
// insert: text added without removal. delete: text removed. replace: text removed and added.
pub enum OperationType {
	insert
	delete
	replace
}

// UndoOperation stores inverse operation data for command pattern undo.
// Each operation captures all info needed to reverse and reapply a mutation.
pub struct UndoOperation {
pub:
	op_type OperationType
	// Cursor/anchor state before mutation (immutable once set)
	cursor_before int
	anchor_before int
pub mut:
	// Range affected in original text (mutable for coalescing)
	range_start int
	range_end   int
	// Text content for inverse operation (mutable for coalescing)
	deleted_text  string
	inserted_text string
	// Cursor/anchor state after mutation (mutable for coalescing)
	cursor_after int
	anchor_after int
}

// UndoManager tracks undo/redo stacks with history limit and operation coalescing.
// Per UNDO-01/02/03: dual stacks, 1s coalescing timeout, 100 operation limit.
pub struct UndoManager {
mut:
	undo_stack  []UndoOperation // Use array for easy history trimming
	redo_stack  []UndoOperation
	max_history int = 100 // UNDO-03 requirement
	// Coalescing state
	last_mutation_time  i64
	coalesce_timeout_ms i64 = 1000 // 1 second (split between Emacs 500ms, Google Docs 2s)
	coalescable_op      ?UndoOperation // Pending operation being built
}

// new_undo_manager creates UndoManager with specified history limit.
// Default limit is 100 operations per UNDO-03 requirement.
pub fn new_undo_manager(max_history int) UndoManager {
	return UndoManager{
		max_history: max_history
	}
}

// mutation_to_undo_op converts MutationResult to UndoOperation.
// Determines operation type based on deleted/inserted text lengths.
pub fn mutation_to_undo_op(result MutationResult, inserted string, cursor_before int,
	anchor_before int) UndoOperation {
	op_type := if result.deleted_text.len > 0 && inserted.len > 0 {
		OperationType.replace
	} else if inserted.len > 0 {
		OperationType.insert
	} else {
		OperationType.delete
	}

	return UndoOperation{
		op_type:       op_type
		range_start:   result.range_start
		range_end:     result.range_end
		deleted_text:  result.deleted_text
		inserted_text: inserted
		cursor_before: cursor_before
		cursor_after:  result.cursor_pos
		anchor_before: anchor_before
		anchor_after:  result.cursor_pos // Mutations clear selection
	}
}

// should_coalesce checks if new operation should merge with pending coalescable_op.
// Returns false if: no pending op, timeout exceeded, op_type differs, or non-adjacent ranges.
fn (um &UndoManager) should_coalesce(new_op UndoOperation, now i64) bool {
	coalescable := um.coalescable_op or { return false }

	// Timeout exceeded
	if now - um.last_mutation_time > um.coalesce_timeout_ms {
		return false
	}

	// Must be same operation type
	if coalescable.op_type != new_op.op_type {
		return false
	}

	// Replace operations never coalesce
	if new_op.op_type == .replace {
		return false
	}

	// For inserts: must be adjacent (typing forward)
	if new_op.op_type == .insert {
		if new_op.range_start != coalescable.range_end {
			return false
		}
	}

	// For deletes: must be adjacent (backspacing backward)
	if new_op.op_type == .delete {
		if new_op.range_end != coalescable.range_start {
			return false
		}
	}

	return true
}

// coalesce_operation merges new operation into pending coalescable_op.
// For insert: append text, update range_end. For delete: prepend text, update range_start.
fn (mut um UndoManager) coalesce_operation(new_op UndoOperation) {
	mut coalescable := um.coalescable_op or { return }

	if new_op.op_type == .insert {
		// Append to inserted text (typing forward)
		coalescable.inserted_text += new_op.inserted_text
		coalescable.range_end = new_op.range_end
		coalescable.cursor_after = new_op.cursor_after
		coalescable.anchor_after = new_op.anchor_after
	} else if new_op.op_type == .delete {
		// Prepend to deleted text (backspacing backward)
		coalescable.deleted_text = new_op.deleted_text + coalescable.deleted_text
		coalescable.range_start = new_op.range_start
		coalescable.cursor_after = new_op.cursor_after
		coalescable.anchor_after = new_op.anchor_after
	}

	um.coalescable_op = coalescable
}

// record_mutation tracks mutation for undo support.
// Handles coalescing, clears redo stack on new operation.
pub fn (mut um UndoManager) record_mutation(result MutationResult, inserted string,
	cursor_before int, anchor_before int) {
	now := time.now().unix_milli()
	new_op := mutation_to_undo_op(result, inserted, cursor_before, anchor_before)

	if um.should_coalesce(new_op, now) {
		um.coalesce_operation(new_op)
		um.last_mutation_time = now
	} else {
		// Flush pending coalescable_op if exists
		if coalescable := um.coalescable_op {
			um.undo_stack << coalescable
			um.coalescable_op = none
		}

		// Start new coalescable operation
		um.coalescable_op = new_op
		um.last_mutation_time = now

		// Clear redo stack on new operation
		um.redo_stack = []
	}
}

// flush_pending pushes pending coalescable_op to undo_stack.
// Enforces max_history limit by removing oldest operations.
pub fn (mut um UndoManager) flush_pending() {
	if coalescable := um.coalescable_op {
		// Enforce history limit before pushing
		if um.undo_stack.len >= um.max_history {
			// Remove oldest (first element)
			um.undo_stack = um.undo_stack[1..]
		}

		um.undo_stack << coalescable
		um.coalescable_op = none
	}
}

// undo reverses last operation, returns (new_text, cursor, anchor).
// Returns none if nothing to undo. Pushes operation to redo_stack.
pub fn (mut um UndoManager) undo(text string, cursor int, anchor int) ?(string, int, int) {
	// Flush pending first
	um.flush_pending()

	if um.undo_stack.len == 0 {
		return none
	}

	// Pop operation
	op := um.undo_stack[um.undo_stack.len - 1]
	um.undo_stack = um.undo_stack[..um.undo_stack.len - 1]

	// Bounds guard: ranges may be stale if text was modified
	// outside undo system.
	if op.range_start > text.len || op.range_end > text.len || op.range_start > op.range_end {
		return none
	}

	// Apply inverse operation
	mut sb := strings.new_builder(text.len)

	match op.op_type {
		.insert {
			// Undo insert: delete the inserted text
			sb.write_string(text[..op.range_start])
			sb.write_string(text[op.range_end..])
		}
		.delete {
			// Undo delete: reinsert the deleted text
			sb.write_string(text[..op.range_start])
			sb.write_string(op.deleted_text)
			sb.write_string(text[op.range_start..])
		}
		.replace {
			// Undo replace: remove inserted, restore deleted
			sb.write_string(text[..op.range_start])
			sb.write_string(op.deleted_text)
			sb.write_string(text[op.range_end..])
		}
	}

	new_text := sb.str()

	// Push to redo stack
	um.redo_stack << op

	return new_text, op.cursor_before, op.anchor_before
}

// redo reapplies undone operation, returns (new_text, cursor, anchor).
// Returns none if nothing to redo. Pushes operation to undo_stack.
pub fn (mut um UndoManager) redo(text string, cursor int, anchor int) ?(string, int, int) {
	if um.redo_stack.len == 0 {
		return none
	}

	// Pop operation
	op := um.redo_stack[um.redo_stack.len - 1]
	um.redo_stack = um.redo_stack[..um.redo_stack.len - 1]

	// Bounds guard: range_start may be stale if text was modified
	// outside undo system.
	if op.range_start > text.len {
		return none
	}

	// Reapply original operation
	mut sb := strings.new_builder(text.len)

	match op.op_type {
		.insert {
			// Redo insert: insert the text
			sb.write_string(text[..op.range_start])
			sb.write_string(op.inserted_text)
			sb.write_string(text[op.range_start..])
		}
		.delete {
			// Redo delete: delete the text
			sb.write_string(text[..op.range_start])
			sb.write_string(text[op.range_end..])
		}
		.replace {
			// Redo replace: delete old, insert new
			sb.write_string(text[..op.range_start])
			sb.write_string(op.inserted_text)
			old_end := op.range_start + op.deleted_text.len
			sb.write_string(text[old_end..])
		}
	}

	new_text := sb.str()

	// Push to undo stack, enforcing history limit
	if um.undo_stack.len >= um.max_history {
		um.undo_stack.delete(0)
	}
	um.undo_stack << op

	return new_text, op.cursor_after, op.anchor_after
}

// break_coalescing flushes pending operation when user navigates.
// Named explicitly for semantic clarity at call sites.
pub fn (mut um UndoManager) break_coalescing() {
	um.flush_pending()
}

// can_undo returns true if undo is possible (pending op or undo_stack not empty)
pub fn (um &UndoManager) can_undo() bool {
	return um.coalescable_op != none || um.undo_stack.len > 0
}

// can_redo returns true if redo is possible (redo_stack not empty)
pub fn (um &UndoManager) can_redo() bool {
	return um.redo_stack.len > 0
}

// clear resets all undo/redo state.
// Clears both stacks and any pending coalescable operation.
pub fn (mut um UndoManager) clear() {
	um.undo_stack = []
	um.redo_stack = []
	um.coalescable_op = none
}

// undo_depth returns count of operations available for undo.
// Includes both committed stack and pending coalescable operation.
pub fn (um &UndoManager) undo_depth() int {
	pending := if um.coalescable_op != none { 1 } else { 0 }
	return um.undo_stack.len + pending
}
