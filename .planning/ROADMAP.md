# Roadmap: VGlyph

## Milestones

- v1.0 Memory Safety — Phases 1-3 (shipped 2026-02-02)
- v1.1 Fragile Area Hardening — Phases 4-7 (shipped 2026-02-02)
- v1.2 Performance Optimization — Phases 8-10 (shipped 2026-02-02)
- v1.3 Text Editing — Phases 11-17 (active)

## Phases

<details>
<summary>v1.0 Memory Safety (Phases 1-3) — SHIPPED 2026-02-02</summary>

- [x] Phase 1: Error Propagation (1/1 plans) — completed 2026-02-01
- [x] Phase 2: Memory Safety (1/1 plans) — completed 2026-02-01
- [x] Phase 3: Layout Safety (1/1 plans) — completed 2026-02-02

</details>

<details>
<summary>v1.1 Fragile Area Hardening (Phases 4-7) — SHIPPED 2026-02-02</summary>

- [x] Phase 4: Layout Iteration (1/1 plans) — completed 2026-02-02
- [x] Phase 5: Attribute List (1/1 plans) — completed 2026-02-02
- [x] Phase 6: FreeType State (1/1 plans) — completed 2026-02-02
- [x] Phase 7: Vertical Coords (1/1 plans) — completed 2026-02-02

</details>

<details>
<summary>v1.2 Performance Optimization (Phases 8-10) — SHIPPED 2026-02-02</summary>

- [x] Phase 8: Instrumentation (2/2 plans) — completed 2026-02-02
- [x] Phase 9: Latency Optimizations (3/3 plans) — completed 2026-02-02
- [x] Phase 10: Memory Optimization (1/1 plans) — completed 2026-02-02

See: .planning/milestones/v1.2-ROADMAP.md for full details.

</details>

<details open>
<summary>v1.3 Text Editing (Phases 11-17) — ACTIVE</summary>

### Phase 11: Cursor Foundation

**Goal:** User can position and navigate cursor within text.

**Dependencies:** None (uses existing Layout hit testing APIs).

**Requirements:** CURS-01, CURS-02, CURS-03, CURS-04, CURS-05

**Success Criteria:**
1. User clicks text, cursor appears at clicked character boundary
2. Arrow keys move cursor by character (respecting grapheme clusters like emoji)
3. Cmd+Arrow moves cursor by word, Ctrl+Arrow by line
4. Home/End keys move cursor to line start/end
5. Cursor geometry API returns (x, y, height) for rendering vertical line

**Plans:** 2 plans

Plans:
- [x] 11-01-PLAN.md — Pango cursor bindings + CursorPosition geometry API
- [x] 11-02-PLAN.md — Cursor movement APIs + keyboard navigation demo

---

### Phase 12: Selection

**Goal:** User can select text ranges for copy/cut operations.

**Dependencies:** Phase 11 (cursor positioning)

**Requirements:** SEL-01, SEL-02, SEL-03, SEL-04, SEL-05

**Success Criteria:**
1. User clicks and drags, text highlights from start to end position
2. User holds Shift and presses arrow keys, selection extends from cursor
3. User double-clicks word, entire word selects
4. User triple-clicks line, entire line selects
5. Cmd+A selects all text, selection rects API returns highlight geometry

**Plans:** 0/0

---

### Phase 13: Text Mutation

**Goal:** User can insert, delete, and modify text content.

**Dependencies:** Phase 11 (cursor), Phase 12 (selection for replace)

**Requirements:** MUT-01, MUT-02, MUT-03, MUT-04, MUT-05, MUT-06

**Success Criteria:**
1. User types character, it inserts at cursor position and cursor advances
2. User presses Backspace, character before cursor deletes (or selection removes)
3. User presses Delete key, character after cursor removes (or selection removes)
4. User selects text and presses Cmd+X, selection copies to clipboard and deletes
5. User presses Cmd+V, clipboard text inserts at cursor (replacing selection if any)

**Plans:** 0/0

---

### Phase 14: Undo/Redo

**Goal:** User can revert and reapply text mutations.

**Dependencies:** Phase 13 (mutation operations)

**Requirements:** UNDO-01, UNDO-02, UNDO-03

**Success Criteria:**
1. User types text then presses Cmd+Z, typed text disappears (cursor returns)
2. User presses Cmd+Shift+Z after undo, text reappears at original position
3. User performs 100+ edits, oldest edits drop from history (50-100 limit respected)

**Plans:** 0/0

---

### Phase 15: IME Integration

**Goal:** User can input CJK and accented characters via system IME.

**Dependencies:** Phase 11 (cursor geometry for candidate window), Phase 13 (text insertion)

**Requirements:** IME-01, IME-02, IME-03, IME-04

**Success Criteria:**
1. User activates Japanese IME and types, composition text displays with underline
2. User converts composition, committed text replaces preedit at cursor position
3. IME candidate window appears near cursor (correct screen coordinates)
4. User types dead key sequence (e.g., ` + e), accented character (e) appears

**Plans:** 0/0

---

### Phase 16: API & Demo

**Goal:** Clean editing API surface and working demo application.

**Dependencies:** Phases 11-15 (all VGlyph editing primitives)

**Requirements:** API-01, API-02, API-03

**Success Criteria:**
1. Editing API documented with examples (cursor, selection, mutation, undo, IME)
2. Demo application shows cursor positioning, selection highlighting, text mutation
3. Demo exercises undo/redo and IME composition (Japanese input test)
4. v-gui can consume APIs (interface contract verified)

**Plans:** 0/0

**Note:** v-gui widget modifications tracked in separate v-gui milestone.

---

### Phase 17: Accessibility

**Goal:** VoiceOver users can navigate and edit text with full screen reader support.

**Dependencies:** Phases 11-15 (editing APIs), existing macOS accessibility integration

**Requirements:** ACC-01, ACC-02, ACC-03

**Success Criteria:**
1. VoiceOver announces cursor position when it changes (character, word, line context)
2. VoiceOver announces selection start/end when selection changes
3. VoiceOver announces IME composition state (preedit text, conversion)
4. Demo verified with VoiceOver enabled

**Plans:** 0/0

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Error Propagation | v1.0 | 1/1 | Complete | 2026-02-01 |
| 2. Memory Safety | v1.0 | 1/1 | Complete | 2026-02-01 |
| 3. Layout Safety | v1.0 | 1/1 | Complete | 2026-02-02 |
| 4. Layout Iteration | v1.1 | 1/1 | Complete | 2026-02-02 |
| 5. Attribute List | v1.1 | 1/1 | Complete | 2026-02-02 |
| 6. FreeType State | v1.1 | 1/1 | Complete | 2026-02-02 |
| 7. Vertical Coords | v1.1 | 1/1 | Complete | 2026-02-02 |
| 8. Instrumentation | v1.2 | 2/2 | Complete | 2026-02-02 |
| 9. Latency Optimizations | v1.2 | 3/3 | Complete | 2026-02-02 |
| 10. Memory Optimization | v1.2 | 1/1 | Complete | 2026-02-02 |
| 11. Cursor Foundation | v1.3 | 2/2 | Complete | 2026-02-02 |
| 12. Selection | v1.3 | 0/0 | Pending | — |
| 13. Text Mutation | v1.3 | 0/0 | Pending | — |
| 14. Undo/Redo | v1.3 | 0/0 | Pending | — |
| 15. IME Integration | v1.3 | 0/0 | Pending | — |
| 16. API & Demo | v1.3 | 0/0 | Pending | — |
| 17. Accessibility | v1.3 | 0/0 | Pending | — |
