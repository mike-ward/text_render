# Phase 20: Korean + Keyboard Integration - Context

**Gathered:** 2026-02-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Korean hangul composition with jamo real-time display, plus keyboard edge cases (dead keys after CJK,
focus loss handling, undo blocking during composition). Japanese/Chinese already work from Phase 19.
Multi-display/Retina is Phase 21.

</domain>

<decisions>
## Implementation Decisions

### Jamo composition display
- Inline with underline — partial syllable appears in text flow, underlined like Japanese preedit
- Cursor appears after the composing syllable (standard behavior)

### Backspace behavior
- Decompose jamo-by-jamo: 간 → 가 → ㄱ → empty (standard Korean behavior)
- Already-committed Korean syllables delete whole (not re-enter composition)
- Single jamo + backspace = delete the jamo, composition ends
- Option+Backspace: cancel composition first, then delete previous word

### State cleanup on focus loss
- Auto-commit composing syllable on focus loss (no text lost)
- Dead keys must work immediately after using CJK IME (clean state, no pollution)

### Claude's Discretion
- Underline style: same as JP/CH or Korean-specific (pick what looks coherent)
- Visual feedback on syllable commit (instant vs brief highlight)
- IME memory per field vs system default on focus return
- Escape key behavior (cancel vs commit)
- Cmd+Z during composition (ignore, beep, or commit-then-undo)
- Cmd+A during composition (block or commit-then-select)
- Undo unit granularity for committed Korean text
- Arrow key behavior during composition (navigate within or commit-and-move)

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following macOS Korean IME conventions.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 20-korean-keyboard*
*Context gathered: 2026-02-04*
