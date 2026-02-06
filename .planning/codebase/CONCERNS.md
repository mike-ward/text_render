# Codebase Concerns

**Analysis Date:** 2026-02-05

## Tech Debt

*None currently identified as high priority.*

## Known Bugs / Incomplete Features

**Platform Support Gaps:**
- Issue: Native Accessibility implementations appear to be macOS-only (`*_darwin.v`, `*.m`).
- Files: `accessibility/backend_darwin.v`, `accessibility/manager.v`
- Status: macOS implementation is fully functional. Other platforms use no-op stubs (`backend_stub.v`).
- Impact: No native Accessibility support on Linux or Windows yet.
- Fix approach: Implement platform-specific backends for Linux (AT-SPI, etc.) and Windows (UI
  Automation).

## Security Considerations

**Unsafe Block Usage:**
- Risk: `unsafe` blocks allow direct memory manipulation and pointer dereferencing, bypassing V's
  safety checks.
- Files: `api.v`, `c_bindings.v`, `pango_wrappers.v`
- Current mitigation: Defensive checks `if ptr == unsafe { nil }`.
- Note: The use of `unsafe { nil }` for pointer initialization and null-checks is a permitted and
  established pattern in this project.
- Recommendations: Minimize `unsafe` scope. Audit all C interop boundaries.

## Performance Bottlenecks

**Text Layout caching:**
- Problem: `get_or_create_layout` relies on cache keys. Complex text configurations might cause
  cache misses or thrashing.
- Files: `api.v`, `layout.v`
- Cause: Pango layout generation is expensive.
- Improvement path: implement more granular caching or string interning for cache keys. Add cache
  hit/miss telemetry.

## Fragile Areas

**C Library Dependencies:**
- Files: `c_bindings.v`, `v.mod`
- Why fragile: Heavy reliance on external C libraries (Pango, Cairo, Freetype). Build environment
  setup is complex.
- Safe modification: Changes to bindings must match the specific version of the C library headers.
- Test coverage: Integration tests run in CI, but local setup can be brittle.

## Resolved Concerns

**macOS Accessibility Tree (Resolved 2026-02-06):**
- Issue: Missing logic for attaching accessibility elements to windows and handling notifications.
- Resolution: Implemented `DarwinAccessibilityBackend` with dynamic Objective-C binding, enabling
  full integration with macOS VoiceOver. Added `AccessibilityManager` to coordinate tree updates.

**Integration Testing (Resolved 2026-02-05):**
- Issue: Unit tests relied on `unsafe { nil }` mocks instead of real Pango/Cairo backend.
- Resolution: Implemented `_integration_test.v` using real `Context` and refactored `_api_test.v`
  to use real backend interactions.

---

*Concerns audit: 2026-02-05*