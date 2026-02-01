# Roadmap: VGlyph Memory & Safety Hardening

## Overview

Harden VGlyph's memory operations in 3 phases: first establish error propagation API, then add
memory safety checks that use that API, finally address layout.v pointer and string lifetime
issues. All work targets glyph_atlas.v and layout.v files identified in CONCERNS.md audit.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Error Propagation** - Change new_glyph_atlas to return errors
- [ ] **Phase 2: Memory Safety** - Add null checks and overflow validation
- [ ] **Phase 3: Layout Safety** - Document pointer cast, fix string lifetime

## Phase Details

### Phase 1: Error Propagation
**Goal**: GlyphAtlas API returns errors instead of asserting/crashing
**Depends on**: Nothing (first phase)
**Requirements**: ERR-01, ERR-02, ERR-03, ERR-04, ERR-05
**Success Criteria** (what must be TRUE):
  1. new_glyph_atlas returns `!GlyphAtlas` type
  2. Invalid dimensions (0, negative, overflow) return error instead of assert
  3. Allocation failure returns error instead of assert
  4. All callers handle GlyphAtlas error with `or` blocks
  5. Code compiles with `v -check-syntax`
**Plans**: 1 plan

Plans:
- [ ] 01-01-PLAN.md - Convert new_glyph_atlas to error-returning API

### Phase 2: Memory Safety
**Goal**: All vcalloc calls validated before dereference
**Depends on**: Phase 1 (error propagation mechanism)
**Requirements**: MEM-01, MEM-02, MEM-03, MEM-04, MEM-05
**Success Criteria** (what must be TRUE):
  1. vcalloc at line 72 has null check before use
  2. vcalloc at line 389 has null check before use
  3. vcalloc at line 439 has null check before use
  4. vcalloc at lines 447-450 have null checks before use
  5. Width * height overflow check exists before allocation
**Plans**: TBD

Plans:
- [ ] 02-01: [TBD]

### Phase 3: Layout Safety
**Goal**: Pointer cast documented and validated; string lifetime safe
**Depends on**: Phase 2 (complete glyph_atlas.v first)
**Requirements**: PTR-01, PTR-02, STR-01, STR-02
**Success Criteria** (what must be TRUE):
  1. Unsafe pointer cast at line 156 has documentation comment explaining assumption
  2. Debug build has runtime validation for Pango pointer cast
  3. Object.id string is cloned before storing in Pango attribute
  4. Cloned string is freed when layout is destroyed
**Plans**: TBD

Plans:
- [ ] 03-01: [TBD]

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Error Propagation | 0/1 | Planned | - |
| 2. Memory Safety | 0/? | Not started | - |
| 3. Layout Safety | 0/? | Not started | - |

---
*Roadmap created: 2026-02-01*
