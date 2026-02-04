---
phase: 19-nstextinputclient-jpch
plan: 02
subsystem: ime
tags: [nstextinputclient, objc, coordinate-transform, clause-parsing]

# Dependency graph
requires:
  - phase: 19-01
    provides: VGlyphIMECallbacks with marked/insert/unmark callbacks
provides:
  - firstRectForCharacterRange with view-to-screen coordinate transform
  - on_get_bounds callback for candidate window positioning
  - Clause attribute parsing from NSAttributedString underline styles
  - on_clause/on_clauses_begin/on_clauses_end callbacks
affects: [19-03, composition-rendering]

# Tech tracking
tech-stack:
  added: []
  patterns: [Y-coordinate flip for macOS bottom-left origin]

key-files:
  created: []
  modified:
    - ime_overlay_darwin.h
    - ime_overlay_darwin.m
    - c_bindings.v

key-decisions:
  - "Thick underline (NSUnderlineStyleThick) maps to selected clause (style=2)"
  - "Other underline styles map to raw clause (style=0)"
  - "Y-flip formula: self.bounds.size.height - y - h"

patterns-established:
  - "Coordinate transform: view -> window -> screen via convertRect:toView:nil then convertRectToScreen"
  - "Clause enumeration bracketed by on_clauses_begin/on_clauses_end"

# Metrics
duration: 8min
completed: 2026-02-03
---

# Phase 19 Plan 02: Coordinate Bridge Summary

**firstRectForCharacterRange with screen coord transform and clause attribute parsing from
NSAttributedString underline styles**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-03T18:44:00Z
- **Completed:** 2026-02-03T18:52:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- on_get_bounds callback for V-side composition bounds
- firstRectForCharacterRange transforms view coords to screen coords for IME candidate window
- Y-coordinate flip for macOS bottom-left origin convention
- NSAttributedString underline attribute parsing for clause segmentation
- Clause callbacks (on_clause, on_clauses_begin, on_clauses_end) for V-side rendering

## Task Commits

Each task was committed atomically:

1. **Task 1: Add bounds callback to VGlyphIMECallbacks** - `cb4c0c3` (feat)
2. **Task 2: Implement firstRectForCharacterRange with screen transform** - `117b8a2` (feat)
3. **Task 3: Parse NSAttributedString underline attributes for clause info** - `340de6d` (feat)

## Files Created/Modified
- `ime_overlay_darwin.h` - Added on_get_bounds and clause callbacks to VGlyphIMECallbacks
- `ime_overlay_darwin.m` - Implemented firstRectForCharacterRange and clause parsing in setMarkedText
- `c_bindings.v` - V bindings for bounds and clause callbacks

## Decisions Made
- Thick underline = selected clause (style 2), other underlines = raw (style 0)
- NSZeroRect returned for invalid/missing bounds data (no crash)
- Clause style 1 (converted) not currently mapped - can extend later if IMEs differentiate

## Deviations from Plan
None - plan executed exactly as written

## Issues Encountered
None

## User Setup Required
None - no external service configuration required

## Next Phase Readiness
- Coordinate bridge complete for candidate window positioning
- Clause data available for V-side preedit rendering with style
- Ready for Phase 19-03: Testing and integration

---
*Phase: 19-nstextinputclient-jpch*
*Completed: 2026-02-03*
