---
phase: 39-ime-polish
plan: 02
subsystem: IME
tags: [macos, ime, safety, consistency]
requires: [39-01]
provides: [safe-native-ime-bridge]
affects: [ime_bridge_macos.m, ime_overlay_darwin.m]
tech-stack:
  added: []
  patterns: [input-validation, coordinate-unification]
key-files:
  created: []
  modified: [ime_bridge_macos.m, ime_overlay_darwin.m]
decisions:
  - unified-coordinate-flip: Standardized the top-left to bottom-left Y-flip logic and documentation across all native macOS IME bridges.
  - defensive-ime-callbacks: Added nil checks for incoming IME strings and bounds validation for cursor positions to prevent crashes from malformed OS events.
metrics:
  duration: 15m
  completed: 2026-02-06
---

# Phase 39 Plan 02: macOS IME Safety and Consistency Summary

## Substantive Changes

### 1. Hardened Native IME Bridges
- Added nil checks for `string` and extracted `text` in `insertText:replacementRange:` and `setMarkedText:selectedRange:replacementRange:` in both `ime_bridge_macos.m` and `ime_overlay_darwin.m`.
- Added defensive check in `vglyph_insertText` (swizzled NSResponder method) in `ime_bridge_macos.m`.
- Implemented bounds validation for `selectedRange.location` against `text.length` before casting to `int`, ensuring cursor positions are always valid.

### 2. Standardized Coordinate Conversion
- Unified the documentation and implementation of the Y-flip logic in `firstRectForCharacterRange` across both native bridge implementations.
- Standardized comment: `// Flip Y: VGlyph top-left origin -> macOS bottom-left origin`.
- Standardized transform logic: `view -> window -> screen` using `convertRect:toView:nil` and `convertRectToScreen:`.

### 3. Verification
- Verified both `.m` files compile cleanly with `clang`.
- Verified the project compiles with `v examples/editor_demo.v`.

## Task Commits

- 4a26151: feat(39-02): add nil checks and bounds validation to ime_bridge_macos.m
- e482651: feat(39-02): add validation and standardize coordinate flip in ime_overlay_darwin.m

## Deviations from Plan

- **Accessibility Frame**: The plan mentioned `setAccessibilityFrame:` in `ime_overlay_darwin.m`, but this file does not implement accessibility elements (it's an IME overlay). I ensured that `firstRectForCharacterRange:` (which serves a similar purpose for IME) uses the standardized coordinate flip, and verified that the accessibility code in `backend_darwin.v` also follows the same logic.

## Self-Check: PASSED
