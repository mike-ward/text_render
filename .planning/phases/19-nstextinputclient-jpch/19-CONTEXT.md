# Phase 19: NSTextInputClient Protocol + Japanese/Chinese - Context

**Gathered:** 2026-02-03
**Status:** Ready for planning

<domain>
## Phase Boundary

IME events flow from overlay to CompositionState; Japanese and Chinese input works end-to-end.
NSTextInputClient protocol methods (setMarkedText, insertText, firstRectForCharacterRange) wire up
correctly. Users can type romaji, see hiragana preedit, convert to kanji, and commit.

</domain>

<decisions>
## Implementation Decisions

### Preedit Styling
- Single underline for uncommitted composition text
- Preedit text at ~70% opacity (slightly dimmed) to show uncommitted state
- Romaji converts to hiragana live as typed (standard macOS IME behavior)
- Cursor appears at insertion point within preedit (not fixed at end)

### Candidate Window Position
- Candidate window appears directly below cursor/preedit
- OS handles off-screen repositioning (we don't flip above manually)
- Return rect with accurate line height so candidate window clears text properly

### Clause Segmentation Display
- Selected clause (for conversion) uses thick underline
- Unselected clauses use thin underline
- No visual gaps between clause boundaries — underlines flow together
- Moving between clauses with arrow keys only changes underline style

### Claude's Discretion
- Horizontal alignment of candidate window (preedit start vs cursor position)
- Focus loss behavior during composition (auto-commit vs cancel)
- Chinese IME commit method (Space, number keys, or both)
- Escape key behavior (clear preedit vs restore original)
- Post-commit cursor positioning

</decisions>

<specifics>
## Specific Ideas

No specific requirements — follow standard macOS IME conventions and match typical native app
behavior.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 19-nstextinputclient-jpch*
*Context gathered: 2026-02-03*
