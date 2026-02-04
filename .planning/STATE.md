# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-04)

**Core value:** Reliable text rendering without crashes or undefined behavior
**Current focus:** v1.4 CJK IME complete — ready for next milestone

## Current Position

Phase: 21 of 21 (all v1.4 phases complete)
Plan: All complete
Status: v1.4 CJK IME milestone SHIPPED
Last activity: 2026-02-04 — Milestone complete

Progress: ██████████████████████████████ 36/36 plans

## Milestone Summary

**v1.4 CJK IME — SHIPPED 2026-02-04**

| IME | Status |
|-----|--------|
| Japanese | PASS |
| Chinese | PASS |
| Korean | Partial (first-keypress issue*) |

*macOS-level bug: Qt QTBUG-136128, Apple FB17460926, Alacritty #6942

## Performance Metrics

Latest profiled build metrics:
- Glyph cache: 4096 entries (LRU eviction)
- Metrics cache: 256 entries (LRU eviction)
- Atlas: Multi-page (4 max), LRU page eviction
- Layout cache: TTL-based eviction
- Frame timing: instrumented via `-d profile`

## Accumulated Context

### Decisions

See PROJECT.md Key Decisions table for full history.

Recent decisions:
- Overlay sibling positioning (avoid Metal conflicts)
- Per-overlay callbacks (multi-field support)
- Block undo/redo during composition
- Korean first-keypress workarounds (best-effort, macOS bug)

### Pending Todos

None.

### Known Issues

**Korean IME first-keypress** — macOS-level bug, reported upstream. User workaround: type first
character twice, or refocus field.

**Overlay API limitation** — editor_demo uses global callback API because gg doesn't expose MTKView
handle. Multi-field apps need native handle access.

## Session Continuity

Last session: 2026-02-04
Stopped at: v1.4 milestone complete
Resume file: None
Resume command: `/gsd:new-milestone` to start v1.5
