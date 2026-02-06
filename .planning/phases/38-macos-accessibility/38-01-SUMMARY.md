---
phase: 38-macos-accessibility
plan: 01
subsystem: accessibility
tags: [macos, accessibility, objective-c]
requires: []
provides: [core-tree-structure]
affects: [accessibility-inspector]
tech-stack:
  added: []
  patterns: [native-bridge, hierarchy-mapping]
key-files:
  created: []
  modified:
    - accessibility/backend_darwin.v
---

# Phase 38 Plan 01: Core Tree (Window, Elements, Hierarchy) Summary

Implemented the core structure for the macOS accessibility tree, enabling `vglyph` to expose its UI hierarchy to the system.

## Key Achievements

- **Window Retrieval:** Integrated `sapp.macos_get_window()` to obtain the native `NSWindow` handle.
- **Element Mapping:** Implemented `update_tree` to create/reuse `NSAccessibilityElement` instances for each V node.
- **Property Sync:**
  - `accessibilityLabel` set from node text.
  - `accessibilityFrame` calculated with correct coordinate space conversion (flipped Y).
- **Hierarchy Construction:**
  - Established parent/child relationships using `setAccessibilityParent:` and `setAccessibilityChildren:`.
  - Connected the root accessibility element to the main `NSWindow`.

## Implementation Details

- **Coordinate System:** Handled the conversion from V's top-left origin to Cocoa's bottom-left origin for `NSRect`.
- **Role Mapping:** Expanded `get_role_string` to cover all defined `AccessibilityRole` enum values.
- **Darwin-only:** Code is properly isolated in `backend_darwin.v` and compiles cleanly with `-os macos`.

## Verification

- **Compilation:** Verified `v -os macos -shared accessibility` compiles without errors.
- **Logic Check:** valid usages of `v_msgSend` wrappers and proper hierarchy building logic.

## Deviations from Plan

- **Combined Tasks:** Tasks 2 (Properties) and 3 (Hierarchy) were implemented together in `update_tree` as they are tightly coupled loop operations.
- **Role Mapping Update:** Proactively updated `get_role_string` to handle all roles, not just those strictly required by the plan.

## Self-Check: PASSED
