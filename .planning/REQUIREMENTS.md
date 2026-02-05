# Requirements: VGlyph v1.6 Performance Optimization

**Defined:** 2026-02-04
**Core Value:** Reliable text rendering without crashes or undefined behavior

## v1.6 Requirements

Requirements for performance optimization milestone. Each maps to roadmap phases.

### Atlas Optimization

- [x] **ATLAS-01**: Shelf packing allocator with best-height-fit algorithm
- [x] **ATLAS-02**: Per-row shelf tracking for atlas pages
- [x] **ATLAS-03**: Preserve existing page-level LRU eviction behavior

### GPU Pipeline

- [ ] **GPU-01**: Double-buffered pixel staging for texture uploads
- [ ] **GPU-02**: CPU/GPU overlap during glyph rasterization
- [ ] **GPU-03**: Preserve commit() → draw ordering

### Profiling

- [ ] **PROF-01**: LayoutCache hit rate measurement (before shape cache decision)
- [ ] **PROF-02**: Atlas utilization metrics (validate shelf packing improvement)

### Shape Caching (Conditional)

- [ ] **SHAPE-01**: HarfBuzz shape plan caching (only if LayoutCache hit rate < 70%)

## Future Requirements

Deferred to post-v1.6. Tracked but not in current roadmap.

### Advanced Atlas

- **ATLAS-04**: Multiple shelf height bins (small/medium/large glyphs)
- **ATLAS-05**: Per-page staging buffers

### Advanced Profiling

- **PROF-03**: Upload time breakdown metrics
- **PROF-04**: Shape cache hit rate tracking

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Runtime defragmentation | Causes frame stalls, not suitable for real-time rendering |
| Guillotine cutting | Overcomplicated for text atlases, shelf packing sufficient |
| Multi-threaded uploads | V is single-threaded by design |
| PBO complexity | Sokol abstracts this, double-buffering sufficient |
| Thread-safe caching | Not needed for single-threaded design |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ATLAS-01 | Phase 26 | Complete |
| ATLAS-02 | Phase 26 | Complete |
| ATLAS-03 | Phase 26 | Complete |
| GPU-01 | Phase 27 | Pending |
| GPU-02 | Phase 27 | Pending |
| GPU-03 | Phase 27 | Pending |
| PROF-01 | Phase 28 | Pending |
| PROF-02 | Phase 28 | Pending |
| SHAPE-01 | Phase 29 | Conditional |

**Coverage:**
- v1.6 requirements: 9 total
- Mapped to phases: 9
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-04*
*Last updated: 2026-02-05 — ATLAS-01/02/03 complete (Phase 26)*
