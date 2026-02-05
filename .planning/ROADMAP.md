# Roadmap: VGlyph

## Milestones

- **v1.0 Memory Safety** — Phases 1-3 (shipped 2026-02-02)
- **v1.1 Fragile Area Hardening** — Phases 4-7 (shipped 2026-02-02)
- **v1.2 Performance Optimization** — Phases 8-10 (shipped 2026-02-02)
- **v1.3 Text Editing** — Phases 11-17 (shipped 2026-02-03)
- **v1.4 CJK IME** — Phases 18-21 (shipped 2026-02-04, Korean first-keypress known issue)
- **v1.5 Codebase Quality Audit** — Phases 22-25 (shipped 2026-02-04)
- **v1.6 Performance Optimization** — Phases 26-29 (in progress)

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
- [x] Phase 15: IME Integration (3/3 plans) — completed 2026-02-03 (dead keys work)
- [x] Phase 16: API & Demo (2/2 plans) — completed 2026-02-03
- [x] Phase 17: Accessibility (2/2 plans) — completed 2026-02-03

See: .planning/milestones/v1.3-ROADMAP.md for full details.

</details>

<details>
<summary>v1.4 CJK IME (Phases 18-21) — SHIPPED 2026-02-04</summary>

- [x] Phase 18: Overlay Infrastructure (1/1 plans) — completed 2026-02-03
- [x] Phase 19: NSTextInputClient + JP/CH (3/3 plans) — completed 2026-02-04
- [x] Phase 20: Korean + Keyboard (2/2 plans) — completed 2026-02-04 (partial*)
- [x] Phase 21: Multi-Display & Polish (3/3 plans) — completed 2026-02-04

*Korean first-keypress is known macOS bug (Qt QTBUG-136128, Apple FB17460926, Alacritty #6942)

See: .planning/milestones/v1.4-ROADMAP.md for full details.

</details>

<details>
<summary>v1.5 Codebase Quality Audit (Phases 22-25) — SHIPPED 2026-02-04</summary>

- [x] Phase 22: Security Audit (4/4 plans) — completed 2026-02-04
- [x] Phase 23: Code Consistency (3/3 plans) — completed 2026-02-04
- [x] Phase 24: Documentation (3/3 plans) — completed 2026-02-04
- [x] Phase 25: Verification (1/1 plans) — completed 2026-02-04

See: .planning/milestones/v1.5-ROADMAP.md for full details.

</details>

### v1.6 Performance Optimization (In Progress)

**Milestone Goal:** Production-ready performance with efficient atlas allocation, non-blocking
GPU uploads, and HarfBuzz shaping optimization.

#### Phase 26: Shelf Packing

**Goal:** Atlas pages use shelf-based allocation with best-height-fit algorithm

**Depends on:** Phase 25

**Requirements:** ATLAS-01, ATLAS-02, ATLAS-03

**Success Criteria** (what must be TRUE):
  1. Atlas pages allocate glyphs using shelf best-height-fit algorithm
  2. Atlas utilization exceeds 75% on typical text (measured via -d profile)
  3. Page-level LRU eviction behavior preserved (no regressions)
  4. Shelf boundaries visible in atlas_debug example output

**Plans:** 2 plans

Plans:
- [x] 26-01-PLAN.md — Shelf BHF allocation algorithm
- [x] 26-02-PLAN.md — Debug visualization

#### Phase 27: Async Texture Updates

**Goal:** GPU uploads overlapped with CPU rasterization via double-buffered staging

**Depends on:** Phase 26

**Requirements:** GPU-01, GPU-02, GPU-03

**Success Criteria** (what must be TRUE):
  1. Texture uploads use double-buffered pixel staging per atlas page
  2. CPU rasterization overlaps with GPU upload (no blocking)
  3. commit() → draw ordering preserved (no frame corruption)
  4. Upload time visible in -d profile metrics

**Plans:** TBD

Plans:
- [ ] 27-01: TBD

#### Phase 28: Profiling Validation

**Goal:** Measure optimization impact and decide on shape cache need

**Depends on:** Phase 27

**Requirements:** PROF-01, PROF-02

**Success Criteria** (what must be TRUE):
  1. LayoutCache hit rate tracked in -d profile output
  2. Atlas utilization improvements measured (shelf vs old row-based)
  3. Upload time improvements measured (async vs old sync)
  4. Decision made on SHAPE-01 based on LayoutCache hit rate threshold

**Plans:** TBD

Plans:
- [ ] 28-01: TBD

#### Phase 29: Shape Cache (Conditional)

**Goal:** HarfBuzz shape plan caching if LayoutCache hit rate below 70%

**Depends on:** Phase 28

**Requirements:** SHAPE-01

**Success Criteria** (what must be TRUE):
  1. CONDITIONAL: Execute only if Phase 28 profiling shows LayoutCache hit rate <70%
  2. If executed: HarfBuzz shape plans cached with LRU eviction (256 entries)
  3. If executed: Shape cache hit rate visible in -d profile metrics
  4. If skipped: SHAPE-01 deferred to future milestone with rationale documented

**Plans:** TBD

Plans:
- [ ] 29-01: TBD (conditional on profiling results)

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
| 19. NSTextInputClient + JP/CH | v1.4 | 3/3 | Complete | 2026-02-04 |
| 20. Korean + Keyboard | v1.4 | 2/2 | Partial* | 2026-02-04 |
| 21. Multi-Display & Polish | v1.4 | 3/3 | Complete | 2026-02-04 |
| 22. Security Audit | v1.5 | 4/4 | Complete | 2026-02-04 |
| 23. Code Consistency | v1.5 | 3/3 | Complete | 2026-02-04 |
| 24. Documentation | v1.5 | 3/3 | Complete | 2026-02-04 |
| 25. Verification | v1.5 | 1/1 | Complete | 2026-02-04 |
| 26. Shelf Packing | v1.6 | 2/2 | Complete | 2026-02-05 |
| 27. Async Texture Updates | v1.6 | 0/? | Not started | - |
| 28. Profiling Validation | v1.6 | 0/? | Not started | - |
| 29. Shape Cache | v1.6 | 0/? | Not started | - |

---
*Last updated: 2026-02-05 — Phase 26 complete (2/2 plans)*
