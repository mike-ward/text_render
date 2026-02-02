# Phase 9: Latency Optimizations - Context

**Gathered:** 2026-02-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Hot paths execute with minimal stalls and redundant computation. Targets:
- LATENCY-01: Multi-page atlas eliminates mid-frame reset stalls
- LATENCY-02: FreeType metrics cached by (font, size) tuple
- LATENCY-03: Glyph cache validates hash collisions with secondary key
- LATENCY-04: Color emoji scaling uses GPU or cached scaled bitmaps

</domain>

<decisions>
## Implementation Decisions

### Multi-page atlas strategy
- Start with 1 page, grow on demand
- Max 4 pages (~64MB VRAM at 4K per page)
- Always add page if under limit (don't reset)
- When all 4 full: reset oldest page (circular reuse)
- Page size same as current atlas
- Track page age via frame counter (increment on use)
- On page reset: invalidate only that page's glyph cache entries
- Profile metrics: per-page utilization stats
- Lazy texture allocation (only when page needed)
- Fill current page first before adding new page

### Metrics cache scope
- LRU eviction with 256 entry limit

### Collision handling
- Track collision stats in profile metrics
- Debug validation: assert on mismatch (catch wrong glyph lookups in debug builds)

### Emoji scaling
- GPU scaling (upload native resolution, scale in shader)
- Store at native resolution for best quality
- Max emoji bitmap: 256x256
- Linear (bilinear) filtering

### Claude's Discretion
- What FreeType metrics to cache (font-level vs per-glyph)
- Cache key structure for metrics
- Page index storage strategy in glyph cache
- OpenGL texture array vs separate textures
- Secondary key design for collision detection
- Collision action (evict vs probe)

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 09-latency-optimizations*
*Context gathered: 2026-02-02*
