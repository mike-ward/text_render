# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-04)

**Core value:** Reliable text rendering without crashes or undefined behavior
**Current focus:** v1.6 Performance Optimization - Phase 28 Profiling Validation

## Current Position

Phase: 27 of 29 (Async Texture Updates) — COMPLETE
Plan: All complete
Status: Phase 27 verified (6/6 must-haves), ready for Phase 28
Last activity: 2026-02-05 — Phase 27 verified and complete

Progress: ███████████████████████████████░░░ 27/29 phases (93%)

## Performance Metrics

**Velocity:**
- Total phases completed: 27
- Phases per milestone avg: 4.2
- Total milestones shipped: 5

**By Milestone:**

| Milestone | Phases | Status |
|-----------|--------|--------|
| v1.0 Memory Safety | 3 | Complete |
| v1.1 Fragile Hardening | 4 | Complete |
| v1.2 Performance v1 | 3 | Complete |
| v1.3 Text Editing | 7 | Complete |
| v1.4 CJK IME | 4 | Complete (partial Korean) |
| v1.5 Quality Audit | 4 | Complete |
| v1.6 Performance v2 | 4 | In progress |

**Recent Activity:**
- Phase 27 Async Texture Updates completed 2026-02-05 (verified 6/6)
- Phase 26 Shelf Packing completed 2026-02-05 (verified 17/17)

## Accumulated Context

### Decisions

See PROJECT.md Key Decisions table for full history (36 decisions documented).

Recent decisions affecting current work:
- Phase 27-01: Upfront staging buffer allocation (at page creation, not lazy)
- Phase 27-01: Preserve staging_back during grow_page (in-progress rasterization)
- Phase 27-01: Zero both buffers in reset_page (prevents stale data)
- Phase 27-01: Profile timing wraps entire commit() (measures CPU-side upload work)
- Phase 26: Debug struct location (ShelfDebugInfo in api.v, keeps glyph_atlas internal)
- Phase 26: Visualization colors (Gray outline, green fill, bright green cursor line)

### Pending Todos

None.

### Known Issues

**Korean IME first-keypress** - macOS-level bug, reported upstream (Qt QTBUG-136128, Apple
FB17460926, Alacritty #6942). User workaround: type first char twice or refocus field.

**Overlay API limitation** - editor_demo uses global callback API because gg doesn't expose
MTKView handle. Multi-field apps need native handle access.

## Session Continuity

Last session: 2026-02-05
Stopped at: Phase 27 verified and complete
Resume file: .planning/ROADMAP.md
Resume command: `/gsd:discuss-phase 28`
