# VGlyph Memory & Safety Hardening

## What This Is

Addressing 4 memory and safety issues documented in CONCERNS.md for the VGlyph text
rendering library. This hardens unsafe memory operations, adds proper error propagation,
and documents lifetime requirements.

## Core Value

Prevent crashes and undefined behavior from memory safety issues in the glyph atlas
and layout systems.

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

### Active

- [ ] Add null checks after vcalloc in glyph atlas hot paths
- [ ] Validate size calculations prevent integer overflow before allocation
- [ ] Document unsafe pointer cast assumption in Pango iteration
- [ ] Add debug-build runtime validation for Pango pointer cast
- [ ] Replace asserts with error returns in new_glyph_atlas
- [ ] Propagate allocation errors through GlyphAtlas API
- [ ] Document string lifetime requirement for inline object IDs
- [ ] Consider Arena allocation for inline object strings

### Out of Scope

- Performance optimizations — separate concern (CONCERNS.md Performance Bottlenecks)
- Tech debt cleanup — separate concern (CONCERNS.md Tech Debt)
- Test coverage expansion — separate concern (CONCERNS.md Test Coverage Gaps)
- Dependency version pinning — separate concern (CONCERNS.md Dependencies at Risk)

## Context

VGlyph is a V language text rendering library using Pango for shaping and FreeType for
rasterization. The glyph atlas uses unsafe memory operations (vmemcpy, vmemset, vcalloc)
for performance in hot paths. CONCERNS.md audit identified 4 memory/safety issues that
could cause crashes or undefined behavior.

**Files involved:**
- `glyph_atlas.v` — Issues #1, #3 (memory ops, overflow checks)
- `layout.v` — Issues #2, #4 (pointer cast, string lifetime)

## Constraints

- **API Change**: new_glyph_atlas will return `!GlyphAtlas` instead of `GlyphAtlas`
- **V Language**: Must use V's error handling idioms (`!` return type, `or` blocks)
- **Performance**: Null checks in hot paths should be minimal overhead

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Return errors vs panic | Graceful degradation in production | — Pending |
| Debug-only validation | Runtime overhead acceptable only in debug | — Pending |
| Document vs Arena | Arena adds complexity for string lifetime | — Pending |

---
*Last updated: 2026-02-01 after initialization*
