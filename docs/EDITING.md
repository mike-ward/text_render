# VGlyph Editing API Reference

This document covers VGlyph's text editing APIs: cursor positioning, selection, text mutation,
undo/redo, and IME composition.

## Table of Contents

- [Quick Start](#quick-start)
- [Cursor API](#cursor-api)
- [Selection API](#selection-api)
- [Mutation API](#mutation-api)
- [Undo API](#undo-api)
- [IME API](#ime-api)
- [Integration Patterns](#integration-patterns)

---

## Quick Start

VGlyph provides building blocks for text editors. Here's a minimal editing loop:

```v ignore
import vglyph

// Initialize state
mut text := 'Hello World'
mut cursor := 0
mut undo_mgr := vglyph.new_undo_manager(100)

// Insert a character
result := vglyph.insert_text(text, cursor, 'X')
undo_mgr.record_mutation(result, 'X', cursor, cursor)

// Apply result atomically
text = result.new_text
cursor = result.cursor_pos

// Rebuild layout for display
layout := ts.layout_text(text, cfg) or { return }
```

**Key concepts:**

1. Mutation functions return `MutationResult`, they don't modify state directly
2. Application applies changes and rebuilds layout
3. `UndoManager` tracks mutations for undo/redo
4. Layout provides cursor/selection geometry

---

## Cursor API

Cursor APIs live on `Layout`. All methods return byte indices into UTF-8 text.

### Cursor Position

```v ignore
// get_cursor_pos returns geometry for cursor rendering
// Returns none if byte_index is not a valid cursor position
pub fn (l Layout) get_cursor_pos(byte_index int) ?CursorPosition

pub struct CursorPosition {
pub:
    x      f32  // Left edge of cursor
    y      f32  // Top of cursor
    height f32  // Cursor height (line height)
}
```

**Example:**

```v ignore
if pos := layout.get_cursor_pos(cursor_idx) {
    gg_ctx.draw_rect_filled(pos.x, pos.y, 2, pos.height, gg.red)
}
```

### Cursor Movement

Navigation methods move between valid cursor positions (grapheme boundaries), never landing inside
multi-byte characters or emoji clusters.

```v ignore
// Character movement - respects grapheme clusters
pub fn (l Layout) move_cursor_left(byte_index int) int
pub fn (l Layout) move_cursor_right(byte_index int) int

// Word movement - jumps to word boundaries
pub fn (l Layout) move_cursor_word_left(byte_index int) int
pub fn (l Layout) move_cursor_word_right(byte_index int) int

// Line movement - start/end of current line
pub fn (l Layout) move_cursor_line_start(byte_index int) int
pub fn (l Layout) move_cursor_line_end(byte_index int) int

// Vertical movement - maintains horizontal position
pub fn (l Layout) move_cursor_up(byte_index int, preferred_x f32) int
pub fn (l Layout) move_cursor_down(byte_index int, preferred_x f32) int
```

**Example - arrow key handling:**

```v ignore
match key_code {
    .left { cursor = layout.move_cursor_left(cursor) }
    .right { cursor = layout.move_cursor_right(cursor) }
    .up { cursor = layout.move_cursor_up(cursor, preferred_x) }
    .down { cursor = layout.move_cursor_down(cursor, preferred_x) }
    else {}
}
```

### Mouse Click to Cursor

```v ignore
// get_closest_offset returns byte index nearest to click position
// Always returns valid cursor position, handles clicks outside text bounds
pub fn (l Layout) get_closest_offset(x f32, y f32) int
```

**Example:**

```v ignore
fn on_mouse_click(x f32, y f32) {
    // Convert screen coords to layout coords
    local_x := x - text_offset_x
    local_y := y - text_offset_y
    cursor = layout.get_closest_offset(local_x, local_y)
}
```

---

## Selection API

VGlyph uses an **anchor-focus model**: anchor stays at initial click, cursor (focus) moves
with drag or shift+arrow.

### Selection Rectangles

```v ignore
// get_selection_rects returns rectangles covering text range [start, end)
// Handles multi-line selections correctly
pub fn (l Layout) get_selection_rects(start int, end int) []gg.Rect
```

**Example:**

```v ignore
if has_selection {
    start := min(cursor, anchor)
    end := max(cursor, anchor)
    for rect in layout.get_selection_rects(start, end) {
        gg_ctx.draw_rect_filled(rect.x, rect.y, rect.width, rect.height,
            gg.Color{50, 50, 200, 100})
    }
}
```

### Word Selection

```v ignore
// get_word_at_index returns (start, end) byte indices for word at index
// Uses Pango word boundaries (locale-aware)
pub fn (l Layout) get_word_at_index(byte_index int) (int, int)
```

**Example - double-click word select:**

```v ignore
fn on_double_click(x f32, y f32) {
    idx := layout.get_closest_offset(x - offset_x, y - offset_y)
    anchor, cursor = layout.get_word_at_index(idx)
    has_selection = true
}
```

### Valid Cursor Positions

```v ignore
// get_valid_cursor_positions returns sorted list of valid cursor byte indices
// Useful for debugging or custom navigation
pub fn (l Layout) get_valid_cursor_positions() []int
```

---

## Mutation API

All mutation functions are **pure**: they take current state, return new state. Application applies
changes and rebuilds layout.

### MutationResult

```v ignore
pub struct MutationResult {
pub:
    new_text     string  // Result of applying mutation
    cursor_pos   int     // New cursor position after mutation
    deleted_text string  // Text removed (empty for insert)
    range_start  int     // Start of affected range
    range_end    int     // End of affected range
}
```

### Basic Mutations

```v ignore
// Insert text at cursor
pub fn insert_text(text string, cursor int, insert string) MutationResult

// Delete one grapheme backward (Backspace)
pub fn delete_backward(text string, layout Layout, cursor int) MutationResult

// Delete one grapheme forward (Delete key)
pub fn delete_forward(text string, layout Layout, cursor int) MutationResult
```

### Extended Deletions

```v ignore
// Option+Backspace - delete to word boundary
pub fn delete_to_word_boundary(text string, layout Layout, cursor int) MutationResult

// Cmd+Backspace - delete to line start
pub fn delete_to_line_start(text string, layout Layout, cursor int) MutationResult

// Option+Delete - delete to word end
pub fn delete_to_word_end(text string, layout Layout, cursor int) MutationResult

// Cmd+Delete - delete to line end
pub fn delete_to_line_end(text string, layout Layout, cursor int) MutationResult
```

### Selection Operations

```v ignore
// Delete selected text
pub fn delete_selection(text string, cursor int, anchor int) MutationResult

// Insert text, replacing selection
pub fn insert_replacing_selection(text string, cursor int, anchor int, insert string) MutationResult

// Get selected text (for copy)
pub fn get_selected_text(text string, cursor int, anchor int) string

// Cut: returns (clipboard_text, mutation_result)
pub fn cut_selection(text string, cursor int, anchor int) (string, MutationResult)
```

**Example - character input with selection:**

```v ignore
fn on_char_input(ch string) {
    cursor_before := cursor
    anchor_before := anchor

    result := if has_selection {
        vglyph.insert_replacing_selection(text, cursor, anchor, ch)
    } else {
        vglyph.insert_text(text, cursor, ch)
    }

    // Record for undo before applying
    undo_mgr.record_mutation(result, ch, cursor_before, anchor_before)

    // Apply
    text = result.new_text
    cursor = result.cursor_pos
    anchor = cursor
    has_selection = false

    // Rebuild layout
    layout = ts.layout_text(text, cfg) or { return }
}
```

---

## Undo API

`UndoManager` implements undo/redo with operation coalescing.

### UndoManager

```v ignore
pub struct UndoManager {
    // Internal: dual stacks, coalescing state
}

// Create with history limit (default 100)
pub fn new_undo_manager(max_history int) UndoManager
```

### Recording Mutations

```v ignore
// Record mutation for undo support
// Handles coalescing automatically (1s timeout, adjacent operations)
pub fn (mut um UndoManager) record_mutation(
    result MutationResult,
    inserted string,
    cursor_before int,
    anchor_before int
)
```

### Performing Undo/Redo

```v ignore
// Undo last operation, returns (new_text, cursor, anchor) or none
pub fn (mut um UndoManager) undo(text string, cursor int, anchor int) ?(string, int, int)

// Redo undone operation
pub fn (mut um UndoManager) redo(text string, cursor int, anchor int) ?(string, int, int)

// Check availability
pub fn (um &UndoManager) can_undo() bool
pub fn (um &UndoManager) can_redo() bool
```

**Example:**

```v ignore
// Ctrl+Z / Cmd+Z
if e.key_code == .z && cmd_held && !shift_held {
    if new_text, new_cursor, new_anchor := undo_mgr.undo(text, cursor, anchor) {
        text = new_text
        cursor = new_cursor
        anchor = new_anchor
        has_selection = (cursor != anchor)
        layout = ts.layout_text(text, cfg) or { return }
    }
}

// Ctrl+Shift+Z / Cmd+Shift+Z (Redo)
if e.key_code == .z && cmd_held && shift_held {
    if new_text, new_cursor, new_anchor := undo_mgr.redo(text, cursor, anchor) {
        // ... apply same as undo
    }
}
```

### Coalescing Control

Typing adjacent characters coalesces into single undo operation. Break coalescing on navigation
to avoid undoing too much.

```v ignore
// Break coalescing when user navigates
pub fn (mut um UndoManager) break_coalescing()

// Clear all history
pub fn (mut um UndoManager) clear()
```

**When to break coalescing:**

- Arrow key navigation
- Mouse clicks
- After programmatic cursor moves

**Example:**

```v ignore
fn on_arrow_key() {
    undo_mgr.break_coalescing()
    // ... move cursor
}
```

---

## IME API

Input Method Editor support for dead keys and CJK composition.

See [IME-APPENDIX.md](./IME-APPENDIX.md) for detailed IME documentation
including dead key tables and CJK IME details with overlay architecture.

### Overlay API (macOS, v1.8+)

Overlay creates transparent NSView sibling above MTKView, receives IME events
directly.

**Overlay lifecycle:**

```v ignore
// Create overlay (discovers MTKView automatically)
ns_window := C.sapp_macos_get_window()
overlay := vglyph.ime_overlay_create_auto(ns_window)

// Register callbacks
vglyph.ime_overlay_register_callbacks(overlay,
    on_marked_text_fn, on_insert_text_fn,
    on_do_command_fn, on_get_rect_fn,
    on_clause_fn, user_data)

// Activate for a field
vglyph.ime_overlay_set_focused_field(overlay, 'my_field')

// Cleanup
vglyph.ime_overlay_free(overlay)
```

**Note:** Falls back to global callbacks if overlay creation fails.

### Dead Keys (Working)

Dead key composition for accented Latin characters:

```v ignore
pub struct DeadKeyState {
pub mut:
    pending     ?rune  // Dead key waiting for combination
    pending_pos int    // Document position where typed
}

// Check for pending dead key
pub fn (dks &DeadKeyState) has_pending() bool

// Record dead key press
pub fn (mut dks DeadKeyState) start_dead_key(dead rune, pos int)

// Try combining with base character
// Returns (result_string, was_combined)
pub fn (mut dks DeadKeyState) try_combine(base rune) (string, bool)

// Check if rune is a dead key
pub fn is_dead_key(r rune) bool
```

**Example:**

```v ignore
fn on_char(ch rune) {
    if vglyph.is_dead_key(ch) {
        dead_key.start_dead_key(ch, cursor)
        return
    }

    if dead_key.has_pending() {
        combined, was_combined := dead_key.try_combine(ch)
        insert_string(combined)  // "e" -> "e" (was_combined: true) or "`x" (false)
        return
    }

    insert_string(ch.str())
}
```

### IME Composition State

For CJK input methods with preedit text:

```v ignore
pub struct CompositionState {
pub mut:
    phase         CompositionPhase  // none | composing
    preedit_text  string            // Current composition string
    preedit_start int               // Byte offset where preedit begins
    cursor_offset int               // Cursor within preedit
}

// Lifecycle
pub fn (cs &CompositionState) is_composing() bool
pub fn (mut cs CompositionState) start(cursor_pos int)
pub fn (mut cs CompositionState) set_marked_text(text string, cursor int)
pub fn (mut cs CompositionState) commit() string
pub fn (mut cs CompositionState) reset()

// Geometry for rendering
pub fn (cs &CompositionState) get_composition_bounds(layout Layout) ?gg.Rect
pub fn (cs &CompositionState) get_clause_rects(layout Layout) []ClauseRects
```

---

## Integration Patterns

### State Management

Editor state should be heap-allocated for gg/sokol callback survival:

```v ignore
@[heap]
struct EditorState {
mut:
    gg_ctx      &gg.Context
    ts          &vglyph.TextSystem
    text        string
    layout      vglyph.Layout
    cursor_idx  int
    anchor_idx  int
    has_selection bool
    undo_mgr    vglyph.UndoManager
    composition vglyph.CompositionState
    dead_key    vglyph.DeadKeyState
}
```

### Render Loop Pattern

```v ignore
fn frame(state &EditorState) {
    // 1. Draw selection highlight
    if state.has_selection {
        start := min(state.cursor_idx, state.anchor_idx)
        end := max(state.cursor_idx, state.anchor_idx)
        for r in state.layout.get_selection_rects(start, end) {
            state.gg_ctx.draw_rect_filled(r.x, r.y, r.width, r.height, selection_color)
        }
    }

    // 2. Draw text
    state.ts.draw_layout(state.layout, offset_x, offset_y)

    // 3. Draw cursor
    if pos := state.layout.get_cursor_pos(state.cursor_idx) {
        state.gg_ctx.draw_rect_filled(pos.x, pos.y, 2, pos.height, cursor_color)
    }

    // 4. Draw IME composition underline
    if state.composition.is_composing() {
        for cr in state.composition.get_clause_rects(state.layout) {
            // Draw underline for each clause
        }
    }

    state.ts.commit()
}
```

### Mutation Pattern

Always: record -> apply -> rebuild layout

```v ignore
fn mutate(mut state EditorState, result MutationResult, inserted string) {
    // Record for undo
    state.undo_mgr.record_mutation(result, inserted, state.cursor_idx, state.anchor_idx)

    // Apply changes
    state.text = result.new_text
    state.cursor_idx = result.cursor_pos
    state.anchor_idx = state.cursor_idx
    state.has_selection = false

    // Rebuild layout
    state.layout = state.ts.layout_text(state.text, state.cfg) or { return }
}
```

---

## See Also

- [API.md](./API.md) - Core rendering API
- [IME-APPENDIX.md](./IME-APPENDIX.md) - IME details and dead key tables
- [examples/editor_demo.v](../examples/editor_demo.v) - Working editor example
