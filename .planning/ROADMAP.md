# Roadmap: VGlyph

## Milestones

- v1.0 Memory Safety — Phases 1-3 (shipped 2026-02-02)
- v1.1 Fragile Area Hardening — Phases 4-7 (shipped 2026-02-02)
- v1.2 Performance Optimization — Phases 8-10 (shipped 2026-02-02)
- v1.3 Text Editing — Phases 11-17 (shipped 2026-02-03)
- v1.4 CJK IME — Phases 18-21 (shipped 2026-02-04)
- v1.5 Codebase Quality Audit — Phases 22-25 (shipped 2026-02-04)
- v1.6 Performance Optimization — Phases 26-29 (shipped 2026-02-05)
- v1.7 Stabilization — Phases 30-32 (shipped 2026-02-05)
- v1.8 Overlay API Activation — Phases 33-34 (in progress)

## Phases

<details>
<summary>v1.0 Memory Safety (Phases 1-3) — SHIPPED 2026-02-02</summary>

- [x] Phase 1: Error Propagation (1/1 plans) — completed 2026-02-01
- [x] Phase 2: Memory Safety (1/1 plans) — completed 2026-02-01
- [x] Phase 3: Layout Safety (1/1 plans) — completed 2026-02-02

</details>

<details>
<summary>v1.1 Fragile Area Hardening (Phases 4-7)
— SHIPPED 2026-02-02</summary>

- [x] Phase 4: Layout Iteration (1/1 plans) — completed 2026-02-02
- [x] Phase 5: Attribute List (1/1 plans) — completed 2026-02-02
- [x] Phase 6: FreeType State (1/1 plans) — completed 2026-02-02
- [x] Phase 7: Vertical Coords (1/1 plans) — completed 2026-02-02

</details>

<details>
<summary>v1.2 Performance Optimization (Phases 8-10)
— SHIPPED 2026-02-02</summary>

- [x] Phase 8: Instrumentation (2/2 plans) — completed 2026-02-02
- [x] Phase 9: Latency Optimizations (3/3 plans)
  — completed 2026-02-02
- [x] Phase 10: Memory Optimization (1/1 plans)
  — completed 2026-02-02

See: .planning/milestones/v1.2-ROADMAP.md for full details.

</details>

<details>
<summary>v1.3 Text Editing (Phases 11-17)
— SHIPPED 2026-02-03</summary>

- [x] Phase 11: Cursor Foundation (2/2 plans)
  — completed 2026-02-02
- [x] Phase 12: Selection (2/2 plans) — completed 2026-02-02
- [x] Phase 13: Text Mutation (2/2 plans) — completed 2026-02-03
- [x] Phase 14: Undo/Redo (2/2 plans) — completed 2026-02-03
- [x] Phase 15: IME Integration (3/3 plans)
  — completed 2026-02-03 (dead keys work)
- [x] Phase 16: API & Demo (2/2 plans) — completed 2026-02-03
- [x] Phase 17: Accessibility (2/2 plans) — completed 2026-02-03

See: .planning/milestones/v1.3-ROADMAP.md for full details.

</details>

<details>
<summary>v1.4 CJK IME (Phases 18-21)
— SHIPPED 2026-02-04</summary>

- [x] Phase 18: Overlay Infrastructure (1/1 plans)
  — completed 2026-02-03
- [x] Phase 19: NSTextInputClient + JP/CH (3/3 plans)
  — completed 2026-02-04
- [x] Phase 20: Korean + Keyboard (2/2 plans)
  — completed 2026-02-04 (partial*)
- [x] Phase 21: Multi-Display & Polish (3/3 plans)
  — completed 2026-02-04

