module main

// Editor demo using proper V/gg state management pattern.
// State is heap-allocated and passed through user_data.
import gg
import time
import vglyph
import accessibility

const window_width = 800
const window_height = 600

// Auto-scroll constants
const scroll_edge_threshold = 30 // Pixels from edge to trigger scroll
const scroll_base_speed = 3.0 // Base pixels per frame
const scroll_acceleration = 0.15 // Speed multiplier per pixel past threshold

@[heap]
struct EditorState {
mut:
	gg_ctx &gg.Context        = unsafe { nil }
	ts     &vglyph.TextSystem = unsafe { nil }

	text   string
	cfg    vglyph.TextConfig
	layout vglyph.Layout

	cursor_idx  int
	preferred_x f32 = -1 // Remembered x position for up/down navigation

	// Selection state (anchor-focus model)
	anchor_idx    int = -1 // Fixed point where selection started (-1 = no selection)
	is_dragging   bool // Mouse drag in progress
	has_selection bool // Selection currently active

	// Multi-click tracking
	last_click_time i64
	click_count     int

	// Auto-scroll state
	scroll_offset   f32 // Current vertical scroll offset
	scroll_velocity f32 // Pixels per frame when auto-scrolling

	// Clipboard (internal - v-gui uses system pasteboard)
	clipboard string

	// Skip next char event (after Cmd+key handled)
	skip_char_event bool

	// Undo/redo support
	undo_mgr vglyph.UndoManager

	// IME composition state
	composition vglyph.CompositionState
	dead_key    vglyph.DeadKeyState
	ime_overlay voidptr = unsafe { nil } // IME overlay handle

	// Status bar tracking
	current_line int
	current_col  int

	// Accessibility support
	a11y_announcer accessibility.AccessibilityAnnouncer
	a11y_manager   &accessibility.AccessibilityManager = unsafe { nil }
	a11y_node_id   int = -1 // Text field node ID
	a11y_enabled   bool
	prev_line      int = -1 // Track line changes for announcements
	in_dead_key    bool // Track dead key composition state
}

fn main() {
	mut state := &EditorState{
		text: 'VGlyph Editor Demo\n\n' + 'Cursor Navigation:\n' +
			'  Arrow keys: move by grapheme\n' + '  Option+Arrow: move by word\n' +
			'  Cmd+Arrow / Home/End: line start/end\n\n' + 'Selection:\n' +
			'  Shift+Arrow: extend selection\n' + '  Double-click: select word\n' +
			'  Triple-click: select paragraph\n\n' + 'Editing:\n' +
			'  Backspace/Delete: delete char\n' + '  Cmd+Backspace: delete to line start\n' +
			'  Option+Backspace: delete word\n' + '  Cmd+Z: undo, Cmd+Shift+Z: redo\n\n' +
			'IME (dead keys):\n' + '  Option+` then e = è (e with grave)\n' +
			'  Option+e then e = é (e with acute)\n\n' +
			'Emoji Tests (cursor should skip whole cluster):\n' + '  Simple: ❤ ⭐ 🌈\n' +
			'  Flag: 🇺🇸 🇯🇵\n' + '  Family: 👨‍👩‍👧\n' +
			'  Skin tone: 👋🏽\n\n' +
			'Lorem ipsum dolor sit amet, consectetur adipiscing elit.\n' +
			'Sed do eiusmod tempor incididunt ut labore et dolore magna.'
	}

	state.gg_ctx = gg.new_context(
		bg_color:     gg.white
		width:        window_width
		height:       window_height
		window_title: 'VGlyph Editor Demo'
		init_fn:      init
		frame_fn:     frame
		event_fn:     event
		user_data:    state
	)

	state.gg_ctx.run()
}

fn init(state_ptr voidptr) {
	mut state := unsafe { &EditorState(state_ptr) }
	state.ts = vglyph.new_text_system(mut state.gg_ctx) or { panic(err) }

	state.cfg = vglyph.TextConfig{
		style: vglyph.TextStyle{
			font_name: 'Sans 16'
			color:     gg.black
		}
		block: vglyph.BlockStyle{
			width: 600
			wrap:  .word
		}
	}

	// Initialize undo manager with 100 operation history
	state.undo_mgr = vglyph.new_undo_manager(100)

	// Perform initial layout
	state.layout = state.ts.layout_text(state.text, state.cfg) or { panic(err) }

	// Create IME overlay and register callbacks (per-overlay API for multi-field support)
	// Note: We need the MTKView handle from sokol, but gg doesn't expose it directly.
	// For now, we still use the global callback API which works for single-field apps.
	// TODO: When gg exposes native view handle, switch to ime_overlay_create + register
	vglyph.ime_register_callbacks(ime_marked_text, ime_insert_text, ime_unmark_text, ime_bounds,
		state_ptr)

	// Also register overlay callbacks for clause enumeration support
	// The overlay API provides clause callbacks not available in the basic API
	// state.ime_overlay = vglyph.ime_overlay_create(mtk_view) // Need native handle
	// When overlay available, register with:
	// vglyph.ime_overlay_register_callbacks(state.ime_overlay, ime_on_marked_text,
	//     ime_on_insert_text, ime_on_unmark_text, ime_on_get_bounds, ime_on_clauses_begin,
	//     ime_on_clause, ime_on_clauses_end, state_ptr)

	// Initialize accessibility
	state.a11y_announcer = accessibility.new_accessibility_announcer()
	state.a11y_manager = accessibility.new_accessibility_manager()
	state.a11y_node_id = state.a11y_manager.create_text_field_node(gg.Rect{
		x:      50
		y:      50
		width:  600
		height: 500
	})
	state.a11y_enabled = true
}

