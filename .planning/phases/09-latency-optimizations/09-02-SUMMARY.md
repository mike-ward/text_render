---
phase: 09-latency-optimizations
plan: 02
subsystem: rendering
tags: [freetype, pango, lru-cache, collision-detection, font-metrics]

# Dependency graph
requires:
  - phase: 09-01
    provides: Multi-page atlas with page field in CachedGlyph
  - phase: 08
    provides: Profile instrumentation infrastructure
provides:
  - MetricsCache with 256-entry LRU for font metrics
  - Secondary key validation for glyph cache collisions
  - Reduced FreeType/Pango FFI calls via caching
affects: [10-memory-management, future-performance-tuning]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - LRU cache with access_order array
    - Secondary key for hash collision detection

key-files:
  created: []
  modified:
    - context.v
    - renderer.v
    - glyph_atlas.v
    - api.v

key-decisions:
  - "Cache key: face pointer XOR (size_units << 32)"
  - "Secondary key stored in CachedGlyph for debug validation"
  - "Panic on collision in debug builds (not evict-and-reload)"

patterns-established:
  - "LRU cache pattern: entries map + access_order array"
  - "Debug-only validation with $if debug"

# Metrics
duration: 12min
completed: 2026-02-02
---

# Phase 09 Plan 02: Metrics Cache and Collision Detection Summary

**MetricsCache with 256-entry LRU reduces FreeType calls; secondary key validation catches hash
collisions in debug builds**

## Performance

- **Duration:** 12 min
- **Started:** 2026-02-02
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- FontMetricsEntry struct storing ascent/descent/linegap in Pango units
- MetricsCache with LRU eviction at 256 entries integrated into Context
- font_height() and font_metrics() check cache before Pango API calls
- CachedGlyph stores font_face/glyph_index/subpixel_bin for collision detection
- Debug builds panic on hash collision with detailed error message

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement MetricsCache with LRU eviction** - `30275cf` (feat)
2. **Task 2: Use metrics cache in font_height() and font_metrics()** - `8e8ee95` (feat)
3. **Task 3: Add secondary key validation to glyph cache** - `7283798` (feat)

## Files Created/Modified

- `context.v` - MetricsCache struct and integration with font_height()/font_metrics()
- `renderer.v` - Secondary key validation in get_or_load_glyph(), multi-page atlas fixes
- `glyph_atlas.v` - CachedGlyph extended with font_face/glyph_index/subpixel_bin fields
- `api.v` - Fixed get_atlas_image() and get_profile_metrics() for multi-page atlas

## Decisions Made

- Cache key uses face pointer XOR with size_units shifted left 32 bits - simple, fast
- Panic on collision rather than evict-and-reload - bugs should be loud in debug
- Secondary key validation only in debug builds - zero release overhead

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed renderer.v and api.v for multi-page atlas structure**

- **Found during:** Task 2 (metrics cache integration)
- **Issue:** GlyphAtlas refactored to multi-page in 09-01, but renderer.v/api.v still used old
  single-page fields (atlas.image, atlas.dirty, atlas.width, atlas.height)
- **Fix:** Updated commit() to iterate pages, draw_layout to use pages[cg.page].image,
  get_atlas_image() to return pages[0].image, get_profile_metrics() to sum across pages
- **Files modified:** renderer.v, api.v
- **Verification:** `v test .` passes
- **Committed in:** 8e8ee95 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (blocking issue from incomplete 09-01 integration)
**Impact on plan:** Essential fix - tests would not compile without it. No scope creep.

## Issues Encountered

None beyond the blocking issue documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- LATENCY-02 addressed: MetricsCache reduces repeated Pango/FreeType calls
- LATENCY-03 addressed: Collision detection active in debug builds
- Ready for LATENCY-04 (emoji scaling) if planned

---

*Phase: 09-latency-optimizations*
*Completed: 2026-02-02*
