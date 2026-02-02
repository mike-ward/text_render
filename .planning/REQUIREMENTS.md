# Requirements: VGlyph v1.3 Text Editing

**Defined:** 2026-02-02
**Core Value:** Reliable text rendering without crashes or undefined behavior

## v1.3 Requirements

Requirements for text editing milestone. Each maps to roadmap phases.

### Cursor

- [x] **CURS-01**: User can click to position cursor at character boundary
- [x] **CURS-02**: Cursor position returns geometry (x, y, height) for rendering
- [x] **CURS-03**: Arrow keys move cursor by character, word (Cmd+Arrow), or line
- [x] **CURS-04**: Home/End keys move cursor to line start/end
- [x] **CURS-05**: Cursor movement respects grapheme clusters (emoji, combining marks)

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

### API & Demo

- [ ] **API-01**: Editing API documented with examples for all operations
- [ ] **API-02**: Demo application demonstrates cursor, selection, mutation, undo
- [ ] **API-03**: Demo exercises IME composition (Japanese input test)

### Accessibility

- [ ] **ACC-01**: VoiceOver announces cursor position changes
- [ ] **ACC-02**: VoiceOver announces selection changes
- [ ] **ACC-03**: IME composition state accessible to VoiceOver

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
| CURS-01 | Phase 11 | Complete |
| CURS-02 | Phase 11 | Complete |
| CURS-03 | Phase 11 | Complete |
| CURS-04 | Phase 11 | Complete |
| CURS-05 | Phase 11 | Complete |
| SEL-01 | Phase 12 | Pending |
| SEL-02 | Phase 12 | Pending |
| SEL-03 | Phase 12 | Pending |
| SEL-04 | Phase 12 | Pending |
| SEL-05 | Phase 12 | Pending |
| MUT-01 | Phase 13 | Pending |
| MUT-02 | Phase 13 | Pending |
| MUT-03 | Phase 13 | Pending |
| MUT-04 | Phase 13 | Pending |
| MUT-05 | Phase 13 | Pending |
| MUT-06 | Phase 13 | Pending |
| UNDO-01 | Phase 14 | Pending |
| UNDO-02 | Phase 14 | Pending |
| UNDO-03 | Phase 14 | Pending |
| IME-01 | Phase 15 | Pending |
| IME-02 | Phase 15 | Pending |
| IME-03 | Phase 15 | Pending |
| IME-04 | Phase 15 | Pending |
| API-01 | Phase 16 | Pending |
| API-02 | Phase 16 | Pending |
| API-03 | Phase 16 | Pending |
| ACC-01 | Phase 17 | Pending |
| ACC-02 | Phase 17 | Pending |
| ACC-03 | Phase 17 | Pending |

**Coverage:**
- v1.3 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0

---
*Requirements defined: 2026-02-02*
*Last updated: 2026-02-02 after roadmap creation*
