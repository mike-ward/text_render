# Phase 10: Memory Optimization - Context

**Gathered:** 2026-02-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Glyph cache memory usage bounded and predictable via LRU eviction with configurable max entries. Atlas space management and advanced packing are separate concerns.

</domain>

<decisions>
## Implementation Decisions

### Default limits
- Default max entries: 4096 glyphs
- Global limit shared across all fonts/sizes (not per-font)
- Cache limit independent of atlas pages — evicted glyphs removed from cache, atlas space left as hole

### Configuration
- Config via struct field (set before init)
- Init-time only — immutable after creation
- Enforce minimum (e.g., 256) — silently clamp small/zero values
- No unbounded option — bounded memory is the point of this phase

### Eviction behavior
- Atlas space left as hole when glyph evicted (simpler, reclaimed when page evicted)
- LRU tracking via frame counters (consistent with existing atlas page LRU pattern)

### Claude's Discretion
- Eviction trigger timing (on insert vs periodic)
- Batch eviction size (one at a time vs percentage)
- Eviction count instrumentation in ProfileMetrics
- Exact minimum value to enforce

</decisions>

<specifics>
## Specific Ideas

- Frame counter pattern already used for atlas page LRU (last_used_frame) — reuse same approach
- Keep it simple: holes in atlas are OK, page eviction eventually reclaims space

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-memory-optimization*
*Context gathered: 2026-02-02*
