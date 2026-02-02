# VGlyph

## What This Is

Text rendering library for V language using Pango for shaping and FreeType for rasterization.
Atlas-based GPU rendering with layout caching, subpixel positioning, and rich text support.

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

### Active

**v1.2 Performance Optimization**

- [ ] Lightweight profiling instrumentation for key operations
- [ ] Profile layout computation (Pango calls, shaping, cache)
- [ ] Profile atlas operations (rasterization, texture updates)
- [ ] Profile render path (draw calls, batching)
- [ ] Optimize latency based on profiling data
- [ ] Optimize memory based on profiling data
- [ ] Address confirmed CONCERNS.md bottlenecks

### Out of Scope

- Performance optimizations — separate concern (CONCERNS.md)
- Tech debt cleanup — separate concern (CONCERNS.md)
- Test coverage expansion — separate concern (CONCERNS.md)
- Dependency version pinning — separate concern (CONCERNS.md)
- Thread safety — V is single-threaded by design

## Context

VGlyph is a V language text rendering library. v1.0 hardened memory operations, v1.1 hardened
fragile areas (iterators, AttrList, FreeType state, vertical coords) based on CONCERNS.md audit.

**Current State:**
- 8,540 LOC V
- Tech stack: Pango, FreeType, Cairo, OpenGL
- All CONCERNS.md safety issues addressed through v1.1

**Files modified in v1.1:**
- `layout.v` — Iterator lifecycle docs, exhaustion guards, AttrList ownership docs, leak counter,
  coordinate system docs, orientation helpers, match dispatch
- `glyph_atlas.v` — FreeType state sequence docs and debug validation guards
- `_layout_test.v` — Orientation test cases

## Constraints

- **API Change**: new_glyph_atlas returns `!GlyphAtlas` instead of `GlyphAtlas`
- **V Language**: Uses V's error handling idioms (`!` return type, `or` blocks)
- **Performance**: Null checks in hot paths minimal overhead

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

---
*Last updated: 2026-02-02 after v1.2 milestone start*
