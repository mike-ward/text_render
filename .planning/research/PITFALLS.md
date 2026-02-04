# Pitfalls Research: CJK IME

**Domain:** CJK Input Method Editor integration with sokol workaround
**Researched:** 2026-02-03
**Context:** v1.4+ milestone — adding CJK IME support to VGlyph with sokol MTKView limitations

## Summary

Key risks for this milestone center on three interrelated challenges:

1. **First responder architecture** — sokol's MTKView doesn't inherit NSView category methods, requiring
   overlay view or sokol fork workarounds
2. **NSTextInputClient protocol edge cases** — range parameters documented incorrectly, IME-specific
   behaviors vary by language (Japanese reconversion vs Korean jamo vs Chinese candidate selection)
3. **Coordinate system transformations** — view-local coords must convert to screen coords for candidate
   window, complicated by multi-monitor and Retina setups

The v1.3 research identified "IME marked text range confusion" as critical. This remains the highest
risk, with additional CJK-specific edge cases now documented.

---

## Critical Pitfalls

Mistakes causing rewrites or broken CJK input.

### 1. Overlay View Event Routing Collision

**What happens:**
Creating a transparent NSView overlay for first responder causes event routing conflicts. Mouse clicks
intended for the underlying Metal view get intercepted by the overlay, or keyboard events meant for IME
composition bypass the overlay and go to sokol's view.

**Warning signs:**
- Clicks don't register on editor content
- Cursor doesn't update on click
- Keyboard input works but IME never activates
- IME activates but composition appears in wrong position

**Why it happens:**
- Overlay's `hitTest:` returns self for all points (blocks Metal view)
- Overlay's `acceptsFirstResponder` conflicts with MTKView's key handling
- Event responder chain unclear: overlay → MTKView → window → app
- sokol captures key events in `keyDown:` before `interpretKeyEvents:` can route to IME

**Prevention:**
- Overlay `hitTest:` must return nil except during active IME composition
- Forward non-IME keyboard events to sokol via `interpretKeyEvents:` → `doCommandBySelector:`
- Track composition state: overlay handles events only when `hasMarkedText` is true
- Test sequence: click (verify cursor), type (verify char), activate IME (verify composition)

**Relevant phase:** Foundation (overlay architecture design before any NSTextInputClient impl)

**Confidence:** MEDIUM (general pattern, specific behavior depends on overlay implementation)

