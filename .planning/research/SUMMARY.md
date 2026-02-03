# VGlyph v1.4 CJK IME Research Summary

**Project:** VGlyph v1.4 CJK IME
**Domain:** CJK input method integration without sokol modifications
**Researched:** 2026-02-03
**Confidence:** MEDIUM-HIGH

## Executive Summary

VGlyph v1.4 adds full CJK (Japanese, Chinese, Korean) input method support via an overlay NSView
architecture that bypasses sokol's MTKView limitation. The core problem: sokol creates an MTKView
that doesn't implement NSTextInputClient, and NSView categories don't transfer protocol conformance
to MTKView subclasses. The solution is a transparent overlay view that sits above the MTKView,
receives IME events as first responder during text editing, and forwards them to VGlyph's existing
CompositionState infrastructure.

VGlyph already has strong foundations from v1.3: CompositionState with clause support, preedit
rendering with underlines, dead key composition, and ime_register_callbacks() for event forwarding.
The missing piece is the native bridge that actually receives macOS IME events. The overlay approach
provides this bridge without modifying sokol, following patterns proven in CEF/Chromium for
off-screen rendering IME support.

Three distinct CJK composition models need support: Japanese (multi-stage romaji→hiragana→kanji with
clause segmentation), Chinese (phonetic pinyin/zhuyin with direct candidate selection), and Korean
(real-time jamo→syllable composition with no candidate window for basic input). All share: marked
text display, candidate window positioning via `firstRectForCharacterRange:`, and commit/cancel flow.
"Basic CJK IME" means the standard flow: type → see preedit with underline → candidates appear →
select → commit.

## Key Findings

### Recommended Approach

**Overlay NSView** — Create a transparent NSView subclass implementing NSTextInputClient, positioned
above sokol's MTKView as a sibling (not child). When a text field gains focus, make the overlay
first responder for keyboard events. The overlay forwards IME callbacks to existing V infrastructure,
then renders results in VGlyph (overlay remains visually transparent).

**Why this approach:**
- No sokol modification required (project constraint)
- Clean separation of concerns (IME handling vs rendering)
- Matches CEF's proven architecture
- Can be enabled/disabled per text field focus
- Doesn't interfere with Metal rendering pipeline

**Rejected alternatives:**
- Runtime method injection (class_addMethod) — fragile, depends on sokol internals
- ISA swizzling (object_setClass) — complex, same fragility issue
- NSTextInputContext remote client — still needs view for inputContext
- Sokol fork — violates project constraint

### Feature Scope

**Table stakes (v1.4):**
- Japanese: hiragana preedit, clause segmentation, Space for conversion, Enter to commit
- Chinese: pinyin preedit, candidate window positioning, number key selection
- Korean: jamo→syllable composition, backspace decomposition (간→가→ㄱ)
- All: marked text underline (thin=raw, thick=selected clause), candidate window positioning

**Already exists (v1.3 foundation):**
- CompositionState with phase tracking and clause support
- Preedit text rendering with underlines
- Dead key composition (accented characters)
- ime_register_callbacks() for event forwarding

**Defer to post-v1.4:**
- Reconversion (select committed text, re-convert)
- Vertical text candidate positioning
- Hanja conversion (Korean→Chinese characters)
- Custom keyboard layouts

### Architecture

**New components:**
1. `ime_overlay_macos.m` — VGlyphIMEOverlayView implementing NSTextInputClient
2. `ime_manager_darwin.v` — V bindings for overlay lifecycle (init, activate, deactivate)
3. `ime_manager_stub.v` — No-op stub for non-Darwin builds

**Integration points:**
- composition.v: Overlay calls existing CompositionState.set_marked_text(), .commit(), .cancel()
- ime_bridge_macos.h: Extend with overlay lifecycle C declarations
- editor_demo.v: Add focus event handling for overlay activation

**Data flow:**
```
User types key → Overlay is first responder → inputContext handleEvent
→ macOS IME processes → setMarkedText:/insertText: callback
→ V CompositionState updated → Layout rebuilt → Rendered with preedit
```

### Critical Pitfalls

**1. Overlay event routing collision**
- Overlay's hitTest: must return nil except during active IME composition
- Track composition state: overlay handles events only when hasMarkedText is true
- Test sequence: click (verify cursor), type (verify char), activate IME (verify composition)

**2. NSTextInputClient range parameter misinterpretation**
- replacementRange.location == NSNotFound means "use current marked range or selection"
- For non-NSNotFound replacementRange, interpret as absolute document position
- Apple docs are misleading — Mozilla devs documented "I believe the document is wrong"
- Log all NSTextInputClient calls with parameters during development

