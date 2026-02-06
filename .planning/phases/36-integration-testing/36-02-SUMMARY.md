---
phase: 36-integration-testing
plan: 36-02
subsystem: api
tags: [testing, pango, refactor]
requires: [36-01]
provides: [integration-tests]
tech-stack:
  added: []
  patterns: [real-context-testing]
key-files:
  created: []
  modified: [_api_test.v]
decisions:
  - use-real-context-in-api-tests: Replaced unsafe { nil } mocks with real Context to ensure API validation works with real backend.
metrics:
  duration: 15m
  completed: 2026-02-05
---

# Phase 36 Plan 02: Refactor API tests to remove nil mocks Summary

## Substantive Changes

Refactored `_api_test.v` to use real Pango `Context` instances instead of `unsafe { nil }` mocks. This elevates these tests from fragile unit tests to robust integration tests that verify API behavior against the actual Pango/FreeType backend.

Key improvements:
- All tests in `_api_test.v` now initialize a real `Context` using `new_context(1.0)!`.
- Added `defer ctx.free()` to all tests to ensure proper resource cleanup and prevent memory leaks.
- Added `test_api_layout_text_success` to verify end-to-end layout through the `TextSystem` API.
- Verified that input validation (invalid UTF-8, empty strings, path traversal) still correctly propagates errors when using a real backend.

## Deviations from Plan

None - plan executed as written.

## Task Commits

- 2a6b5d4: test(36-02): replace nil Context mocks with real Context in API tests

## Self-Check: PASSED
