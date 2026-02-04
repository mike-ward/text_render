---
phase: 19
plan: 01
subsystem: ime-overlay
tags: [ime, objc, nstextinputclient, callbacks]
requires: [18-01]
provides: [ime-overlay-callbacks, nstextinputclient-core]
affects: [19-02, 19-03]
tech-stack:
  added: []
  patterns: [c-callbacks, per-overlay-state]
key-files:
  created: []
  modified:
    - ime_overlay_darwin.h
    - ime_overlay_darwin.m
    - ime_overlay_stub.c
    - c_bindings.v
decisions:
  - Per-overlay callbacks (not global) to support multiple text fields
  - cursor_pos in callback is byte offset within preedit (selectedRange.location)
metrics:
  duration: 2m
  completed: 2026-02-04
---

# Phase 19 Plan 01: NSTextInputClient Core Methods Summary

**One-liner:** NSTextInputClient setMarkedText/insertText/unmarkText with C callback bridge to V

## What Was Built

1. **VGlyphIMECallbacks struct** - C callback structure for marked/insert/unmark events with
   user_data pointer for per-overlay context

2. **setMarkedText implementation** - Extracts text from NSString/NSAttributedString, handles
   replacementRange edge cases per RESEARCH.md Pitfall #1, invokes on_marked_text callback

3. **insertText implementation** - Extracts committed text, invokes on_insert_text callback,
   clears composition via unmarkText

4. **unmarkText implementation** - Resets _markedRange to NSNotFound, invokes on_unmark_text
   callback

5. **Query methods** - markedRange/selectedRange return tracked state, hasMarkedText returns
   true when _markedRange.location != NSNotFound

6. **V bindings** - C.VGlyphIMECallbacks typedef, ime_overlay_register_callbacks wrapper

## Key Code

```objc
// setMarkedText handles replacementRange edge cases
if (replacementRange.location == NSNotFound) {
    if (_markedRange.location != NSNotFound) {
        replacementRange = _markedRange;
    } else {
        replacementRange = _selectedRange;
    }
}
_markedRange = NSMakeRange(replacementRange.location, text.length);
_selectedRange = NSMakeRange(replacementRange.location + selectedRange.location, 0);
if (_callbacks.on_marked_text) {
    _callbacks.on_marked_text([text UTF8String], (int)selectedRange.location, _callbacks.user_data);
}
```

## Changes Made

| File | Change |
|------|--------|
| ime_overlay_darwin.h | +VGlyphIMECallbacks struct, +vglyph_overlay_register_callbacks |
| ime_overlay_darwin.m | +_markedRange/_selectedRange ivars, impl setMarkedText/insertText/unmarkText |
| ime_overlay_stub.c | +vglyph_overlay_register_callbacks stub |
| c_bindings.v | +C.VGlyphIMECallbacks, +ime_overlay_register_callbacks wrapper |

## Verification Results

- clang -c -fobjc-arc ime_overlay_darwin.m: PASS
- v -check-syntax c_bindings.v: PASS
- All 9 NSTextInputClient methods implemented: PASS
- Callback invocations present: PASS

## Deviations from Plan

None - plan executed exactly as written.

## Decisions Made

1. **Per-overlay callbacks (not global):** Each overlay stores its own VGlyphIMECallbacks
   property. Supports apps with multiple text fields that need separate callback contexts.

2. **cursor_pos is selectedRange.location:** Passed directly to callback as byte offset within
   preedit string, matching CONTEXT.md expectation.

## Next Phase Readiness

- Phase 19-02 can implement firstRectForCharacterRange for candidate window positioning
- Phase 19-03 can implement attributedSubstringForProposedRange for document queries
- V code can now receive IME events via registered callbacks
