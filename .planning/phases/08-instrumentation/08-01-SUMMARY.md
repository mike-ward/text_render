---
phase: 08-instrumentation
plan: 01
subsystem: profiling
tags: [profiling, timing, conditional-compilation, zero-overhead]

# Dependency graph
requires:
  - phase: 06-freetype-state
    provides: Debug validation pattern ($if debug {})
provides:
  - ProfileMetrics struct for timing accumulation
  - Defer-based timing in 4 hot paths
  - Zero release overhead via $if profile ?
affects: [08-02, 09-atlas, 10-optimization]

# Tech tracking
tech-stack:
  added: [time.sys_mono_now()]
  patterns: ["$if profile ? { timing instrumentation }"]

key-files:
  created: []
  modified: [context.v, layout.v, glyph_atlas.v, renderer.v]

key-decisions:
  - "Timing fields always exist in structs; only accessed in profile builds"
  - "ProfileMetrics struct conditionally compiled; unavailable in release"
  - "Defer-based timing for accurate measurement with early returns"

patterns-established:
  - "Profile timing: $if profile ? { start := time.sys_mono_now(); defer { field += ... } }"
  - "Timing fields in struct: pub mut, unconditional, accessed only in $if profile ?"

# Metrics
duration: 12min
completed: 2026-02-02
---

# Phase 8 Plan 01: Profiling Instrumentation Summary

**ProfileMetrics struct and defer-based timing in 4 hot paths with zero release overhead via $if
profile ? conditional compilation**

## Performance

- **Duration:** 12 min
- **Started:** 2026-02-02
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- ProfileMetrics struct with 4 timing fields (layout, rasterize, upload, draw)
- Defer-based timing in layout_text(), layout_rich_text(), load_glyph(), commit(), draw_layout(),
  draw_layout_rotated()
- Zero release overhead confirmed - ProfileMetrics inaccessible without -d profile flag
- All existing tests pass

## Task Commits

1. **Task 1: Add ProfileMetrics struct to context.v** - `37312c4` (feat)
2. **Task 2: Instrument hot paths with defer-based timing** - `8973f6e` (feat)
3. **Task 3: Verify zero release overhead** - verification only, no code changes

## Files Modified

- `context.v` - ProfileMetrics struct ($if profile ?), layout_time_ns field in Context
- `layout.v` - Timing in layout_text() and layout_rich_text()
- `glyph_atlas.v` - Timing in load_glyph() for rasterize phase
- `renderer.v` - Timing fields in Renderer, timing in commit() and draw_layout*()

## Decisions Made

1. **Fields always exist, conditionally accessed:** V doesn't allow $if inside struct definitions.
   Timing fields exist in both builds but are only updated inside $if profile ? blocks. Memory
   overhead is minimal (few i64 fields).

2. **ProfileMetrics struct conditionally compiled:** The struct itself is behind $if profile ?,
   making it unavailable in release builds. This provides a clean API boundary.

3. **Timing fields split between Context and Renderer:** Context holds layout_time_ns (updated by
   layout_text/layout_rich_text), Renderer holds rasterize/upload/draw times (updated by
   load_glyph/commit/draw_layout).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] V doesn't allow conditional fields in structs**
- **Found during:** Task 1 (adding profile_metrics field to Context)
- **Issue:** Plan specified `$if profile ? { pub mut: profile_metrics ProfileMetrics }` inside
  struct, but V compiler doesn't support conditional compilation inside struct definitions
- **Fix:** Changed pattern to: timing fields always exist unconditionally, but are only
  accessed/updated inside $if profile ? blocks
- **Files modified:** context.v, renderer.v
- **Verification:** Both profile and release builds compile successfully
- **Committed in:** 37312c4 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minor pattern adjustment. Zero overhead still achieved - the unconditional
fields take minimal memory but timing code is completely removed in release builds.

## Issues Encountered

None - after fixing the conditional compilation pattern, all tasks completed smoothly.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ProfileMetrics struct ready for Plan 02 to add cache/atlas statistics fields
- Timing instrumentation pattern established for future profiling work
- INST-01 (zero release overhead) partially satisfied
- INST-02 (frame time breakdown) partially satisfied - captures 4 phases

---
*Phase: 08-instrumentation*
*Completed: 2026-02-02*
