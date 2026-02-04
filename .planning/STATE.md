# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-03)

**Core value:** Reliable text rendering without crashes or undefined behavior
**Current focus:** v1.4 CJK IME — Phase 19 NSTextInputClient Protocol

## Current Position

Phase: 19 of 21 (NSTextInputClient Protocol)
Plan: 1 of 3 complete
Status: In progress
Last activity: 2026-02-04 — Completed 19-01-PLAN.md

Progress: ████████████████████████████░░ 30/32+ plans

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

v1.4 Phase 19 decisions:
- Per-overlay callbacks (not global) to support multiple text fields
- cursor_pos in callback is selectedRange.location (byte offset within preedit)

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

Last session: 2026-02-04
Stopped at: Completed 19-01-PLAN.md
Resume file: None
Next: Execute 19-02-PLAN.md or 19-03-PLAN.md
