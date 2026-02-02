# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-02)

**Core value:** Reliable text rendering without crashes or undefined behavior
**Current focus:** v1.3 Text Editing

## Current Position

Phase: Phase 11 - Cursor Foundation
Plan: 1 of 2 complete
Status: In progress
Last activity: 2026-02-02 - Completed 11-01-PLAN.md (Cursor Position API)

Progress: [█░░░░░░░░░] 1/7 phases in progress (Plan 2 remaining)

## Performance Metrics

Latest profiled build metrics (from v1.2 Phase 10 completion):
- Glyph cache: 4096 entries (LRU eviction)
- Metrics cache: 256 entries (LRU eviction)
- Atlas: Multi-page (4 max), LRU page eviction
- Layout cache: TTL-based eviction
- Frame timing: instrumented via `-d profile`

## Accumulated Context

### Decisions

See PROJECT.md Key Decisions table for full history.

v1.3 decisions:
- v-gui owns blink timer, VGlyph provides cursor geometry
- macOS primary for IME, other platforms later
- Targeting all three use cases: code editor, rich text, simple inputs
- Phase order: Cursor -> Selection -> Mutation -> Undo/Redo -> IME -> API & Demo -> Accessibility
- 7 phases (11-17) for v1.3 milestone
- v-gui widget changes tracked in separate v-gui milestone

Phase 11-01 decisions:
- Use Pango C struct members directly (not packed u32) for LogAttr access
- Cursor position uses cached char_rects with line fallback for edge cases
- LogAttr array has len = text.len + 1 (position before each char + end)

### Pending Todos

None.

### Blockers/Concerns

None. Cursor position API complete, ready for navigation APIs.

## Session Continuity

Last session: 2026-02-02
Stopped at: Completed 11-01-PLAN.md (Cursor Position API)
Resume file: .planning/phases/11-cursor-foundation/11-02-PLAN.md