**3. Candidate window screen coordinate errors**
- Use proper conversion chain: view → window → screen
- Test on multi-monitor setups and Retina displays
- Account for backing scale factor on Retina

**4. Korean hangul backspace behavior**
- During active composition (hasMarkedText), forward backspace to IME
- Don't handle backspace directly when composition is active
- Let IME manage jamo decomposition via setMarkedText updates

## Implications for Roadmap

### Phase 18: Overlay Infrastructure

**Rationale:** Must have native bridge before IME events can flow
**Delivers:**
- VGlyphIMEOverlayView with NSTextInputClient skeleton
- ime_manager_darwin.v with init/activate/deactivate
- ime_manager_stub.v for non-Darwin
**Success criteria:**
- Overlay appears and can become first responder
- Japanese IME activates when overlay focused
**Addresses pitfalls:** Overlay event routing collision (#1)

### Phase 19: NSTextInputClient Implementation

**Rationale:** Connect overlay to existing callbacks, verify events reach V
**Delivers:**
- Full NSTextInputClient protocol implementation
- setMarkedText/insertText forwarding to CompositionState
- firstRectForCharacterRange with coordinate transforms
**Success criteria:**
- Japanese IME shows composition text in VGlyph
- Candidate window appears near cursor (not at screen corner)
**Addresses pitfalls:** Range parameters (#2), coordinate errors (#3)

### Phase 20: Keyboard Integration

**Rationale:** Handle backspace, dead keys, focus transitions correctly
**Delivers:**
- Korean backspace decomposition (forward to IME when composing)
- Dead key integration (disable V-side when overlay active)
- Focus loss auto-commit
- Undo/redo blocked during composition
**Success criteria:**
- Korean 간 + backspace → 가 (not deleted)
- Dead keys work after using CJK IME
- No crash on Cmd+Z during composition
**Addresses pitfalls:** Korean backspace (#4), dead key conflict (#5), undo during composition (#6)

### Phase 21: CJK Testing & Polish

**Rationale:** Validate all three CJK input methods work correctly
**Delivers:**
- Japanese: hiragana → kanji with clause selection
- Chinese: pinyin with candidate selection
- Korean: hangul jamo composition
- Multi-monitor candidate positioning
- Retina display support
**Success criteria:**
- All three IMEs complete basic flow: type → candidates → commit
- Manual testing with native speakers

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Overlay approach | MEDIUM | CEF precedent exists, not tested with sokol specifically |
| NSTextInputClient protocol | HIGH | Apple docs, Mozilla/winit implementations verified |
| Japanese/Chinese flow | HIGH | Well-documented, multiple sources agree |
| Korean jamo composition | MEDIUM | Less documentation, behavior inferred from bug reports |
| Coordinate transforms | HIGH | Multiple implementations documented, known pitfalls |
| Range parameters | HIGH | Mozilla Bug 875674 explicitly documents Apple doc errors |

**Overall confidence:** MEDIUM-HIGH

The overlay approach is well-supported by CEF precedent. NSTextInputClient protocol is
well-documented, though with known Apple doc inaccuracies that the research has addressed.
Main uncertainty: overlay integration with sokol's event loop needs implementation validation.

## Sources

**HIGH confidence (official docs, verified bugs):**
- [NSTextInputClient Protocol](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [Mozilla Bug 875674](https://bugzilla.mozilla.org/show_bug.cgi?id=875674) — NSTextInputClient impl
- [winit Issue #3617](https://github.com/rust-windowing/winit/issues/3617) — Range parameters
- [Apple FB13789916](https://gist.github.com/krzyzanowskim/340c5810fc427e346b7c4b06d46b1e10) — Chinese
  keyboard selectedRange bug
- [Microsoft: Glaring Hole in NSTextInputClient](https://learn.microsoft.com/en-us/archive/blogs/rick_schaut/the-glaring-hole-in-the-nstextinputclient-protocol)

**MEDIUM confidence (patterns, multiple sources):**
- [CEF IME for Off-Screen Rendering](https://www.magpcss.org/ceforum/viewtopic.php?f=8&t=10470)
- [sokol Issue #595](https://github.com/floooh/sokol/issues/595) — IME support request
- [GLFW NSTextInputClient](https://fsunuc.physics.fsu.edu/git/gwm17/glfw/commit/3107c9548d7911d9424ab589fd2ab8ca8043a84a)
- [jessegrosjean NSTextInputClient](https://github.com/jessegrosjean/NSTextInputClient) — Reference
- [FSNotes Issue #708](https://github.com/glushchenko/fsnotes/issues/708) — Korean delete bug
- [Zed Issue #46055](https://github.com/zed-industries/zed/issues/46055) — Candidate position

---
*Research completed: 2026-02-03*
*Ready for roadmap: yes*
