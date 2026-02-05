# Roadmap: VGlyph

## Milestones

- **v1.0 Memory Safety** — Phases 1-3 (shipped 2026-02-02)
- **v1.1 Fragile Area Hardening** — Phases 4-7 (shipped 2026-02-02)
- **v1.2 Performance Optimization** — Phases 8-10 (shipped 2026-02-02)
- **v1.3 Text Editing** — Phases 11-17 (shipped 2026-02-03)
- **v1.4 CJK IME** — Phases 18-21
  (shipped 2026-02-04, Korean first-keypress known issue)
- **v1.5 Codebase Quality Audit** — Phases 22-25 (shipped 2026-02-04)
- **v1.6 Performance Optimization** — Phases 26-29
  (shipped 2026-02-05, P29 skipped)
- **v1.7 Stabilization** — Phases 30-32 (in progress)

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

### v1.7 Stabilization (Phases 30-32) — In Progress

**Milestone Goal:** Fix v1.6 regressions (flickering, delays, blank
regions in stress_demo) without introducing new features.

- [ ] **Phase 30: Diagnosis** - Identify root causes of all three
  regression symptoms
- [ ] **Phase 31: Fix** - Resolve regressions or roll back offending
  v1.6 changes
- [ ] **Phase 32: Verification** - Confirm all demos and tests are
  regression-free

## Phase Details

### Phase 30: Diagnosis
**Goal**: Root causes of all v1.6 regression symptoms are identified
and documented
**Depends on**: Nothing (first phase of v1.7)
**Requirements**: DIAG-01, DIAG-02, DIAG-03
**Success Criteria** (what must be TRUE):
  1. Scroll flickering in stress_demo can be reproduced on demand
     and its trigger mechanism is documented
  2. Rendering delay root cause is traced to a specific v1.6 code
     path (async uploads, shelf packing, or other)
  3. Blank scroll region cause is identified with evidence (logs,
     frame captures, or instrumentation output)
  4. Each symptom is mapped to the specific v1.6 change that
     introduced it (Phase 26, 27, or 28)
**Plans:** 2 plans
Plans:
- [ ] 30-01-PLAN.md — Instrument async path, automated scroll, kill
  switch test
- [ ] 30-02-PLAN.md — Analyze results, document root causes

### Phase 31: Fix
**Goal**: All regression symptoms are resolved in stress_demo
**Depends on**: Phase 30
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04
**Success Criteria** (what must be TRUE):
  1. stress_demo scrolls smoothly without visible flickering
  2. stress_demo renders text without perceptible delays during
     scroll and resize
  3. stress_demo shows no blank regions during or after scrolling
  4. If any root cause was unfixable, the specific v1.6 change is
     rolled back with documented rationale (not a blanket revert)
  5. No new regressions introduced by the fix (existing tests pass)
**Plans**: TBD

### Phase 32: Verification
**Goal**: All demos and tests confirmed regression-free
**Depends on**: Phase 31
**Requirements**: VRFY-01, VRFY-02, VRFY-03, VRFY-04
**Success Criteria** (what must be TRUE):
  1. stress_demo scrolls continuously for 30+ seconds without
     flickering, blanks, or delays
  2. editor_demo text entry, selection, and scrolling work without
     visual artifacts
  3. atlas_debug renders glyph atlas correctly without corruption
  4. `v test` passes with zero failures
**Plans**: TBD

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
| 30. Diagnosis | v1.7 | 0/TBD | Not started | - |
| 31. Fix | v1.7 | 0/TBD | Not started | - |
| 32. Verification | v1.7 | 0/TBD | Not started | - |

---
*Last updated: 2026-02-05 — v1.7 roadmap created*
