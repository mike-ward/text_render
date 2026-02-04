---
phase: 21-multi-display-polish
plan: 01
subsystem: ime
tags: [objc, macos, ime, coordinate-transform, multi-monitor, retina]

# Dependency graph
requires:
  - phase: 19-composition-rendering
    provides: ime_overlay_darwin.m convertRectToScreen pattern
provides:
  - Fixed multi-monitor coordinate handling in ime_bridge_macos.m
  - Both IME files use consistent convertRectToScreen pattern
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "convertRectToScreen for multi-monitor coordinate transforms"

key-files:
  created: []
  modified:
    - ime_bridge_macos.m

key-decisions:
  - "NSZeroRect fallback instead of hardcoded position on failure"

patterns-established:
  - "Always use convertRect:toView:nil then convertRectToScreen: for screen coords"
  - "Never use [[NSScreen screens] firstObject] for coordinate calculations"

# Metrics
duration: 3min
completed: 2026-02-04
---

# Phase 21 Plan 01: Multi-Monitor IME Coordinate Fix Summary

**Fixed IME candidate window positioning on external monitors via convertRectToScreen pattern**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-04
- **Completed:** 2026-02-04
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Fixed ime_bridge_macos.m firstRectForCharacterRange to use convertRectToScreen
- Verified ime_overlay_darwin.m already correct (Phase 19 implementation)
- Removed hardcoded screen reference that caused wrong-monitor positioning

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix firstRectForCharacterRange** - `e8c4f8b` (fix)
2. **Task 2: Verify ime_overlay_darwin.m** - no commit needed (already correct)

## Files Created/Modified

- `ime_bridge_macos.m` - Fixed coordinate transform in firstRectForCharacterRange

## Decisions Made

- Return NSZeroRect on failure instead of hardcoded fallback position (IME will use default)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Multi-monitor coordinate handling fixed for global callback API
- Ready for Phase 21 Plan 02 (if any) or manual testing

---
*Phase: 21-multi-display-polish*
*Completed: 2026-02-04*
