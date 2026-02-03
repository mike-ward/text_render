# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-03)

**Core value:** Reliable text rendering without crashes or undefined behavior
**Current focus:** v1.4 CJK IME — full input method support without sokol modifications

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements for v1.4 CJK IME
Last activity: 2026-02-03 — Milestone v1.4 started

Progress: v1.0-v1.3 complete (17 phases, 28 plans)

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
- NSView category for IME (blocked by sokol)
- 150ms announcement debounce

### Pending Todos

None.

### Blockers/Concerns

**CJK IME** (documented 2026-02-03):
- Dead key composition works
- CJK (Japanese/Chinese/Korean) IME blocked by sokol architecture
- NSTextInputClient bridge implemented but cannot connect to MTKView
- Future work: sokol fork, overlay NSView, or method swizzling
- Non-blocking: accepted as tech debt for v1.3

### Known Issues

None active.

## Session Continuity

Last session: 2026-02-03
Stopped at: v1.4 milestone initialization
Resume file: None
Next: Define requirements → roadmap
