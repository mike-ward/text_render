# Roadmap: VGlyph

## Milestones

- ✅ **v1.0 Memory Safety** — Phases 1-3 (shipped 2026-02-02)
- ✅ **v1.1 Fragile Area Hardening** — Phases 4-7 (shipped 2026-02-02)
- ✅ **v1.2 Performance Optimization** — Phases 8-10 (shipped 2026-02-02)
- ✅ **v1.3 Text Editing** — Phases 11-17 (shipped 2026-02-03)
- ✅ **v1.4 CJK IME** — Phases 18-21 (shipped 2026-02-04, Korean first-keypress known issue)
- 🔄 **v1.5 Codebase Quality Audit** — Phases 22-25

## Phases

<details>
<summary>✅ v1.0 Memory Safety (Phases 1-3) — SHIPPED 2026-02-02</summary>

- [x] Phase 1: Error Propagation (1/1 plans) — completed 2026-02-01
- [x] Phase 2: Memory Safety (1/1 plans) — completed 2026-02-01
- [x] Phase 3: Layout Safety (1/1 plans) — completed 2026-02-02

</details>

<details>
<summary>✅ v1.1 Fragile Area Hardening (Phases 4-7) — SHIPPED 2026-02-02</summary>

- [x] Phase 4: Layout Iteration (1/1 plans) — completed 2026-02-02
- [x] Phase 5: Attribute List (1/1 plans) — completed 2026-02-02
- [x] Phase 6: FreeType State (1/1 plans) — completed 2026-02-02
- [x] Phase 7: Vertical Coords (1/1 plans) — completed 2026-02-02

</details>

<details>
<summary>✅ v1.2 Performance Optimization (Phases 8-10) — SHIPPED 2026-02-02</summary>

- [x] Phase 8: Instrumentation (2/2 plans) — completed 2026-02-02
- [x] Phase 9: Latency Optimizations (3/3 plans) — completed 2026-02-02
- [x] Phase 10: Memory Optimization (1/1 plans) — completed 2026-02-02

See: .planning/milestones/v1.2-ROADMAP.md for full details.

</details>

<details>
<summary>✅ v1.3 Text Editing (Phases 11-17) — SHIPPED 2026-02-03</summary>

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
<summary>✅ v1.4 CJK IME (Phases 18-21) — SHIPPED 2026-02-04</summary>

- [x] Phase 18: Overlay Infrastructure (1/1 plans) — completed 2026-02-03
- [x] Phase 19: NSTextInputClient + JP/CH (3/3 plans) — completed 2026-02-04
- [x] Phase 20: Korean + Keyboard (2/2 plans) — completed 2026-02-04 (partial*)
- [x] Phase 21: Multi-Display & Polish (3/3 plans) — completed 2026-02-04

*Korean first-keypress is known macOS bug (Qt QTBUG-136128, Apple FB17460926, Alacritty #6942)

See: .planning/milestones/v1.4-ROADMAP.md for full details.

</details>

<details open>
<summary>🔄 v1.5 Codebase Quality Audit (Phases 22-25)</summary>

### Phase 22: Security Audit

**Goal:** All input paths validated, all error paths verified, all resources properly cleaned up

**Dependencies:** None (start of milestone)

**Requirements:** SEC-01, SEC-02, SEC-03, SEC-04, SEC-05, SEC-06, SEC-07, SEC-08, SEC-09, SEC-10,
SEC-11

**Success Criteria:**
1. User can pass malformed UTF-8 text without crash or memory corruption
2. User can pass invalid font paths without crash or file system access outside allowed paths
3. User can pass extreme numeric values (0, negative, MAX_INT) without overflow or undefined behavior
4. All public API functions return proper errors on invalid input (no silent failures)
5. Memory profiler shows no leaks in error paths (FreeType handles, Pango objects, atlas resources)

---

### Phase 23: Code Consistency

**Goal:** Codebase follows uniform conventions for naming, structure, and formatting

**Dependencies:** Phase 22 (security fixes may change code being audited)

**Requirements:** CON-01, CON-02, CON-03, CON-04, CON-05, CON-06, CON-07, CON-08, CON-09

**Success Criteria:**
1. All source files formatted with `v fmt -w` (no diff after running)
2. All test files follow `_*.v` naming pattern
3. Grep for naming patterns shows consistent conventions (no mixed snake_case/camelCase)
4. Error handling uses V idioms consistently (`!` returns, `or` blocks, no bare panics)
5. No source lines exceed 99 characters

---

### Phase 24: Documentation

**Goal:** Documentation accurately reflects current implementation

**Dependencies:** Phase 22, 23 (document after code is stabilized)

**Requirements:** DOC-01, DOC-02, DOC-03, DOC-04, DOC-05, DOC-06, DOC-07, DOC-08

**Success Criteria:**
1. User can follow README build instructions and successfully compile on fresh checkout
2. All public API doc comments match actual function signatures and behavior
3. Example files each have header comment explaining what they demonstrate
4. Complex algorithms (shaping, layout, atlas packing) have inline comments explaining approach

---

### Phase 25: Verification

**Goal:** All tests pass and manual smoke tests confirm functionality

**Dependencies:** Phase 22, 23, 24 (verify after all fixes)

**Requirements:** VER-01, VER-02, VER-03, VER-04, VER-05, VER-06

**Success Criteria:**
1. `v test .` passes with 100% of tests green
2. All example programs run without errors or warnings
3. Manual test: text renders correctly at various sizes and with different fonts
4. Manual test: text editing (cursor, selection, insert, delete, undo/redo) works
5. Manual test: IME input (dead keys, CJK composition) produces correct characters

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
| 22. Security Audit | v1.5 | 0/? | Pending | — |
| 23. Code Consistency | v1.5 | 0/? | Pending | — |
| 24. Documentation | v1.5 | 0/? | Pending | — |
| 25. Verification | v1.5 | 0/? | Pending | — |

---
*Last updated: 2026-02-04 after v1.5 roadmap creation*