fn event(e &gg.Event, state_ptr voidptr) {
	mut state := unsafe { &EditorState(state_ptr) }

	// Offset for rendering (x=50, y=50)
	offset_x := f32(50)
	offset_y := f32(50)

	match e.typ {
		.mouse_down {
			// Commit composition on click (per CONTEXT.md)
			if state.composition.is_composing() {
				committed := state.composition.commit()
				if committed.len > 0 {
					cursor_before := state.cursor_idx
					anchor_before := state.anchor_idx
					result := vglyph.insert_text(state.text, state.cursor_idx, committed)
					new_layout := state.ts.layout_text(result.new_text, state.cfg) or { return }
					mut new_cursor := result.cursor_pos
					if new_cursor < 0 {
						new_cursor = 0
					}
					if new_cursor > result.new_text.len {
						new_cursor = result.new_text.len
					}
					state.text = result.new_text
					state.layout = new_layout
					state.cursor_idx = new_cursor
					state.anchor_idx = new_cursor
					state.has_selection = false
					state.undo_mgr.record_mutation(result, committed, cursor_before, anchor_before)
				}
			}

			mx := e.mouse_x - offset_x
			my := e.mouse_y - offset_y + state.scroll_offset

			// Get index closest to click
			idx := state.layout.get_closest_offset(mx, my)

			// Multi-click detection (400ms threshold per user decision)
			current_time := time.now().unix_milli()
			click_threshold := i64(400)

			if current_time - state.last_click_time < click_threshold {
				state.click_count += 1
			} else {
				state.click_count = 1
			}
			state.last_click_time = current_time

			// Check if Option/Alt held for word snap
			opt_held := (e.modifiers & u32(gg.Modifier.alt)) != 0

			match state.click_count {
				1 {
					// Single click
					if opt_held {
						// Option+click: snap to word
						start, end := state.layout.get_word_at_index(idx)
						state.anchor_idx = start
						state.cursor_idx = end
						state.has_selection = (start != end)
					} else {
						// Click inside existing selection clears and repositions
						if state.has_selection {
							sel_start := if state.anchor_idx < state.cursor_idx {
								state.anchor_idx
							} else {
								state.cursor_idx
							}
							sel_end := if state.anchor_idx < state.cursor_idx {
								state.cursor_idx
							} else {
								state.anchor_idx
							}
							if idx >= sel_start && idx < sel_end {
								state.has_selection = false
							}
						}
						state.anchor_idx = idx
						state.cursor_idx = idx
						state.has_selection = false
					}
				}
				2 {
					// Double-click: select word
					start, end := state.layout.get_word_at_index(idx)
					state.anchor_idx = start
					state.cursor_idx = end
					state.has_selection = start != end
				}
				3 {
					// Triple-click: select paragraph
					start, end := state.layout.get_paragraph_at_index(idx, state.text)
					state.anchor_idx = start
					state.cursor_idx = end
					state.has_selection = start != end
					state.click_count = 0 // Reset to prevent quad-click
				}
				else {
					state.click_count = 1
				}
			}
			state.is_dragging = true
			state.preferred_x = -1
		}
		.mouse_up {
			state.is_dragging = false
			state.scroll_velocity = 0
		}
		.mouse_move {
			if state.is_dragging {
				mx := e.mouse_x - offset_x
				// Account for scroll offset when calculating layout-relative y
				my := e.mouse_y - offset_y + state.scroll_offset
				mut idx := state.layout.get_closest_offset(mx, my)

				// Check if Option/Alt held for word snap during drag
				opt_held := (e.modifiers & u32(gg.Modifier.alt)) != 0

				if opt_held {
					// Snap to word boundaries (extend word-by-word)
					start, end := state.layout.get_word_at_index(idx)
					// Use closer boundary based on anchor position
					if state.anchor_idx <= idx {
						idx = end
					} else {
						idx = start
					}
				}

				state.cursor_idx = idx
				state.has_selection = (state.anchor_idx != state.cursor_idx)

				// Auto-scroll calculation - only if content exceeds visible area
				visible_height := f32(window_height - 100) // 100 = top+bottom margins
				if state.layout.height > visible_height {
					text_top := offset_y
					text_bottom := offset_y + visible_height

					if e.mouse_y < text_top + scroll_edge_threshold {
						// Above: scroll up
						dist := text_top + scroll_edge_threshold - e.mouse_y
						state.scroll_velocity = -scroll_base_speed - (dist * scroll_acceleration)
					} else if e.mouse_y > text_bottom - scroll_edge_threshold {
						// Below: scroll down
						dist := e.mouse_y - (text_bottom - scroll_edge_threshold)
						state.scroll_velocity = scroll_base_speed + (dist * scroll_acceleration)
					} else {
						state.scroll_velocity = 0
					}
				} else {
					state.scroll_velocity = 0
				}
			}
		}
		.key_down {
			// Handle navigation keys
			cmd_held := (e.modifiers & u32(gg.Modifier.super)) != 0
			shift_held := (e.modifiers & u32(gg.Modifier.shift)) != 0

			// Handle Escape for composition/dead key cancellation
			if e.key_code == .escape {
				if state.composition.is_composing() {
					state.composition.cancel()
					if state.a11y_enabled {
						state.a11y_announcer.announce_composition_cancelled()
					}
					return
				}
				if state.dead_key.has_pending() {
					state.dead_key.clear()
					if state.a11y_enabled {
						state.a11y_announcer.announce_composition_cancelled()
						state.in_dead_key = false
					}
					return
				}
			}

			// Handle undo/redo FIRST - before other command handling
			if cmd_held && e.key_code == .z && !shift_held {
				// Cmd+Z: undo
				if new_text, new_cursor, new_anchor := state.undo_mgr.undo(state.text,
					state.cursor_idx, state.anchor_idx)
				{
					state.text = new_text
					state.cursor_idx = new_cursor
					state.anchor_idx = new_anchor
					state.has_selection = (new_cursor != new_anchor)
					// Regenerate layout
					state.layout = state.ts.layout_text(state.text, state.cfg) or { return }
				}
				return
			}

			if cmd_held && e.key_code == .z && shift_held {
				// Cmd+Shift+Z: redo
				if new_text, new_cursor, new_anchor := state.undo_mgr.redo(state.text,
					state.cursor_idx, state.anchor_idx)
				{
					state.text = new_text
					state.cursor_idx = new_cursor
					state.anchor_idx = new_anchor
					state.has_selection = (new_cursor != new_anchor)
					// Regenerate layout
					state.layout = state.ts.layout_text(state.text, state.cfg) or { return }
				}
				return
			}

			// Handle clipboard commands FIRST - before selection collapse
			// This prevents Cmd from clearing selection before copy/cut
			if cmd_held {
				match e.key_code {
					.a {
						// Cmd+A: select all
						state.anchor_idx = 0
						positions := state.layout.get_valid_cursor_positions()
						state.cursor_idx = if positions.len > 0 {
							positions[positions.len - 1]
						} else {
							0
						}
						state.has_selection = state.anchor_idx != state.cursor_idx
						state.skip_char_event = true
						return
					}
					.c {
						// Cmd+C: copy selection to clipboard
						if state.has_selection {
							state.clipboard = vglyph.get_selected_text(state.text, state.cursor_idx,
								state.anchor_idx)
						}
						state.skip_char_event = true
						return
					}
					.x {
						// Cmd+X: cut selection to clipboard
						if state.has_selection {
							cursor_before := state.cursor_idx
							anchor_before := state.anchor_idx
							cut_text, result := vglyph.cut_selection(state.text, state.cursor_idx,
								state.anchor_idx)
							if result.new_text != state.text {
								new_layout := state.ts.layout_text(result.new_text, state.cfg) or {
									state.skip_char_event = true
									return
								}
								// Trust mutation result cursor directly
								mut new_cursor := result.cursor_pos
								if new_cursor < 0 {
									new_cursor = 0
								}
								if new_cursor > result.new_text.len {
									new_cursor = result.new_text.len
								}
								state.clipboard = cut_text
								state.text = result.new_text
								state.layout = new_layout
								state.cursor_idx = new_cursor
								state.anchor_idx = new_cursor
								state.has_selection = false
								// Track for undo
								state.undo_mgr.record_mutation(result, '', cursor_before,
									anchor_before)
							}
						}
						state.skip_char_event = true
						return
					}
					.v {
						// Cmd+V: paste from clipboard
						if state.clipboard.len > 0 {
							cursor_before := state.cursor_idx
							anchor_before := state.anchor_idx
							mut result := vglyph.MutationResult{}
							if state.has_selection {
								result = vglyph.insert_replacing_selection(state.text,
									state.cursor_idx, state.anchor_idx, state.clipboard)
							} else {
								result = vglyph.insert_text(state.text, state.cursor_idx,
									state.clipboard)
							}
							new_layout := state.ts.layout_text(result.new_text, state.cfg) or {
								state.skip_char_event = true
								return
							}
							// Trust mutation result cursor directly
							mut new_cursor := result.cursor_pos
							if new_cursor < 0 {
								new_cursor = 0
							}
							if new_cursor > result.new_text.len {
								new_cursor = result.new_text.len
							}
							state.text = result.new_text
							state.layout = new_layout
							state.cursor_idx = new_cursor
							state.anchor_idx = new_cursor
							state.has_selection = false
							// Track for undo
							state.undo_mgr.record_mutation(result, state.clipboard, cursor_before,
								anchor_before)
						}
						state.skip_char_event = true
						return
					}
					else {}
				}
			}

			// Handle selection collapse ONLY for navigation keys without Shift
			// Do NOT collapse for other keys (like Cmd, letters, etc.)
			if !shift_held && state.has_selection {
				sel_start := if state.anchor_idx < state.cursor_idx {
					state.anchor_idx
				} else {
					state.cursor_idx
				}
				sel_end := if state.anchor_idx < state.cursor_idx {
					state.cursor_idx
				} else {
					state.anchor_idx
				}
				match e.key_code {
					.left, .up, .home {
						state.cursor_idx = sel_start
						state.has_selection = false
						state.anchor_idx = state.cursor_idx
						state.preferred_x = -1
						return
					}
					.right, .down, .end {
						state.cursor_idx = sel_end
						state.has_selection = false
						state.anchor_idx = state.cursor_idx
						state.preferred_x = -1
						return
					}
					else {
						// Non-navigation key - do NOT clear selection here
						// Let char handler or specific key handlers deal with it
					}
				}
			}

			// Break coalescing for navigation keys
			match e.key_code {
				.left, .right, .up, .down, .home, .end {
					state.undo_mgr.break_coalescing()
				}
				else {}
			}

			// If Shift held and no selection yet, set anchor
			if shift_held && !state.has_selection {
				state.anchor_idx = state.cursor_idx
			}

			// Check Option key for word movement (macOS standard: Option+Arrow = word)
			opt_held := (e.modifiers & u32(gg.Modifier.alt)) != 0

			match e.key_code {
				.left {
					if opt_held {
						// Option+Arrow: word movement (macOS standard)
						state.cursor_idx = state.layout.move_cursor_word_left(state.cursor_idx)
						// Announce word jump with context preview
						if state.a11y_enabled {
							start, end := state.layout.get_word_at_index(state.cursor_idx)
							if end > start && start < state.text.len {
								word := state.text[start..end]
								state.a11y_announcer.announce_word_jump(word)
							}
						}
					} else if cmd_held {
						// Cmd+Arrow: line start (macOS standard)
						state.cursor_idx = state.layout.move_cursor_line_start(state.cursor_idx)
						if state.a11y_enabled {
							state.a11y_announcer.announce_line_boundary(.beginning)
							start, end := state.layout.get_word_at_index(state.cursor_idx)
							if end > start && start < state.text.len {
								word := state.text[start..end]
								state.a11y_announcer.announce_word_jump(word)
							}
						}
					} else {
						state.cursor_idx = state.layout.move_cursor_left(state.cursor_idx)
						// Announce character at new cursor position
						if state.a11y_enabled && state.cursor_idx < state.text.len {
							ch := get_rune_at_byte_index(state.text, state.cursor_idx)
							state.a11y_announcer.announce_character(ch)
						}
					}
					state.preferred_x = -1
				}
				.right {
					if opt_held {
						// Option+Arrow: word movement (macOS standard)
						state.cursor_idx = state.layout.move_cursor_word_right(state.cursor_idx)
						// Announce word jump with context preview
						if state.a11y_enabled {
							start, end := state.layout.get_word_at_index(state.cursor_idx)
							if end > start && start < state.text.len {
								word := state.text[start..end]
								state.a11y_announcer.announce_word_jump(word)
							}
						}
					} else if cmd_held {
						// Cmd+Arrow: line end (macOS standard)
						state.cursor_idx = state.layout.move_cursor_line_end(state.cursor_idx)
						if state.a11y_enabled {
							state.a11y_announcer.announce_line_boundary(.end)
							start, end := state.layout.get_word_at_index(state.cursor_idx)
							if end > start && start < state.text.len {
								word := state.text[start..end]
								state.a11y_announcer.announce_word_jump(word)
							}
						}
					} else {
						state.cursor_idx = state.layout.move_cursor_right(state.cursor_idx)
						// Announce character at new cursor position
						if state.a11y_enabled && state.cursor_idx < state.text.len {
							ch := get_rune_at_byte_index(state.text, state.cursor_idx)
							state.a11y_announcer.announce_character(ch)
						}
					}
					state.preferred_x = -1
				}
				.up {
					if state.preferred_x < 0 {
						if pos := state.layout.get_cursor_pos(state.cursor_idx) {
							state.preferred_x = pos.x
						}
					}
					state.cursor_idx = state.layout.move_cursor_up(state.cursor_idx, state.preferred_x)
				}
				.down {
					if state.preferred_x < 0 {
						if pos := state.layout.get_cursor_pos(state.cursor_idx) {
							state.preferred_x = pos.x
						}
					}
					state.cursor_idx = state.layout.move_cursor_down(state.cursor_idx,
						state.preferred_x)
				}
				.home {
					state.cursor_idx = state.layout.move_cursor_line_start(state.cursor_idx)
					state.preferred_x = -1
					// Announce line boundary and word context (per CONTEXT.md)
					if state.a11y_enabled {
						state.a11y_announcer.announce_line_boundary(.beginning)
						start, end := state.layout.get_word_at_index(state.cursor_idx)
						if end > start && start < state.text.len {
							word := state.text[start..end]
							state.a11y_announcer.announce_word_jump(word)
						}
					}
				}
				.end {
					state.cursor_idx = state.layout.move_cursor_line_end(state.cursor_idx)
					state.preferred_x = -1
					// Announce line boundary and word context (per CONTEXT.md)
					if state.a11y_enabled {
						state.a11y_announcer.announce_line_boundary(.end)
						start, end := state.layout.get_word_at_index(state.cursor_idx)
						if end > start && start < state.text.len {
							word := state.text[start..end]
							state.a11y_announcer.announce_word_jump(word)
						}
					}
				}
				.backspace {
					// opt_held already defined above for arrow key handling

					// Capture cursor state BEFORE mutation for undo
					cursor_before := state.cursor_idx
					anchor_before := state.anchor_idx

					mut result := vglyph.MutationResult{}

					if state.has_selection {
						// Selection active: delete selection only
						result = vglyph.delete_selection(state.text, state.cursor_idx,
							state.anchor_idx)
					} else if cmd_held {
						// Cmd+Backspace: delete to line start
						result = vglyph.delete_to_line_start(state.text, state.layout,
							state.cursor_idx)
					} else if opt_held {
						// Option+Backspace: delete to word boundary
						result = vglyph.delete_to_word_boundary(state.text, state.layout,
							state.cursor_idx)
					} else {
						// Plain Backspace: delete one grapheme cluster
						result = vglyph.delete_backward(state.text, state.layout, state.cursor_idx)
					}

					// Only update if text actually changed
					if result.new_text != state.text {
						// Create new layout FIRST - if this fails, don't change state
						new_layout := state.ts.layout_text(result.new_text, state.cfg) or { return }

						// Trust mutation result cursor directly - just clamp to valid range
						mut new_cursor := result.cursor_pos
						if new_cursor < 0 {
							new_cursor = 0
						}
						if new_cursor > result.new_text.len {
							new_cursor = result.new_text.len
						}

						// Now atomically update all state
						state.text = result.new_text
						state.layout = new_layout
						state.cursor_idx = new_cursor
						state.anchor_idx = new_cursor
						state.has_selection = false

						// Track for undo (empty string since deletion)
						state.undo_mgr.record_mutation(result, '', cursor_before, anchor_before)
					}
					return
				}
				.delete {
					// opt_held already defined above for arrow key handling

					// Capture cursor state BEFORE mutation for undo
					cursor_before := state.cursor_idx
					anchor_before := state.anchor_idx

					mut result := vglyph.MutationResult{}

					if state.has_selection {
						result = vglyph.delete_selection(state.text, state.cursor_idx,
							state.anchor_idx)
					} else if cmd_held {
						result = vglyph.delete_to_line_end(state.text, state.layout, state.cursor_idx)
					} else if opt_held {
						result = vglyph.delete_to_word_end(state.text, state.layout, state.cursor_idx)
					} else {
						result = vglyph.delete_forward(state.text, state.layout, state.cursor_idx)
					}

					// Only update if text actually changed
					if result.new_text != state.text {
						// Create new layout FIRST - if this fails, don't change state
						new_layout := state.ts.layout_text(result.new_text, state.cfg) or { return }

						// Trust mutation result cursor directly - just clamp to valid range
						mut new_cursor := result.cursor_pos
						if new_cursor < 0 {
							new_cursor = 0
						}
						if new_cursor > result.new_text.len {
							new_cursor = result.new_text.len
						}

						// Now atomically update all state
						state.text = result.new_text
						state.layout = new_layout
						state.cursor_idx = new_cursor
						state.anchor_idx = new_cursor
						state.has_selection = false

						// Track for undo (empty string since deletion)
						state.undo_mgr.record_mutation(result, '', cursor_before, anchor_before)
					}
					return
				}
				else {}
			}

			// Update selection state ONLY for navigation keys
			// Letter keys should NOT clear selection here - let char handler deal with it
			match e.key_code {
				.left, .right, .up, .down, .home, .end {
					// Track if selection was cleared
					had_selection := state.has_selection
					if shift_held {
						state.has_selection = state.anchor_idx != state.cursor_idx
						// Announce selection changes
						if state.a11y_enabled && state.has_selection {
							sel_text := vglyph.get_selected_text(state.text, state.cursor_idx,
								state.anchor_idx)
							state.a11y_announcer.announce_selection(sel_text)
							// Post notification to VoiceOver
							if state.a11y_node_id >= 0 {
								state.a11y_manager.post_notification(state.a11y_node_id,
									.selected_text_changed)
							}
						}
					} else {
						state.has_selection = false
						state.anchor_idx = state.cursor_idx
						// Announce deselection
						if state.a11y_enabled && had_selection {
							state.a11y_announcer.announce_selection_cleared()
						}
					}
					// Announce line number changes
					if state.a11y_enabled {
						new_line, _ := calc_line_col(state.layout, state.cursor_idx)
						state.a11y_announcer.announce_line_number(new_line)
					}
					// Update text field and post notification
					if state.a11y_enabled && state.a11y_node_id >= 0 {
						line, _ := calc_line_col(state.layout, state.cursor_idx)
						state.a11y_manager.update_text_field(state.a11y_node_id, state.text,
							accessibility.Range{
							location: state.cursor_idx
							length:   0
						}, line)
						state.a11y_manager.post_notification(state.a11y_node_id, .value_changed)
					}
				}
				else {
					// Non-navigation key - don't modify selection state
					// Char event will handle selection replacement for letter keys
				}
			}
		}
		.char {
			// Skip char event after Cmd+key was handled (prevents 'v' after Cmd+V)
			if state.skip_char_event {
				state.skip_char_event = false
				return
			}

			// Skip char events when Cmd is held (Cmd+letter = command, not text input)
			cmd_held := (e.modifiers & u32(gg.Modifier.super)) != 0
			if cmd_held {
				return
			}

			// Ignore control characters
			if e.char_code < 32 {
				return
			}

			// Convert codepoint to rune/string
			char_rune := rune(e.char_code)

			// Handle dead key combination
			if state.dead_key.has_pending() {
				combined, _ := state.dead_key.try_combine(char_rune)
				if combined.len > 0 {
					cursor_before := state.cursor_idx
					anchor_before := state.anchor_idx
					mut result := vglyph.MutationResult{}
					if state.has_selection {
						result = vglyph.insert_replacing_selection(state.text, state.cursor_idx,
							state.anchor_idx, combined)
					} else {
						result = vglyph.insert_text(state.text, state.cursor_idx, combined)
					}
					new_layout := state.ts.layout_text(result.new_text, state.cfg) or { return }
					mut new_cursor := result.cursor_pos
					if new_cursor < 0 {
						new_cursor = 0
					}
					if new_cursor > result.new_text.len {
						new_cursor = result.new_text.len
					}
					state.text = result.new_text
					state.layout = new_layout
					state.cursor_idx = new_cursor
					state.anchor_idx = new_cursor
					state.has_selection = false
					state.undo_mgr.record_mutation(result, combined, cursor_before, anchor_before)
					// Announce dead key result (per CONTEXT.md)
					if state.a11y_enabled && state.in_dead_key && combined.len > 0 {
						state.a11y_announcer.announce_dead_key_result(combined.runes()[0])
						state.in_dead_key = false
					}
				}
				return
			}

			// Check if char is a dead key
			if vglyph.is_dead_key(char_rune) {
				state.dead_key.start_dead_key(char_rune, state.cursor_idx)
				// Announce dead key (per CONTEXT.md)
				if state.a11y_enabled {
					state.a11y_announcer.announce_dead_key(char_rune)
					state.in_dead_key = true
				}
				return
			}

			// Convert codepoint to string
			char_str := utf32_to_string(e.char_code)

			// Capture cursor state BEFORE mutation for undo
			cursor_before := state.cursor_idx
			anchor_before := state.anchor_idx

			// Insert with selection replacement
			mut result := vglyph.MutationResult{}
			if state.has_selection {
				result = vglyph.insert_replacing_selection(state.text, state.cursor_idx,
					state.anchor_idx, char_str)
			} else {
				result = vglyph.insert_text(state.text, state.cursor_idx, char_str)
			}

			// Create new layout FIRST - if this fails, don't change state
			new_layout := state.ts.layout_text(result.new_text, state.cfg) or { return }

			// Trust mutation result cursor directly - just clamp to valid range
			mut new_cursor := result.cursor_pos
			if new_cursor < 0 {
				new_cursor = 0
			}
			if new_cursor > result.new_text.len {
				new_cursor = result.new_text.len
			}

			// Atomically update all state
			state.text = result.new_text
			state.layout = new_layout
			state.cursor_idx = new_cursor
			state.anchor_idx = new_cursor
			state.has_selection = false

			// Track for undo
			state.undo_mgr.record_mutation(result, char_str, cursor_before, anchor_before)
		}
		else {}
	}
}

