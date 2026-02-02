# Requirements: VGlyph v1.3 Text Editing

**Defined:** 2026-02-02
**Core Value:** Reliable text rendering without crashes or undefined behavior

## v1.3 Requirements

Requirements for text editing milestone. Each maps to roadmap phases.

### Cursor

- [ ] **CURS-01**: User can click to position cursor at character boundary
- [ ] **CURS-02**: Cursor position returns geometry (x, y, height) for rendering
- [ ] **CURS-03**: Arrow keys move cursor by character, word (Cmd+Arrow), or line
- [ ] **CURS-04**: Home/End keys move cursor to line start/end
- [ ] **CURS-05**: Cursor movement respects grapheme clusters (emoji, combining marks)

### Selection

- [ ] **SEL-01**: User can click+drag to select text range
- [ ] **SEL-02**: Shift+arrow extends selection from cursor
- [ ] **SEL-03**: Double-click selects word, triple-click selects line
- [ ] **SEL-04**: Cmd+A selects all text
- [ ] **SEL-05**: Selection returns geometry rects for highlighting

### Mutation

- [ ] **MUT-01**: User can insert text at cursor position
- [ ] **MUT-02**: Backspace deletes character before cursor (or selection)
- [ ] **MUT-03**: Delete key removes character after cursor (or selection)
- [ ] **MUT-04**: Cut (Cmd+X) removes selection to clipboard
- [ ] **MUT-05**: Copy (Cmd+C) copies selection to clipboard
- [ ] **MUT-06**: Paste (Cmd+V) inserts clipboard at cursor (replacing selection)

### Undo/Redo

- [ ] **UNDO-01**: Cmd+Z undoes last edit operation
- [ ] **UNDO-02**: Cmd+Shift+Z redoes last undone operation
- [ ] **UNDO-03**: Undo history limited to 50-100 actions

### IME (macOS)

- [ ] **IME-01**: NSTextInputClient protocol integration for macOS IME
- [ ] **IME-02**: Composition text displayed with underline (preedit)
- [ ] **IME-03**: Candidate window positions near cursor
- [ ] **IME-04**: Dead keys compose characters (e.g., ` + e = è)

### v-gui Integration

- [ ] **VGUI-01**: Integrate VGlyph editing APIs into existing view_input.v
- [ ] **VGUI-02**: VGlyph-backed cursor/selection rendering in v-gui
- [ ] **VGUI-03**: Demo application demonstrating all editing features

## Future Requirements

Deferred to v1.3.1+ milestones.

### Advanced Selection

- **ASEL-01**: Rectangular/column selection (Alt+drag)
- **ASEL-02**: Multiple cursor support (Ctrl+D style)

### Advanced Mutation

- **AMUT-01**: Drag-and-drop text movement
- **AMUT-02**: Duplicate line (Cmd+Shift+D)
- **AMUT-03**: Move line up/down (Alt+Arrow)

### Search

- **SRCH-01**: Find text (Cmd+F)
- **SRCH-02**: Find and replace
- **SRCH-03**: Regex search

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Unlimited undo | Memory cost, 50-100 limit sufficient for text fields |
| Grammar checking | Application layer, not rendering library |
| Autocomplete | Application layer, not rendering library |
| Syntax highlighting | VGlyph provides styled runs, app colors them |
| Collaborative editing | CRDT/OT complexity, major future feature |
| Windows/Linux IME | macOS primary for v1.3, platform expansion later |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CURS-01 | — | Pending |
| CURS-02 | — | Pending |
| CURS-03 | — | Pending |
| CURS-04 | — | Pending |
| CURS-05 | — | Pending |
| SEL-01 | — | Pending |
| SEL-02 | — | Pending |
| SEL-03 | — | Pending |
| SEL-04 | — | Pending |
| SEL-05 | — | Pending |
| MUT-01 | — | Pending |
| MUT-02 | — | Pending |
| MUT-03 | — | Pending |
| MUT-04 | — | Pending |
| MUT-05 | — | Pending |
| MUT-06 | — | Pending |
| UNDO-01 | — | Pending |
| UNDO-02 | — | Pending |
| UNDO-03 | — | Pending |
| IME-01 | — | Pending |
| IME-02 | — | Pending |
| IME-03 | — | Pending |
| IME-04 | — | Pending |
| VGUI-01 | — | Pending |
| VGUI-02 | — | Pending |
| VGUI-03 | — | Pending |

**Coverage:**
- v1.3 requirements: 26 total
- Mapped to phases: 0
- Unmapped: 26

---
*Requirements defined: 2026-02-02*
*Last updated: 2026-02-02 after initial definition*
