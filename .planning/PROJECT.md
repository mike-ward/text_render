# VGlyph

## What This Is

Text rendering library for V language using Pango for shaping and FreeType for rasterization.
Atlas-based GPU rendering with layout caching, subpixel positioning, and rich text support.
Includes profiling instrumentation, multi-page atlas, and LRU cache eviction.

## Core Value

Reliable text rendering without crashes or undefined behavior.

## Requirements

### Validated

- Text composition via Pango/HarfBuzz — existing
- Glyph rasterization via FreeType — existing
- Atlas-based GPU rendering — existing
- Layout caching with TTL eviction — existing
- Subpixel positioning (4 bins) — existing
- Rich text with styled runs — existing
- Hit testing and character rect queries — existing
- macOS accessibility integration — existing
- Error-returning GlyphAtlas API (`!GlyphAtlas`) — v1.0
- Dimension/overflow validation before allocation — v1.0
- 1GB max allocation limit with overflow protection — v1.0
- grow() error propagation through insert_bitmap — v1.0
- Pango pointer cast documented with debug validation — v1.0
- Inline object ID string lifetime management — v1.0
- Iterator lifecycle docs and exhaustion guards — v1.1
- AttrList ownership docs and debug leak counter — v1.1
- FreeType state sequence docs and debug validation — v1.1
- Vertical coordinate transform docs and match dispatch — v1.1
- Zero-overhead profiling instrumentation (`-d profile`) — v1.2
- Frame time breakdown (layout/rasterize/upload/draw) — v1.2
- Cache hit/miss tracking (glyph, metrics, layout) — v1.2
- Memory allocation tracking (peak, current) — v1.2
- Atlas utilization metrics (used/total pixels) — v1.2
- Multi-page atlas with LRU page eviction — v1.2
- FreeType metrics cache (256-entry LRU) — v1.2
- Glyph cache collision detection (secondary key) — v1.2
- GPU emoji scaling (destination rect, no CPU bicubic) — v1.2
- Glyph cache LRU eviction (4096 default, configurable) — v1.2

### Active

None — planning next milestone.

### Out of Scope

- Shelf packing allocator — future optimization
- Async texture updates — future optimization
- Shape plan caching — future optimization
- Thread safety — V is single-threaded by design
- SDF rendering — quality feature, not performance
- Pre-rendered atlases — app size bloat

## Context

VGlyph is a V language text rendering library. v1.0 hardened memory operations, v1.1 hardened
fragile areas (iterators, AttrList, FreeType state, vertical coords), v1.2 added performance
instrumentation and optimizations.

**Current State:**
- 5,309 LOC V
- Tech stack: Pango, FreeType, Cairo, OpenGL
- Profiling: `-d profile` flag for timing/cache/atlas metrics
- Atlas: Multi-page (4 max), LRU page eviction
- Caches: Glyph cache (4096 LRU), Metrics cache (256 LRU), Layout cache (TTL)

**Files modified in v1.2:**
- `context.v` — ProfileMetrics struct, MetricsCache, timing fields
- `layout.v` — Layout timing instrumentation
- `glyph_atlas.v` — Multi-page atlas, rasterize timing, atlas tracking
- `renderer.v` — Draw/upload timing, LRU eviction, GPU emoji scaling
- `api.v` — Layout cache tracking, get_profile_metrics() API

## Constraints

- **API Change**: new_glyph_atlas returns `!GlyphAtlas` instead of `GlyphAtlas`
- **V Language**: Uses V's error handling idioms (`!` return type, `or` blocks)
- **Profile builds**: Fields exist unconditionally (V limitation), accessed only in `-d profile`

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Return errors vs panic | Graceful degradation in production | Good - errors propagate cleanly |
| Debug-only validation | Runtime overhead acceptable only in debug | Good - catch issues in dev |
| Clone strings vs Arena | Arena adds complexity for string lifetime | Good - simple clone/free pattern |
| `or { panic(err) }` in renderer | Atlas failure unrecoverable at init | Good - matches existing examples |
| 1GB max allocation limit | Reasonable bound for glyph atlas | Good - prevents runaway growth |
| Silent errors in grow() | No log.error, just return error | Good - caller decides response |
| Debug-only guards | Zero runtime overhead in release | Good - catches bugs in dev |
| Iterator exhaustion tracking | Prevents reuse after exhaustion | Good - UB caught in debug |
| AttrList leak counter | Debug-only resource tracking | Good - catches leaks in dev |
| FT state validation | Inline docs + debug guards | Good - invalid state caught |
| Match dispatch for orientation | Compiler-verified exhaustiveness | Good - no missing arms |
| Helper function separation | _horizontal/_vertical suffix | Good - clear distinction |
| Timing fields unconditional | V doesn't allow $if in struct defs | Good - minimal memory overhead |
| Separate textures per page | Sokol compatibility (no texture arrays) | Good - works with gg backend |
| Cache key: face XOR size | Simple hash combining | Good - fast and unique |
| Panic on collision in debug | Bugs should be loud | Good - catches hash issues |
| O(n) LRU scan | Simple, sufficient for 4096 entries | Good - no complex data structure |
| GPU emoji scaling | Eliminates CPU bicubic overhead | Good - fast and good quality |

---
*Last updated: 2026-02-02 after v1.2 milestone complete*