// calc_line_col calculates 1-indexed line:col from cursor byte index.
// Iterates through layout.lines to find containing line, calculates column offset.
fn calc_line_col(layout vglyph.Layout, cursor_idx int) (int, int) {
	for i, line in layout.lines {
		line_end := line.start_index + line.length
		if cursor_idx >= line.start_index && cursor_idx <= line_end {
			return i + 1, cursor_idx - line.start_index + 1
		}
	}
	// Fallback: last line if cursor at end
	if layout.lines.len > 0 {
		last := layout.lines[layout.lines.len - 1]
		return layout.lines.len, cursor_idx - last.start_index + 1
	}
	return 1, 1
}

// get_rune_at_byte_index returns the rune starting at the given byte index.
// This correctly handles multi-byte UTF-8 characters (emoji, etc.)
fn get_rune_at_byte_index(text string, byte_idx int) rune {
	if byte_idx < 0 || byte_idx >= text.len {
		return ` `
	}
	// Find which rune index corresponds to this byte index
	mut current_byte := 0
	for r in text.runes() {
		rune_bytes := r.str().len
		if current_byte == byte_idx {
			return r
		}
		current_byte += rune_bytes
		if current_byte > byte_idx {
			// byte_idx is in the middle of a multi-byte character
			return r
		}
	}
	return ` `
}

