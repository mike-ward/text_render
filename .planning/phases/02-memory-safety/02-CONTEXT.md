# Phase 2: Memory Safety - Context

**Gathered:** 2026-02-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Add null checks and overflow validation to all vcalloc calls in glyph_atlas.v. Ensures memory
allocations are validated before dereference. Specific locations: lines 72, 389, 439, 447-450.

</domain>

<decisions>
## Implementation Decisions

### Null check behavior
- Return error to caller (propagate up, like Phase 1 pattern)
- Clean up partial state: if 2nd allocation fails, free 1st allocation before returning error
- Silent errors: return error, let caller decide to log

### Overflow detection
- Enforce reasonable size limit (e.g., 1GB) — reject unreasonably large even if no overflow
- Create shared helper function: check_allocation_size(w, h) used by all vcalloc sites

### Error granularity
- Distinct error types per cause: overflow_error, null_allocation, size_limit_exceeded
- Extend existing GlyphAtlasError enum (don't create new type)
- Developer-focused messages with location info: "allocation failed in resize_atlas at line 389"

### Debug vs release
- All safety checks run in both debug and release builds
- No extra debug-only assertions — just the required null/overflow checks
- Silent errors in all builds (no logging, just return error)

### Claude's Discretion
- How to detect overflow in V (research V idioms)
- Whether to return Result or bool for mutating methods
- Error message format details (whether to include allocation size)
- Exact placement of overflow check (before alloc vs wrapper function)

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard V approaches for memory safety.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-memory-safety*
*Context gathered: 2026-02-01*
