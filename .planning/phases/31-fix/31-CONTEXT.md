# Phase 31: Fix - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Resolve all three v1.6 regression symptoms (scroll flickering, rendering
delays, blank scroll regions) traced to Phase 27's async double-buffer
swap without accumulation. No new features, no scope beyond fixing
regressions.

</domain>

<decisions>
## Implementation Decisions

### Fix vs rollback strategy
- Fix forward first: apply memcpy staging_front → staging_back after swap
- Minimal scope: touch only swap_staging_buffers(), do not audit broader
  commit path
- Fallback: full Phase 27 revert if ANY of the 3 symptoms persists after
  memcpy fix — no partial fixes, no alternate approaches
- Threshold is strict: any remaining symptom triggers revert

### Performance budget
- Memcpy cost is acceptable — correctness over performance for v1.7
- No hard frame-time floor — fix takes priority
- No perf measurement needed — visual correctness is the criterion
- Dirty-only vs all-pages copy scope: Claude's discretion

### Validation criteria
- Manual visual test of stress_demo only (user will test)
- `v test` must pass before fix is considered complete
- Other demos (editor_demo, atlas_debug) deferred to Phase 32
- No automated diag-based validation — user knows the symptoms

### Diagnostic code fate
- Keep all Phase 30 diagnostic instrumentation ($if diag)
- No new diagnostic output from the fix itself — keep changes minimal
- Auto-scroll toggle retention: Claude's discretion
- If full Phase 27 revert needed: also revert Phase 30 diag code that
  references async paths (dead code removal)

### Claude's Discretion
- Whether to memcpy dirty pages only or all pages after swap
- Whether to retain the automated scroll toggle for Phase 32 use

</decisions>

<specifics>
## Specific Ideas

- Fix is exactly as diagnosed: memcpy staging_front → staging_back after
  swap in swap_staging_buffers()
- Sync path does not have this bug and must not be modified
- User will personally validate stress_demo — no checklist needed

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 31-fix*
*Context gathered: 2026-02-05*