*Korean first-keypress is known macOS bug
(Qt QTBUG-136128, Apple FB17460926, Alacritty #6942)

See: .planning/milestones/v1.4-ROADMAP.md for full details.

</details>

<details>
<summary>v1.5 Codebase Quality Audit (Phases 22-25)
— SHIPPED 2026-02-04</summary>

- [x] Phase 22: Security Audit (4/4 plans) — completed 2026-02-04
- [x] Phase 23: Code Consistency (3/3 plans)
  — completed 2026-02-04
- [x] Phase 24: Documentation (3/3 plans) — completed 2026-02-04
- [x] Phase 25: Verification (1/1 plans) — completed 2026-02-04

See: .planning/milestones/v1.5-ROADMAP.md for full details.

</details>

<details>
<summary>v1.6 Performance Optimization (Phases 26-29)
— SHIPPED 2026-02-05</summary>

- [x] Phase 26: Shelf Packing (2/2 plans) — completed 2026-02-05
- [x] Phase 27: Async Texture Updates (1/1 plan)
  — completed 2026-02-05
- [x] Phase 28: Profiling Validation (1/1 plan)
  — completed 2026-02-05
- [ ] Phase 29: Shape Cache — SKIPPED (LayoutCache 92.3% > 70%)

See: .planning/milestones/v1.6-ROADMAP.md for full details.

</details>

<details>
<summary>v1.7 Stabilization (Phases 30-32)
— SHIPPED 2026-02-05</summary>

- [x] Phase 30: Diagnosis (2/2 plans) — completed 2026-02-05
- [x] Phase 31: Fix (1/1 plans) — completed 2026-02-05
- [x] Phase 32: Verification (1/1 plans) — completed 2026-02-05

See: .planning/milestones/v1.7-ROADMAP.md for full details.

</details>

### v1.8 Overlay API Activation (In Progress)

**Milestone Goal:** Unblock per-overlay IME API by discovering MTKView
from NSWindow, enabling multi-field IME support.

- [ ] Phase 33: Overlay API Wiring
- [ ] Phase 34: Documentation & Verification

#### Phase 33: Overlay API Wiring
**Goal**: editor_demo uses per-overlay IME callbacks via MTKView
discovery, with global fallback intact and cross-platform compilation
preserved
**Depends on**: Phase 32 (v1.7 complete)
**Requirements**: IME-01, IME-02, IME-03, IME-04, IME-06
**Success Criteria** (what must be TRUE):
  1. Obj-C helper walks NSWindow view hierarchy and returns MTKView
     pointer (or null if not found)
  2. editor_demo creates IME overlay from discovered MTKView via
     `vglyph_create_ime_overlay()` and receives IME events through
     per-overlay callbacks
  3. When per-overlay path unavailable, global callback API still
     works identically to v1.7 behavior
  4. `v build` succeeds on Linux without macOS overlay code
     compiling or linking
**Plans**: TBD

Plans:
- [ ] 33-01: TBD

#### Phase 34: Documentation & Verification
**Goal**: Project documentation reflects overlay API activation and
full regression passes
**Depends on**: Phase 33
**Requirements**: IME-05
**Success Criteria** (what must be TRUE):
  1. SECURITY.md documents Obj-C view hierarchy walk and its trust
     boundary
  2. README reflects overlay API as the primary IME integration path
  3. All CJK IME flows (Japanese, Chinese, Korean) work through
     overlay API in editor_demo
**Plans**: TBD

Plans:
- [ ] 34-01: TBD

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
| 15. IME Integration | v1.3 | 3/3 | Complete | 2026-02-03 |
| 16. API & Demo | v1.3 | 2/2 | Complete | 2026-02-03 |
| 17. Accessibility | v1.3 | 2/2 | Complete | 2026-02-03 |
| 18. Overlay Infrastructure | v1.4 | 1/1 | Complete | 2026-02-03 |
| 19. NSTextInputClient | v1.4 | 3/3 | Complete | 2026-02-04 |
| 20. Korean + Keyboard | v1.4 | 2/2 | Partial* | 2026-02-04 |
| 21. Multi-Display & Polish | v1.4 | 3/3 | Complete | 2026-02-04 |
| 22. Security Audit | v1.5 | 4/4 | Complete | 2026-02-04 |
| 23. Code Consistency | v1.5 | 3/3 | Complete | 2026-02-04 |
| 24. Documentation | v1.5 | 3/3 | Complete | 2026-02-04 |
| 25. Verification | v1.5 | 1/1 | Complete | 2026-02-04 |
| 26. Shelf Packing | v1.6 | 2/2 | Complete | 2026-02-05 |
| 27. Async Texture Updates | v1.6 | 1/1 | Complete | 2026-02-05 |
| 28. Profiling Validation | v1.6 | 1/1 | Complete | 2026-02-05 |
| 29. Shape Cache | v1.6 | N/A | Skipped | 2026-02-05 |
| 30. Diagnosis | v1.7 | 2/2 | Complete | 2026-02-05 |
| 31. Fix | v1.7 | 1/1 | Complete | 2026-02-05 |
| 32. Verification | v1.7 | 1/1 | Complete | 2026-02-05 |
| 33. Overlay API Wiring | v1.8 | 0/? | Not started | - |
| 34. Docs & Verification | v1.8 | 0/? | Not started | - |

---
*Last updated: 2026-02-05 — v1.8 roadmap created*
