---
phase: 21-multi-display-polish
plan: 02
subsystem: ime
tags: [korean, ime, nstextinputclient, macos, composition]

# Dependency graph
requires:
  - phase: 18-ime-foundation
    provides: NSTextInputClient implementation
  - phase: 20-korean-keyboard
    provides: Korean IME investigation results
provides:
  - Korean IME pre-warm workaround in +load
  - discardMarkedText call for Korean state clearing
  - handleEvent before interpretKeyEvents pattern
affects: [future-ime-improvements, korean-localization]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - IME pre-warming via dummy NSTextInputContext in +load
    - handleEvent before interpretKeyEvents for Korean IME

key-files:
  created: []
  modified:
    - ime_bridge_macos.m
    - ime_overlay_darwin.m

key-decisions:
  - "Pre-warm with dummy context rather than real view (less side effects)"
  - "100ms delay before deactivate to allow IME initialization"
  - "handleEvent before interpretKeyEvents (Korean IME may respond differently)"

patterns-established:
  - "Korean IME workaround: pre-warm + discardMarkedText + handleEvent first"

# Metrics
duration: 3min
completed: 2026-02-04
---

# Phase 21 Plan 02: Korean IME First-Keypress Workarounds Summary

**Best-effort Korean IME workarounds: pre-warm in +load, discardMarkedText, handleEvent-first pattern**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-04T19:36:19Z
- **Completed:** 2026-02-04T19:39:16Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added Korean IME pre-warm in +load via dummy NSTextInputContext
- Added discardMarkedText call on first keypress to clear stale state
- Changed to handleEvent before interpretKeyEvents pattern
- Applied same fixes to overlay API for consistency

## Task Commits

Each task was committed atomically:

1. **Task 1: Investigate Korean IME initialization timing** - `dc9824c` (feat)
2. **Task 2: Apply fix to ime_overlay_darwin.m** - `e76e76a` (feat)

## Files Created/Modified

- `ime_bridge_macos.m` - Added Korean IME pre-warm and keyDown fixes
- `ime_overlay_darwin.m` - Applied same Korean IME workarounds

## Decisions Made

1. **Pre-warm approach:** Create dummy NSView + NSTextInputContext in +load via dispatch_async
   to main queue, then deactivate after 100ms. This is less invasive than modifying real views.

2. **discardMarkedText on non-composition:** Call discardMarkedText when not composing to clear
   any stale Korean IME state that might cause first-keypress issues.

3. **handleEvent before interpretKeyEvents:** Korean IME may respond to handleEvent when it
   doesn't respond to interpretKeyEvents. Try handleEvent first, fall back to interpretKeyEvents.

## Deviations from Plan

None - plan executed as specified with all three attempts implemented.

## Known Issue Status

**Korean IME first-keypress issue remains a KNOWN ISSUE with best-effort workarounds.**

The issue is reported across multiple projects:
- Qt QTBUG-136128
- Apple FB17460926
- Alacritty #6942
- Godot #85458 (different issue - insertText+setMarkedText collision)

**Root cause:** Unknown, appears to be macOS Korean IME internal state initialization.

**Workarounds implemented:**
1. Pre-warm NSTextInputContext in +load
2. discardMarkedText on first keypress
3. handleEvent before interpretKeyEvents

**User workaround (if issue persists):**
- Type first character twice, or
- Click away and back to refocus the text field

## Next Phase Readiness

- Both ime_bridge_macos.m and ime_overlay_darwin.m have consistent Korean IME handling
- Japanese and Chinese IME should not be affected (need manual verification)
- If issue still occurs, further investigation requires deeper macOS IME internals knowledge

---
*Phase: 21-multi-display-polish*
*Completed: 2026-02-04*
