# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-03)

**Core value:** Reliable text rendering without crashes or undefined behavior
**Current focus:** v1.4 CJK IME — Phase 18 Overlay Infrastructure

## Current Position

Phase: 18 of 21 (Overlay Infrastructure)
Plan: 1 of 2 complete
Status: In progress
Last activity: 2026-02-03 — Completed 18-01-PLAN.md

Progress: ████████████████████████████░ 29/30 plans (96.7%)

## Performance Metrics

Latest profiled build metrics (from v1.2 Phase 10):
- Glyph cache: 4096 entries (LRU eviction)
- Metrics cache: 256 entries (LRU eviction)
- Atlas: Multi-page (4 max), LRU page eviction
- Layout cache: TTL-based eviction
- Frame timing: instrumented via `-d profile`

## Accumulated Context

### Decisions

See PROJECT.md Key Decisions table for full history.

v1.3 key decisions archived:
- Byte-to-logattr mapping for UTF-8/emoji cursor
- Anchor-focus selection model
- Pure function mutation (MutationResult)
- 1s coalescing timeout for undo
- 150ms announcement debounce

v1.4 approach decision:
- Overlay NSView architecture (transparent sibling above MTKView)
- No sokol modifications (project constraint)

v1.4 Phase 18 decisions:
- Overlay sibling positioning: Sibling above MTKView (not child) to avoid Metal rendering interference
- ARC memory management: __bridge_retained for C ownership transfer

### Pending Todos

None.

### Blockers/Concerns

**CJK IME approach** (documented 2026-02-03):
- Overlay approach has CEF precedent but not tested with sokol specifically
- Korean jamo backspace behavior less documented than Japanese/Chinese
- Research confidence: MEDIUM-HIGH overall

### Known Issues

None active.

## Session Continuity

Last session: 2026-02-03
Stopped at: Completed 18-01-PLAN.md
Resume file: None
Next: Execute 18-02 (field focus integration)