// utf32_to_string converts a UTF-32 codepoint to a UTF-8 string.
fn utf32_to_string(codepoint u32) string {
	if codepoint < 0x80 {
		return [u8(codepoint)].bytestr()
	} else if codepoint < 0x800 {
		return [u8(0xC0 | (codepoint >> 6)), u8(0x80 | (codepoint & 0x3F))].bytestr()
	} else if codepoint < 0x10000 {
		return [u8(0xE0 | (codepoint >> 12)), u8(0x80 | ((codepoint >> 6) & 0x3F)),
			u8(0x80 | (codepoint & 0x3F))].bytestr()
	} else {
		return [u8(0xF0 | (codepoint >> 18)), u8(0x80 | ((codepoint >> 12) & 0x3F)),
			u8(0x80 | ((codepoint >> 6) & 0x3F)), u8(0x80 | (codepoint & 0x3F))].bytestr()
	}
}

fn frame(state_ptr voidptr) {
	mut state := unsafe { &EditorState(state_ptr) }

	// Apply auto-scroll
	if state.is_dragging && state.scroll_velocity != 0 {
		state.scroll_offset += state.scroll_velocity
		// Clamp to valid range
		max_scroll := state.layout.height - (window_height - 100) // 100 = top+bottom margins
		if state.scroll_offset < 0 {
			state.scroll_offset = 0
		}
		if max_scroll > 0 && state.scroll_offset > max_scroll {
			state.scroll_offset = max_scroll
		}
	}

	state.gg_ctx.begin()

	// Draw Text with scroll offset
	offset_x := f32(50)
	offset_y := f32(50) - state.scroll_offset

	// Draw Selection Backgrounds
	if state.has_selection && state.anchor_idx != state.cursor_idx {
		start := if state.anchor_idx < state.cursor_idx {
			state.anchor_idx
		} else {
			state.cursor_idx
		}
		end := if state.anchor_idx < state.cursor_idx {
			state.cursor_idx
		} else {
			state.anchor_idx
		}

		rects := state.layout.get_selection_rects(start, end)
		for r in rects {
			state.gg_ctx.draw_rect_filled(offset_x + r.x, offset_y + r.y, r.width, r.height,
				gg.Color{50, 50, 200, 100})
		}
	}

	// Render the text using the system
	// When composing, render text with preedit included
	if state.composition.is_composing() {
		display_text := state.text[..state.composition.preedit_start] +
			state.composition.preedit_text + state.text[state.composition.preedit_start..]
		state.ts.draw_text(offset_x, offset_y, display_text, state.cfg) or { println(err) }
		// Draw composition underlines
		state.ts.draw_composition(state.layout, offset_x, offset_y, &state.composition,
			gg.black)
	} else {
		state.ts.draw_text(offset_x, offset_y, state.text, state.cfg) or { println(err) }
	}

	// Draw Cursor using get_cursor_pos API (visible during composition)
	if pos := state.layout.get_cursor_pos(state.cursor_idx) {
		state.gg_ctx.draw_rect_filled(offset_x + pos.x, offset_y + pos.y, 2, pos.height,
			gg.red)
	}

	// Draw status bar at bottom
	status_y := f32(window_height - 25)
	state.current_line, state.current_col = calc_line_col(state.layout, state.cursor_idx)

	// Left: Line:Col
	line_col_text := 'Line: ${state.current_line}  Col: ${state.current_col}'
	state.gg_ctx.draw_text(10, int(status_y), line_col_text, color: gg.gray)

	// Center: Selection info (if active)
	if state.has_selection {
		sel_start := if state.anchor_idx < state.cursor_idx {
			state.anchor_idx
		} else {
			state.cursor_idx
		}
		sel_end := if state.anchor_idx < state.cursor_idx {
			state.cursor_idx
		} else {
			state.anchor_idx
		}
		sel_len := sel_end - sel_start
		sel_text := 'Sel: ${sel_len} chars'
		state.gg_ctx.draw_text(window_width / 2 - 40, int(status_y), sel_text, color: gg.gray)
	}

	// Right: Undo depth
	undo_depth := state.undo_mgr.undo_depth()
	undo_text := 'Undo: ${undo_depth}'
	state.gg_ctx.draw_text(window_width - 80, int(status_y), undo_text, color: gg.gray)

	state.gg_ctx.end()
	state.ts.commit()
}

