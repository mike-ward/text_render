# Codebase Concerns

**Analysis Date:** 2026-02-05

## Tech Debt

**Manual Memory Management:**
- Issue: Complex manual lifecycle management of Pango/GObject pointers using `defer`, `free`, and
  explicit unreferencing.
- Files: `layout.v`, `context.v`, `c_bindings.v`
- Impact: High risk of memory leaks or "double-free" crashes if logic paths are modified without
  deep understanding.
- Fix approach: Encapsulate C pointers in V structs with strictly defined `free()` methods and
  RAII-like ownership patterns.

## Known Bugs / Incomplete Features

**Incomplete Accessibility Integration:**
- Symptoms: TODOs indicate missing logic for attaching accessibility elements to windows and
  handling notifications.
- Files: `accessibility/backend_darwin.v`, `accessibility/manager.v`
- Trigger: Using accessibility features on macOS.
- Workaround: None. Feature is likely non-functional or partial.

**Platform Support Gaps:**
- Issue: IME (Input Method Editor) and Accessibility implementations appear to be macOS-only
  (`*_darwin.v`, `*.m`).
- Files: `ime_bridge_macos.m`, `accessibility/backend_darwin.v`
- Impact: No native IME or Accessibility support on Linux or Windows.
- Fix approach: Implement platform-specific backends for Linux (AT-SPI, etc.) and Windows (UI
  Automation).

## Security Considerations

**Unsafe Block Usage:**
- Risk: `unsafe` blocks allow direct memory manipulation and pointer dereferencing, bypassing V's
  safety checks.
- Files: `api.v`, `c_bindings.v`
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

## Test Coverage Gaps

**Integration Testing:**
- What's not tested: Real interactions with Pango/Cairo backend in unit tests. `_api_test.v` uses
  `unsafe { nil }` mocks.
- Files: `_api_test.v`
- Risk: Bugs in the C-binding layer might not be caught until runtime.
- Priority: High.

---

*Concerns audit: 2026-02-05*