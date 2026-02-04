# Roadmap: VGlyph

## Milestones

- v1.0 Memory Safety — Phases 1-3 (shipped 2026-02-02)
- v1.1 Fragile Area Hardening — Phases 4-7 (shipped 2026-02-02)
- v1.2 Performance Optimization — Phases 8-10 (shipped 2026-02-02)
- v1.3 Text Editing — Phases 11-17 (shipped 2026-02-03)
- v1.4 CJK IME — Phases 18-21 (in progress)

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

<details>
<summary>v1.3 Text Editing (Phases 11-17) — SHIPPED 2026-02-03</summary>

- [x] Phase 11: Cursor Foundation (2/2 plans) — completed 2026-02-02
- [x] Phase 12: Selection (2/2 plans) — completed 2026-02-02
- [x] Phase 13: Text Mutation (2/2 plans) — completed 2026-02-03
- [x] Phase 14: Undo/Redo (2/2 plans) — completed 2026-02-03
- [x] Phase 15: IME Integration (3/3 plans) — completed 2026-02-03 (PARTIAL: dead keys work)
- [x] Phase 16: API & Demo (2/2 plans) — completed 2026-02-03
- [x] Phase 17: Accessibility (2/2 plans) — completed 2026-02-03

See: .planning/milestones/v1.3-ROADMAP.md for full details.

</details>

### v1.4 CJK IME (In Progress)

**Milestone Goal:** Full CJK input method support via overlay NSView without sokol modifications

#### Phase 18: Overlay Infrastructure
**Goal**: Native IME bridge exists and can become first responder
**Depends on**: Phase 17 (v1.3 foundation)
**Requirements**: OVLY-01, OVLY-02, OVLY-03, OVLY-04, OVLY-05
**Success Criteria** (what must be TRUE):
  1. VGlyphIMEOverlayView class exists implementing NSTextInputClient protocol skeleton
  2. Overlay positioned as sibling above MTKView (not child, not blocking clicks)
  3. Overlay becomes first responder when text field gains focus
  4. First responder returns to MTKView when text field loses focus
  5. Non-Darwin builds compile with stub implementation
**Plans**: 1 plan

Plans:
- [x] 18-01-PLAN.md — VGlyphIMEOverlayView class, factory API, focus management, non-Darwin stubs

#### Phase 19: NSTextInputClient Protocol + Japanese/Chinese
**Goal**: IME events flow from overlay to CompositionState, Japanese and Chinese input works
**Depends on**: Phase 18
**Requirements**: PROT-01 through PROT-08, JPIM-01 through JPIM-07, CHIM-01 through CHIM-05
**Success Criteria** (what must be TRUE):
  1. setMarkedText/insertText forward to CompositionState correctly
  2. firstRectForCharacterRange returns correct screen coordinates (candidate window near cursor)
  3. Japanese: type romaji, see hiragana preedit, Space converts to kanji, Enter commits
  4. Japanese: clause segmentation visible, arrow keys navigate, thick underline on selected clause
  5. Chinese: type pinyin, see preedit, candidates appear, number keys or Space select
**Plans**: 3 plans

Plans:
- [x] 19-01-PLAN.md — NSTextInputClient core methods (setMarkedText, insertText, unmarkText)
- [x] 19-02-PLAN.md — Coordinate bridge for candidate window, clause attribute parsing
- [x] 19-03-PLAN.md — V-side callbacks and preedit rendering

#### Phase 20: Korean + Keyboard Integration
**Goal**: Korean hangul composition works, keyboard edge cases handled
**Depends on**: Phase 19
**Requirements**: KRIM-01 through KRIM-04, KEYB-01 through KEYB-04
**Success Criteria** (what must be TRUE):
  1. Korean jamo composition displays in real-time (typing shows syllable building)
  2. Backspace decomposes syllable correctly (not delete entire syllable)
  3. Dead key composition works after using CJK IME (no state pollution)
  4. Focus loss auto-commits preedit (text not lost)
  5. Undo/redo blocked during active composition (no crash)
**Plans**: 2 plans

Plans:
- [x] 20-01-PLAN.md — Native overlay key forwarding, focus loss handling, IME state cleanup
- [x] 20-02-PLAN.md — V-side keyboard integration (undo blocking, Option+Backspace, Cmd+A)

**Known Issue:** Korean first-keypress fails; works on 2nd+ keypress.

#### Phase 21: Multi-Display & Polish
**Goal**: CJK IME works correctly on multi-monitor and Retina setups
**Depends on**: Phase 20
**Requirements**: DISP-01, DISP-02
**Success Criteria** (what must be TRUE):
  1. Candidate window appears on correct monitor (not jumping to primary)
  2. Coordinate transforms work with Retina displays (no 2x offset)
  3. All three CJK IMEs complete basic flow end-to-end
**Plans**: TBD

Plans:
- [ ] 21-01: TBD

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
| 12. Selection | v1.3 | 2/2 | Complete | 2026-02-02 |
| 13. Text Mutation | v1.3 | 2/2 | Complete | 2026-02-03 |
| 14. Undo/Redo | v1.3 | 2/2 | Complete | 2026-02-03 |
| 15. IME Integration | v1.3 | 3/3 | Partial | 2026-02-03 |
| 16. API & Demo | v1.3 | 2/2 | Complete | 2026-02-03 |
| 17. Accessibility | v1.3 | 2/2 | Complete | 2026-02-03 |
| 18. Overlay Infrastructure | v1.4 | 1/1 | Complete | 2026-02-03 |
| 19. NSTextInputClient + JP/CH | v1.4 | 3/3 | Complete | 2026-02-04 |
| 20. Korean + Keyboard | v1.4 | 2/2 | Partial* | 2026-02-04 |
| 21. Multi-Display & Polish | v1.4 | 0/? | Not started | - |

---
*Last updated: 2026-02-04 after Phase 20 execution*