// IME callback functions
fn ime_marked_text(text &char, cursor_pos int, user_data voidptr) {
	mut state := unsafe { &EditorState(user_data) }

	// Start composition if not already composing
	if !state.composition.is_composing() {
		state.composition.start(state.cursor_idx)
	}

	// Update preedit text
	preedit := unsafe { cstring_to_vstring(text) }
	state.composition.set_marked_text(preedit, cursor_pos)

	// Rebuild layout with preedit text inserted at cursor position
	// This creates a "display text" that includes the uncommitted preedit
	display_text := state.text[..state.composition.preedit_start] + preedit +
		state.text[state.composition.preedit_start..]
	state.layout = state.ts.layout_text(display_text, state.cfg) or { return }
}

fn ime_insert_text(text &char, user_data voidptr) {
	mut state := unsafe { &EditorState(user_data) }

	// Commit composition if active
	committed := if state.composition.is_composing() {
		state.composition.commit()
	} else {
		unsafe { cstring_to_vstring(text) }
	}

	// Insert committed text
	if committed.len > 0 {
		cursor_before := state.cursor_idx
		anchor_before := state.anchor_idx

		mut result := vglyph.MutationResult{}
		if state.has_selection {
			result = vglyph.insert_replacing_selection(state.text, state.cursor_idx, state.anchor_idx,
				committed)
		} else {
			result = vglyph.insert_text(state.text, state.cursor_idx, committed)
		}

		new_layout := state.ts.layout_text(result.new_text, state.cfg) or { return }
		mut new_cursor := result.cursor_pos
		if new_cursor < 0 {
			new_cursor = 0
		}
		if new_cursor > result.new_text.len {
			new_cursor = result.new_text.len
		}

		state.text = result.new_text
		state.layout = new_layout
		state.cursor_idx = new_cursor
		state.anchor_idx = new_cursor
		state.has_selection = false
		state.undo_mgr.record_mutation(result, committed, cursor_before, anchor_before)
	}
}

