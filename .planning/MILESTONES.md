# Project Milestones: VGlyph

## v1.2 Performance Optimization (Shipped: 2026-02-02)

**Delivered:** Performance instrumentation, latency optimizations, and memory management for VGlyph's
rendering pipeline.

**Phases completed:** 8-10 (6 plans total)

**Key accomplishments:**

- Zero-overhead profiling with `-d profile` conditional compilation
- Multi-page texture atlas (4 pages max) with LRU page eviction
- MetricsCache for FreeType font metrics (256-entry LRU)
- GPU emoji scaling via destination rect (no CPU bicubic)
- Glyph cache LRU eviction with configurable max entries (4096 default)
- Unified get_profile_metrics() API aggregating all subsystem metrics

**Stats:**

- 5 files modified (context.v, layout.v, renderer.v, glyph_atlas.v, api.v)
- 5,309 lines of V (+726/-220)
- 3 phases, 6 plans
- 1 day execution (2026-02-02)

**Git range:** `feat(08-01)` → `feat(10-01)`

**What's next:** TBD (run `/gsd:new-milestone`)

---

## v1.1 Fragile Area Hardening (Shipped: 2026-02-02)

**Delivered:** Hardened VGlyph's fragile areas with iterator lifecycle safety, AttrList ownership
clarity, FreeType state validation, and vertical coordinate transform documentation.

**Phases completed:** 4-7 (4 plans total)

**Key accomplishments:**

- Iterator lifecycle docs at all creation sites with debug-only exhaustion guards
- AttrList ownership boundaries documented with debug leak counter
- FreeType load→translate→render sequence documented with debug validation
- Vertical coordinate transforms with inline formulas and match dispatch
- Consistent debug pattern ($if debug {}) across all phases with zero release overhead

**Stats:**

- 2 files modified (layout.v, glyph_atlas.v)
- 8,540 lines of V
- 4 phases, 4 plans, 11 tasks
- 1 day execution (2026-02-02)

**Git range:** `feat(04-01)` → `feat(07-01)`

**What's next:** TBD (run `/gsd:new-milestone`)

---

## v1.0 Memory & Safety Hardening (Shipped: 2026-02-01)

**Delivered:** Hardened VGlyph's memory operations with error propagation, allocation validation, and
proper string lifetime management.

**Phases completed:** 1-3 (3 plans total)

**Key accomplishments:**

- Error-returning GlyphAtlas API with dimension/overflow/allocation validation
- check_allocation_size helper enforcing 1GB limit and overflow protection
- grow() error propagation through insert_bitmap
- Pointer cast documentation with debug-build runtime validation
- String lifetime management for inline object IDs (clone on store, free on destroy)

**Stats:**

- 23 files created/modified
- 8,301 lines of V
- 3 phases, 3 plans, 8 tasks
- 37 days from start to ship

**Git range:** `dcabe59` → `d5104a1`

**What's next:** TBD (run `/gsd:new-milestone`)

---
