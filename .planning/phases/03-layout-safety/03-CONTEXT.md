# Phase 3: Layout Safety - Context

**Gathered:** 2026-02-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Document unsafe pointer cast at layout.v:156 and fix object.id string lifetime issue. Pointer
cast gets brief documentation and debug validation. String lifetime fixed with manual clone/free.

</domain>

<decisions>
## Implementation Decisions

### Pointer cast documentation
- Brief inline comment (1-2 lines)
- Include URL to Pango docs explaining iterator behavior
- Don't mention what could break the assumption — keep it simple
- State why it's safe, not risks

### Debug validation
- Panic with message on validation failure (not assert, not log)
- Simple panic message without pointer address
- Skip cloning empty/null object.id strings

### String lifetime
- Manual clone() and free in Layout.destroy()
- Skip cloning if object.id is empty or null

### Claude's Discretion
- Exact comment placement (above line or trailing)
- How thorough validation check should be (null check vs struct field check)
- Data structure for tracking cloned strings (array, list, etc.)
- Build scope for debug validation ($if debug vs $if debug || test)
- Whether to nullify pointers after free for safety

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-layout-safety*
*Context gathered: 2026-02-01*