fn ime_unmark_text(user_data voidptr) {
	mut state := unsafe { &EditorState(user_data) }
	state.composition.cancel()
	// Restore layout without preedit
	state.layout = state.ts.layout_text(state.text, state.cfg) or { return }
}

fn ime_bounds(user_data voidptr, x &f32, y &f32, width &f32, height &f32) bool {
	state := unsafe { &EditorState(user_data) }

	if rect := state.composition.get_composition_bounds(state.layout) {
		// Convert to screen coordinates (accounting for offset and scroll)
		offset_x := f32(50)
		offset_y := f32(50) - state.scroll_offset

		unsafe {
			*x = offset_x + rect.x
			*y = offset_y + rect.y
			*width = rect.width
			*height = rect.height
		}
		return true
	}
	return false
}

// IME overlay callback functions (for per-overlay API with clause support)
// These use the new handler methods in CompositionState

fn ime_on_marked_text(text &char, cursor_pos int, user_data voidptr) {
	mut state := unsafe { &EditorState(user_data) }
	text_str := unsafe { cstring_to_vstring(text) }
	state.composition.handle_marked_text(text_str, cursor_pos, state.cursor_idx)
	// Rebuild layout to include preedit text
	state.layout = state.ts.layout_text(state.text, state.cfg) or { return }
}