**Sources:**
- [Apple Developer Forums: Input with Metal-CPP](https://developer.apple.com/forums/thread/713233)
- v1.3 verification: NSView category doesn't affect MTKView (15-VERIFICATION.md)

---

### 2. NSTextInputClient Range Parameter Misinterpretation

**What happens:**
`setMarkedText:selectedRange:replacementRange:` receives parameters in different coordinate systems
depending on IME and context. Developer implements assuming one interpretation, breaks for certain IMEs
or reconversion scenarios.

**Warning signs:**
- Japanese IME works, Chinese IME inserts at wrong position
- Reconversion selects wrong text range
- Traditional Chinese Zhuyin IME nested composition fails
- Korean composition appears duplicated

**Why it happens:**
- Apple docs say `replacementRange` is "computed from beginning of marked text"
- Mozilla devs documented: "I ignore the document of NSTextInputClient. I believe the document is wrong"
- Japanese IME uses `replacementRange` for reconversion (absolute document position)
- `replacementRange.location == NSNotFound` means "use current marked/selection"
- Chinese keyboard bug (FB13789916): `selectedRange` changes unexpectedly mid-composition

**Prevention:**
- Treat `replacementRange.location == NSNotFound` as signal to use marked range or selection
- For non-NSNotFound `replacementRange`, interpret as absolute document position
- Log all NSTextInputClient calls with parameters during development
- Test with: Japanese IME reconversion, Traditional Chinese Zhuyin, Korean 2-set

**Detection:**
- Test: Japanese IME, type "kanji", convert, select committed text, reconvert (Ctrl+Shift+R on Kotoeri)
- Test: Chinese IME, type pinyin, observe `selectedRange` values in setMarkedText calls
- Test: Zhuyin IME, nested composition (in-ICB cursor positioning)

**Relevant phase:** NSTextInputClient implementation

**Confidence:** HIGH (verified via [Mozilla Bug 875674](https://bugzilla.mozilla.org/show_bug.cgi?id=875674),
[winit Issue #3617](https://github.com/rust-windowing/winit/issues/3617),
[FB13789916](https://gist.github.com/krzyzanowskim/340c5810fc427e346b7c4b06d46b1e10))

---

### 3. Candidate Window Screen Coordinate Errors

**What happens:**
`firstRectForCharacterRange:actualRange:` returns rect in wrong coordinate space. IME candidate window
appears at screen corner, wrong monitor, or offset from cursor.

**Warning signs:**
- Candidate window at bottom-left of screen
- Candidate window on wrong monitor in multi-display setup
- Candidate window offset by ~2x on Retina displays
- Candidate window position correct on primary, wrong on secondary monitor

**Why it happens:**
- macOS screen coords: origin at bottom-left of primary display
- View coords: origin at top-left (flipped) or bottom-left depending on view
- Window coords: origin at window's bottom-left
- Multi-monitor: coordinates merge across displays, can exceed single-display bounds
- Retina: backing scale factor doubles logical coordinates
- Common error: return view-local or window-local coords instead of screen coords

**Prevention:**
- Use conversion chain: view → window → screen
  ```objc
  NSRect localRect = [self rectForCharacterRange:range];
  NSRect windowRect = [self convertRect:localRect toView:nil];
  NSRect screenRect = [[self window] convertRectToScreen:windowRect];
  return screenRect;
  ```
- Account for backing scale factor on Retina: use `convertRectToBacking:` if needed
- Test on multi-monitor with different arrangements (primary left/right/above)
- Test on Retina display at 1x and 2x scaling

**Detection:**
- Test: Japanese IME on secondary monitor, verify candidate near cursor
- Test: Chinese IME at screen edge, verify candidate doesn't go off-screen
- Test: Retina display, verify candidate position matches cursor

**Relevant phase:** NSTextInputClient implementation

**Confidence:** HIGH (verified via [Zed Issue #46055](https://github.com/zed-industries/zed/issues/46055),
[Mozilla Bug #296687](https://bugzilla.mozilla.org/show_bug.cgi?id=296687),
[Apple Coordinate System docs](https://developer.apple.com/library/archive/documentation/General/Devpedia-CocoaApp-MOSX/CoordinateSystem.html))

---

### 4. Korean Hangul Backspace Deleting Entire Syllable

**What happens:**
Backspace during Korean composition deletes entire syllable (e.g., "간") instead of just the last
jamo ("ㄴ"), breaking standard Korean typing expectations.

**Warning signs:**
- Korean users complain "can't correct typing mistakes"
- Backspace removes entire composed character instead of last component
- Korean input feels "all-or-nothing"

**Why it happens:**
- Korean syllables composed from multiple jamo: ㄱ + ㅏ + ㄴ = 간
- During composition (before commit), backspace should remove only last jamo: 간 → 가 → ㄱ
- Application handles backspace as "delete character" instead of "IME composition backspace"
- Backspace event bypasses IME and goes directly to text mutation

**Prevention:**
- During active composition (`hasMarkedText`), forward backspace to IME via `interpretKeyEvents:`
- Do NOT handle backspace directly when composition is active
- Let IME manage composition text modification
- Only handle backspace directly when `markedRange.location == NSNotFound`

**Detection:**
- Test: Korean IME, type 간 (ㄱ + ㅏ + ㄴ), press backspace, should become 가 not empty
- Test: Verify backspace during composition doesn't trigger `insertText:` callback
- Test: Verify backspace after commit works normally (deletes whole character)

**Relevant phase:** Keyboard event routing

**Confidence:** HIGH (verified via [FSNotes Issue #708](https://github.com/glushchenko/fsnotes/issues/708),
[Spacemacs Issue #13303](https://github.com/syl20bnr/spacemacs/issues/13303),
[Oracle Korean Input docs](https://docs.oracle.com/cd/E19253-01/817-2522/userkorinputmethod-proc-38/index.html))

---

## Medium-Risk Pitfalls

Mistakes causing delays or degraded functionality.

### 5. Dead Key Composition Conflict with CJK IME

**What happens:**
v1.3 dead key handling in V char events conflicts with macOS IME when both are active. User switches
from Japanese IME to US keyboard, types dead key, composition state corrupted.

**Warning signs:**
- Dead key works in US, fails after using IME
- Accents double: ` + e produces `è è` instead of `è`
- Dead key becomes "sticky" after IME use
- modifier keys stop working after dead key + IME interaction

**Why it happens:**
- v1.3 dead keys handled in V char event (bypass native IME)
- macOS may still activate IME preedits for dead keys in certain keyboard layouts
- Custom keyboard layouts trigger IME composing mode for diacritics
- Two competing composition states: V-side DeadKeyState + macOS IME markedText

**Prevention:**
- Disable V-side dead key handling when native IME overlay is active
- Let macOS handle all composition when overlay is first responder
- Clear V-side DeadKeyState when overlay becomes first responder
- OR: use macOS dead key handling exclusively (remove V-side implementation)

**Detection:**
- Test: Switch US → Japanese → US, type ` + e, verify single è
- Test: Custom keyboard layout with dead keys, verify no modifier issues
- Test: Rapid IME switching during dead key pending state

**Relevant phase:** Integration with existing dead key support

**Confidence:** MEDIUM (verified via [winit Issue #2651](https://github.com/rust-windowing/winit/issues/2651),
[neovide PR #1083](https://github.com/neovide/neovide/pull/1083))

---

### 6. Undo/Redo During IME Composition

**What happens:**
User presses Cmd+Z during active IME composition. Undo system tries to undo while markedText exists,
corrupting composition state or document text.

**Warning signs:**
- Undo during composition causes crash
- Undo removes composition AND previous committed text
- Redo fails to restore composition state
- Text corruption after undo during composition

**Why it happens:**
- IME composition text is "provisional" — not in document yet
- Undo stack contains committed operations only
- Cmd+Z during composition: should it cancel composition or undo last commit?
- No clear boundary between composition state and document state

**Prevention:**
- Block undo/redo when `hasMarkedText` returns true
- Treat composition as atomic: either commit all or cancel all
- Cancel composition before applying undo (insert empty marked text)
- Don't record partial composition in undo stack

**Detection:**
- Test: Japanese IME, type "kanji" (not converted), press Cmd+Z
- Test: Chinese IME mid-composition, Cmd+Z, verify clean cancellation
- Test: Undo after commit, verify composition not affected

**Relevant phase:** Undo/redo integration

**Confidence:** MEDIUM (verified via [EmEditor v18.3 bug](https://www.emeditor.com/forums/topic/find-ime-undo/),
[Slate Issue #4127](https://github.com/ianstormtaylor/slate/issues/4127))

---

### 7. attributedSubstringForProposedRange Out-of-Bounds Crash

**What happens:**
macOS calls `attributedSubstringForProposedRange:actualRange:` with range outside document bounds.
Implementation doesn't handle this, crashes or returns invalid string.

**Warning signs:**
- Crash after hiding/showing application during composition
- Crash with macOS Sequoia + Apple AI enabled
- NSInvalidArgumentException: Range out of bounds
- IME stops working after app loses and regains focus

**Why it happens:**
- macOS caches text ranges, may request stale range after app state change
- App hide/show clears composition state, resets document — old range now invalid
- Apple AI features in Sequoia request ranges more aggressively
- Apple docs state: "implementation should be prepared for aRange to be out of bounds"

**Prevention:**
- Always clamp `proposedRange` to `[0, documentLength]`
- Return nil (not crash) for out-of-bounds range
- Set `actualRange` to clamped range when adjusting
- Log out-of-bounds requests during development for diagnosis

**Detection:**
- Test: Start composition, hide app (Cmd+H), show app, type — should not crash
- Test: macOS Sequoia with AI features, composition + background
- Test: Very long document, request range beyond end

**Relevant phase:** NSTextInputClient implementation

**Confidence:** HIGH (verified via [Flutter Issue #153157](https://github.com/flutter/flutter/issues/153157),
[Mozilla Bug #1692379](https://bugzilla.mozilla.org/show_bug.cgi?id=1692379),
[Apple docs](https://developer.apple.com/documentation/appkit/nstextinputclient/1438238-attributedsubstring))

---

### 8. CJK Full-Width/Half-Width Character Width Confusion

**What happens:**
CJK characters expected to occupy 2 cell widths render as 1 cell, or half-width characters render
as 2 cells. Cursor position calculation wrong, text layout misaligned.

**Warning signs:**
- Cursor appears offset from actual position
- Selection highlight doesn't cover full character
- Text wrapping occurs at wrong position
- Mixed CJK + Latin text alignment broken

**Why it happens:**
- CJK full-width characters: 2 cell widths in monospace context
- CJK half-width variants (ｈａｌｆ): 1 cell width
- Unicode East_Asian_Width property: Wide/Fullwidth/Narrow/Half-width/Ambiguous
- Pango may return glyph width that doesn't match terminal expectations
- Font metrics don't always match logical character width

**Prevention:**
- For graphical rendering (not terminal): use Pango glyph metrics directly
- Don't assume character_count * cell_width for layout
- Use `pango_layout_get_pixel_extents()` for actual rendered width
- For cursor positioning, use byte-based Pango APIs (already established in v1.3)

**Detection:**
- Test: Japanese text with mixed hiragana and kanji, verify cursor positions
- Test: Chinese text, select range, verify highlight covers glyphs exactly
- Test: Korean half-width ㅎㅏㄴ vs full-width 한

**Relevant phase:** Composition text rendering

**Confidence:** MEDIUM (verified via [JetBrains Mono Issue #20](https://github.com/JetBrains/JetBrainsMono/issues/20),
[kitty Issue #6560](https://github.com/kovidgoyal/kitty/issues/6560))

---

## Low-Risk Pitfalls

Mistakes causing annoyance but recoverable.

### 9. Composition Underline Style Inconsistency

**What happens:**
macOS IME expects specific underline styles for composition: thick for selected clause, thin for
unselected. Application uses single style, confuses user about which clause is active.

**Why it happens:**
- Japanese IME multi-clause composition: user selects which clause to convert
- Single underline style doesn't indicate active clause
- v1.3 implemented single thick underline (sufficient for dead keys, insufficient for CJK)

**Prevention:**
- Parse attributed string from `setMarkedText:` for underline attributes
- NSUnderlineStyleSingle = unselected clause
- NSUnderlineStyleThick = selected clause (for conversion)
- Render different underline weights based on attributes

**Detection:**
- Test: Japanese IME, type long phrase, observe multiple clauses
- Test: Navigate between clauses with arrow keys, verify underline changes

**Relevant phase:** Composition rendering

**Confidence:** HIGH (documented in v1.3 15-CONTEXT.md)

---

### 10. IME Candidate Window Z-Order Issues

**What happens:**
IME candidate window appears behind application window or behind overlay view.

**Why it happens:**
- Candidate window is system-owned, positioned by macOS
- Application window level may conflict
- Overlay view z-order may interfere

**Prevention:**
- Implement `windowLevel` method in NSTextInputClient if using non-standard window level
- Don't use window levels higher than NSFloatingWindowLevel without returning correct level
- Test with full-screen mode (different window level semantics)

**Detection:**
- Test: Japanese IME, verify candidate window visible
- Test: Full-screen mode, composition — candidate should float

**Relevant phase:** Overlay view setup

**Confidence:** MEDIUM ([Apple NSTextInputClient docs](https://developer.apple.com/documentation/appkit/nstextinputclient))

---

## Phase-Specific Warnings

| Phase | Likely Pitfall | Mitigation |
|-------|---------------|------------|
| Overlay architecture | Event routing collision (1) | Test click→type→IME sequence early |
| NSTextInputClient impl | Range misinterpretation (2) | Log all parameters, test with 3 IMEs |
| NSTextInputClient impl | Coordinate errors (3) | Test multi-monitor before feature complete |
| NSTextInputClient impl | Out-of-bounds crash (7) | Clamp all ranges to document bounds |
| Keyboard routing | Hangul backspace (4) | Forward to IME when hasMarkedText |
| Dead key integration | Composition conflict (5) | Disable V-side when overlay active |
| Undo/redo integration | Composition undo (6) | Block undo when hasMarkedText |
| Composition rendering | Width confusion (8) | Use Pango pixel metrics, not assumptions |
| Composition rendering | Underline style (9) | Parse attributed string underline attrs |

---

## Testing Strategy

**IME test matrix:**

| IME | Key Scenarios |
|-----|---------------|
| Japanese (Kotoeri) | Basic composition, conversion, reconversion, multi-clause |
| Chinese Pinyin | Candidate selection, tone marks, phrase completion |
| Traditional Chinese Zhuyin | Nested composition (in-ICB cursor) |
| Korean 2-set | Jamo composition, backspace decomposition |

**Edge case tests:**

```
Basic composition:     Japanese "nihongo" → 日本語
Multi-clause:          Japanese long phrase → navigate/convert clauses
Reconversion:          Japanese: select 日本語, reconvert
Backspace:             Korean 간 + backspace → 가
Candidate position:    Multi-monitor, secondary display
Coordinate scaling:    Retina display at 2x
Focus transition:      Compose → hide → show → continue
Undo during comp:      Compose → Cmd+Z → verify cancellation
Dead key after IME:    Japanese → US → ` + e → single è
```

**Critical manual verification:**

1. Japanese IME: Type "nihongo", convert, verify candidate near cursor
2. Korean IME: Type "hangul", backspace removes last jamo not whole syllable
3. Multi-monitor: Composition on secondary, candidate on same display
4. App hide/show: Composition survives or cleanly cancels (no crash)

---

## Open Questions

- Overlay vs sokol fork: Which approach for first responder?
- Dead key handling: Keep V-side or defer entirely to macOS?
- Composition styling: How to render clause boundaries in VGlyph?

---

## Sources

**HIGH confidence (official docs, verified bugs):**
- [NSTextInputClient Protocol](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [Apple Coordinate System](https://developer.apple.com/library/archive/documentation/General/Devpedia-CocoaApp-MOSX/CoordinateSystem.html)
- [Mozilla Bug 875674: NSTextInputClient implementation](https://bugzilla.mozilla.org/show_bug.cgi?id=875674)
- [winit Issue #3617: Range parameters ignored](https://github.com/rust-windowing/winit/issues/3617)
- [Flutter Issue #153157: attributedSubstringForProposedRange crash](https://github.com/flutter/flutter/issues/153157)
- [Apple FB13789916: Chinese keyboard bogus selectedRange](https://gist.github.com/krzyzanowskim/340c5810fc427e346b7c4b06d46b1e10)
- [Microsoft: Glaring Hole in NSTextInputClient](https://learn.microsoft.com/en-us/archive/blogs/rick_schaut/the-glaring-hole-in-the-nstextinputclient-protocol)

**MEDIUM confidence (community patterns, multiple sources):**
- [Zed Issue #46055: Candidate window position](https://github.com/zed-industries/zed/issues/46055)
- [Mozilla Bug #296687: IME position too below](https://bugzilla.mozilla.org/show_bug.cgi?id=296687)
- [FSNotes Issue #708: Korean delete bug](https://github.com/glushchenko/fsnotes/issues/708)
- [Spacemacs Issue #13303: Hangul backspace](https://github.com/syl20bnr/spacemacs/issues/13303)
- [winit Issue #2651: Dead keys and IME conflict](https://github.com/rust-windowing/winit/issues/2651)
- [sokol Issue #595: IME support request](https://github.com/floooh/sokol/issues/595)
- [sokol Issue #727: MTKView replacement](https://github.com/floooh/sokol/issues/727)

**LOW confidence (single source, needs validation):**
- [EmEditor IME/undo bug](https://www.emeditor.com/forums/topic/find-ime-undo/)
- [Slate composition issues](https://github.com/ianstormtaylor/slate/issues/4127)
