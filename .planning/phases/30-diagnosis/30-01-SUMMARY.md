---
phase: 30-diagnosis
plan: 01
subsystem: rendering
tags: [v, opengl, metal, gpu, texture-atlas, async, diagnostics, stress-testing]

# Dependency graph
requires:
  - phase: 27-async-texture-updates
    provides: Double-buffered staging with async commit
  - phase: 26-shelf-packing
    provides: Shelf-based atlas allocation
provides:
  - Diagnostic instrumentation behind $if diag flag (swap, reset, commit logging)
  - Automated scroll stress test with -d diag flag
  - Async/sync kill switch via -d diag_sync flag
  - Empirical async vs sync comparison data
affects: [31-root-cause, 32-regression-fix]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "$if diag ? for zero-cost diagnostic logging"
    - "Automated stress testing via compile-time flags"
    - "Kill switch pattern for isolating suspect code paths"

key-files:
  created: []
  modified:
    - glyph_atlas.v
    - renderer.v
    - api.v
    - examples/stress_demo.v

key-decisions:
  - "All diagnostic code behind $if diag ? to ensure zero overhead in release builds"
  - "Automated scroll (toggle every 10 frames) to reliably trigger LRU eviction"
  - "Kill switch accessed via set_async_uploads_diag() method for diag builds"

patterns-established:
  - "Buffer state logging: sample first 16 bytes pre/post swap, check identity"
  - "Frame counter tracking for correlating events across subsystems"
  - "Async vs sync comparison via compile-time flags (-d diag vs -d diag_sync)"

# Metrics
duration: 3min
completed: 2026-02-05
---

# Phase 30 Plan 01: Diagnosis Summary

**Diagnostic instrumentation in async upload path with automated scroll stress test and
async/sync kill switch comparison**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-05T15:34:33Z
- **Completed:** 2026-02-05T15:37:51Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Added buffer state logging in swap_staging_buffers (pre/post swap, identical check)
- Added reset_page and commit() path logging behind $if diag ?
- Implemented automated scroll stress mode (toggle every 10 frames via -d diag)
- Added async/sync kill switch via -d diag_sync flag
- Ran empirical comparison: async shows swap ping-pong, sync shows direct copy

## Task Commits

Each task was committed atomically:

1. **Task 1: Add diagnostic instrumentation** - `a9f16c8` (feat)
   - **Fix for Task 1** - `db1d1cc` (fix) - Corrected .min() syntax to if-else
2. **Task 2: Add automated scroll stress mode** - `803311b` (feat)

**Task 3:** Test execution (no commit - observational)

## Files Created/Modified

- `glyph_atlas.v` - Added swap_staging_buffers() and reset_page() diagnostics
- `renderer.v` - Added commit() async/sync path logging with stale buffer detection
- `api.v` - Added set_async_uploads_diag() method for diagnostic builds
- `examples/stress_demo.v` - Added frame_count, automated scroll, and kill switch

## Decisions Made

- **Diagnostic flag strategy:** All instrumentation behind `$if diag ?` for zero overhead
- **Sample size:** First 16 bytes of staging buffers (balance between info and output size)
- **Scroll frequency:** Every 10 frames (produces rapid scroll thrashing for LRU stress)
- **Kill switch access:** Created set_async_uploads_diag() instead of direct field access
  (maintains encapsulation even in diagnostic builds)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed .min() method syntax error**

- **Found during:** Task 1 (diagnostic build compilation)
- **Issue:** V doesn't support .min() method on integer literals
  (`16.min(page.staging_front.len)` failed)
- **Fix:** Replaced with if-else: `if page.staging_front.len < 16 { ... } else { 16 }`
- **Files modified:** glyph_atlas.v, renderer.v
- **Verification:** v -d diag build succeeds
- **Committed in:** db1d1cc (fix commit)

**2. [Rule 3 - Blocking] Removed unused variable warning**

- **Found during:** Task 2 (diag build compilation)
- **Issue:** `cache_entries := 0` in reset_page diagnostic block unused (would need
  renderer context)
- **Fix:** Removed unused variable, kept meaningful diagnostics (page, frame, shelves)
- **Files modified:** glyph_atlas.v
- **Verification:** v -d diag build succeeds without warnings
- **Committed in:** db1d1cc (fix commit)

**3. [Rule 3 - Blocking] Added set_async_uploads_diag() for field access**

- **Found during:** Task 2 (diag_sync build compilation)
- **Issue:** `app.ts.renderer.atlas.async_uploads` field access failed (renderer/atlas
  not pub)
- **Fix:** Added `set_async_uploads_diag()` pub method in api.v behind `$if diag ?`
- **Files modified:** api.v, examples/stress_demo.v
- **Verification:** v -d diag_sync build succeeds
- **Committed in:** db1d1cc (fix commit)

---

**Total deviations:** 3 auto-fixed (3 blocking)
**Impact on plan:** All auto-fixes necessary for compilation. No scope changes.

## Issues Encountered

None beyond syntax corrections (all handled via deviation rules).

## Empirical Findings

**Async mode (v -d diag):**

- Buffer swaps occur (front/back exchange with different data)
- Uploads infrequent (frames 442, 4922 in 5-sec window)
- No identical buffer warnings observed
- No atlas resets in test window

**Sync mode (v -d diag -d diag_sync):**

- No buffer swaps (direct staging_back → image.data copy)
- Uploads frequent (every few hundred frames)
- Clean diagnostic output

**Key observation:** Both modes run without errors or warnings during automated scroll.
No immediate evidence of buffer identity issues or stale data. Further testing needed
with longer runs to trigger atlas resets (LRU eviction).

## Next Phase Readiness

- Diagnostic instrumentation operational and verified
- Stress test reproduces scroll range traversal (6000 glyphs, rapid toggle)
- Kill switch isolates async path for targeted testing
- Ready for Phase 31 (root cause documentation) with empirical data

**Blockers:** None

**Concerns:** Test window too short to trigger atlas reset (LRU eviction). Longer runs
or higher glyph density may be needed to expose blank region symptoms.

---

_Phase: 30-diagnosis_
_Completed: 2026-02-05_