fn ime_on_insert_text(text &char, user_data voidptr) {
	mut state := unsafe { &EditorState(user_data) }
	text_str := unsafe { cstring_to_vstring(text) }
	committed := state.composition.handle_insert_text(text_str)
	if committed.len > 0 {
		cursor_before := state.cursor_idx
		anchor_before := state.anchor_idx

		mut result := vglyph.MutationResult{}
		if state.has_selection {
			result = vglyph.insert_replacing_selection(state.text, state.cursor_idx, state.anchor_idx,
				committed)
		} else {
			result = vglyph.insert_text(state.text, state.cursor_idx, committed)
		}

		new_layout := state.ts.layout_text(result.new_text, state.cfg) or { return }
		mut new_cursor := result.cursor_pos
		if new_cursor < 0 {
			new_cursor = 0
		}
		if new_cursor > result.new_text.len {
			new_cursor = result.new_text.len
		}

		state.text = result.new_text
		state.layout = new_layout
		state.cursor_idx = new_cursor
		state.anchor_idx = new_cursor
		state.has_selection = false
		state.undo_mgr.record_mutation(result, committed, cursor_before, anchor_before)
	}
}

fn ime_on_unmark_text(user_data voidptr) {
	mut state := unsafe { &EditorState(user_data) }
	state.composition.handle_unmark_text()
	// Rebuild layout without preedit
	state.layout = state.ts.layout_text(state.text, state.cfg) or { return }
}

fn ime_on_get_bounds(user_data voidptr, x &f32, y &f32, w &f32, h &f32) bool {
	state := unsafe { &EditorState(user_data) }
	if rect := state.composition.get_composition_bounds(state.layout) {
		offset_x := f32(50)
		offset_y := f32(50) - state.scroll_offset
		unsafe {
			*x = offset_x + rect.x
			*y = offset_y + rect.y
			*w = rect.width
			*h = rect.height
		}
		return true
	}
	return false
}

fn ime_on_clauses_begin(user_data voidptr) {
	mut state := unsafe { &EditorState(user_data) }
	state.composition.clear_clauses()
}

fn ime_on_clause(start int, length int, style int, user_data voidptr) {
	mut state := unsafe { &EditorState(user_data) }
	state.composition.handle_clause(start, length, style)
}

fn ime_on_clauses_end(user_data voidptr) {
	// No action needed - clauses already accumulated
}
