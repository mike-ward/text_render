# Phase 33: Overlay API Wiring - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire per-overlay IME callbacks through MTKView discovery so editor_demo
uses the overlay API path instead of global callbacks. Global fallback
must remain intact. Cross-platform compilation preserved.

</domain>

<decisions>
## Implementation Decisions

### Discovery behavior
- Discover MTKView at overlay creation time (in
  `vglyph_create_ime_overlay()`), not lazily
- If MTKView not found, return hard error — caller must handle
  explicitly
- Support two paths: auto-discover from NSWindow (default) and
  explicit MTKView pointer for advanced consumers
- Walk depth: Claude's discretion based on actual view hierarchy

### Fallback strategy
- Per-overlay and global callbacks coexist at runtime
- Global callbacks remain the default for consumers without overlays
- Per-overlay callbacks take precedence when an overlay is present
- On overlay destroy: force-cancel any active IME composition (don't
  route to global — state mismatch risk)
- editor_demo goes straight to per-overlay from init (no
  global→upgrade migration)

### Demo integration
- Status text rendered in the demo area showing active IME path
  ("overlay" vs "global")
- `--global-ime` command-line flag to skip overlay discovery and
  force global callbacks (regression testing)
- Two independent text fields with separate overlays to prove
  multi-field support

### Cross-platform guards
- Stub functions on Linux — overlay API exists but returns error
  codes, callers compile and link
- Overlay tests skip on Linux, Linux only verifies compilation
- Public headers use opaque pointers only — no macOS types
  (MTKView*, etc.) leak into headers

### Claude's Discretion
- View hierarchy walk depth (recursive vs direct subviews)
- Obj-C discovery code file organization (separate .m or in
  existing overlay .m)
- Exact status text placement and formatting in editor_demo
- Stub function error code values

</decisions>

<specifics>
## Specific Ideas

- Hard error on discovery failure rather than silent fallback —
  caller should know explicitly when per-overlay isn't available
- Two-field demo to prove multi-field IME works, not just
  single-field passthrough
- Cancel-on-destroy for clean state management rather than
  cross-handler routing

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 33-overlay-api-wiring*
*Context gathered: 2026-02-05*
