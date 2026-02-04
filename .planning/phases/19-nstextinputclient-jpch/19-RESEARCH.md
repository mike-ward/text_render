# Phase 19: NSTextInputClient Protocol + Japanese/Chinese - Research

**Researched:** 2026-02-03
**Domain:** macOS NSTextInputClient protocol for CJK IME
**Confidence:** HIGH

## Summary

NSTextInputClient protocol is macOS's interface for Input Method Editor integration. Text views
implement ~10 required methods to communicate with system IME. Core pattern: IME sends marked
text (composition preview), user converts/selects candidates, IME sends final insertText.
Japanese/Chinese input follows same protocol with language-specific candidate window behaviors.

**Primary recommendation:** Implement required NSTextInputClient methods in overlay view created
by Phase 18, wire to CompositionState for preedit display, test early with Japanese IME
(simplest case) before Chinese (more complex candidate selection).

**Key finding:** Apple's documentation for `setMarkedText:selectedRange:replacementRange:`
contains errors — Mozilla/Flutter/winit all ignore official docs, use empirical behavior
instead. Range parameter interpretation varies by IME type.

## Standard Stack

### Core Framework
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AppKit NSTextInputClient | macOS 10.5+ | IME protocol | Only official IME API for macOS |
| NSTextInputContext | macOS 10.5+ | IME system bridge | Manages IME activation/routing |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| NSAttributedString | Marked text styling | Parse underline attributes for clause display |
| NSUnderlineStyle | Composition underlines | Thick=selected clause, thin=unselected |
| NSRange | Text range specification | All protocol method parameters |

**Installation:** Built into macOS SDK, no external dependencies.

## Architecture Patterns

### Recommended Implementation Structure
```
ime_overlay_darwin.m          # VGlyphIMEOverlayView class
├── NSTextInputClient         # Protocol conformance
│   ├── setMarkedText:        # Composition preview
│   ├── insertText:           # Commit
│   ├── markedRange           # Query composition
│   ├── selectedRange         # Query cursor
│   ├── firstRectForRange:    # Candidate window position
│   └── unmarkText            # Cancel composition
└── Integration
    └── Call CompositionState # Direct V struct access
```

### Pattern 1: Core Message Flow
**What:** IME sends messages via NSTextInputContext, overlay responds with state/geometry.

**Message sequence:**
```
1. keyDown: → interpretKeyEvents: (route to IME)
2. IME → setMarkedText: (show composition "にほん")
3. User presses Space
4. IME → firstRectForCharacterRange: (position candidate window)
5. User selects candidate
6. IME → insertText: (commit "日本")
7. IME → unmarkText (clear composition)
```

**When to use:** Every IME interaction follows this flow.

**Example:**
```objc
// Source: Apple NSTextInputClient docs + Mozilla implementation
- (void)setMarkedText:(id)string
        selectedRange:(NSRange)selectedRange
     replacementRange:(NSRange)replacementRange {
    // Extract text
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string] : string;

    // Handle replacementRange edge cases (see Pitfalls)
    if (replacementRange.location == NSNotFound) {
        // Use current marked range or selection
        replacementRange = [self markedRange];
        if (replacementRange.location == NSNotFound) {
            replacementRange = [self selectedRange];
        }
    }

    // Forward to VGlyph CompositionState
    vglyph_composition_set_preedit([text UTF8String], selectedRange.location);
}
```

### Pattern 2: Coordinate Transform for Candidate Window
**What:** IME needs screen coordinates for candidate window placement.

**Transform chain:**
```
Layout coords (VGlyph byte index)
  → pango_layout_index_to_pos() → Pango rect
  → View coords (add text field offset)
  → Window coords (convertRect:toView:nil)
  → Screen coords (convertRectToScreen:)
```

**When to use:** `firstRectForCharacterRange:actualRange:` implementation.

**Example:**
```objc
// Source: Apple TextInputView sample
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    // Clamp to document bounds (see Pitfalls #7)
    NSUInteger docLength = vglyph_document_length();
    if (range.location >= docLength) {
        return NSZeroRect;
    }
    range.length = MIN(range.length, docLength - range.location);
    if (actualRange) *actualRange = range;

    // Get rect from VGlyph (Pango layout)
    float x, y, w, h;
    vglyph_get_cursor_rect_for_index(range.location, &x, &y, &w, &h);
    NSRect viewRect = NSMakeRect(x, y, w, h);

    // Transform to screen
    NSRect windowRect = [self convertRect:viewRect toView:nil];
    return [[self window] convertRectToScreen:windowRect];
}
```

### Pattern 3: Marked Text Attributes Parsing
**What:** Extract underline styles from attributed string to display clause segmentation.

**Japanese IME sends:**
- NSUnderlineStyleSingle for unselected clauses
- NSUnderlineStyleThick for selected clause (conversion target)

**When to use:** Rendering preedit with clause boundaries.

**Example:**
```objc
// Source: Mozilla NSTextInputClient implementation
- (void)setMarkedText:(id)string
        selectedRange:(NSRange)selectedRange
     replacementRange:(NSRange)replacementRange {
    NSAttributedString* attrString = [string isKindOfClass:[NSAttributedString class]]
                                      ? string : [[NSAttributedString alloc]
                                                  initWithString:string];

    // Parse underline attributes
    [attrString enumerateAttribute:NSUnderlineStyleAttributeName
                           inRange:NSMakeRange(0, attrString.length)
                           options:0
                        usingBlock:^(id value, NSRange range, BOOL *stop) {
        NSUnderlineStyle style = [value integerValue];
        bool is_thick = (style == NSUnderlineStyleThick);
        vglyph_composition_set_clause_style(range.location, range.length, is_thick);
    }];
}
```

### Anti-Patterns to Avoid
- **Implementing NSTextInputClient on MTKView directly:** Cannot modify sokol's class, use
  overlay approach (Phase 18 decision)
- **Returning view-local coordinates from firstRectForCharacterRange:** Must transform to screen
  coords (Pitfall #3)
- **Assuming replacementRange is relative to marked text:** Sometimes absolute document position
  (Pitfall #2)
- **Handling backspace during composition in app code:** Forward to IME via interpretKeyEvents
  (Pitfall #4)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| IME activation | Custom keyboard layout detection | NSTextInputContext | Handles all IME types, language switching |
| Candidate window | Custom popup rendering | System IME window | Retina/multi-monitor/accessibility handled by OS |
| Romaji→hiragana | String conversion tables | Japanese IME | OS knows all conversion rules, user dictionaries |
| Pinyin→hanzi | Phonetic mapping | Chinese IME | Tone marks, phrase completion, learning |
| Character width | EastAsianWidth table | Pango pixel metrics | Font-specific, handles all edge cases |
| Composition cancellation | Escape key handling | unmarkText | IME decides policy (commit vs cancel) |

**Key insight:** NSTextInputClient is protocol only — all logic lives in system IME. Application
provides geometry and text storage access, IME does conversion/candidates/input rules.

## Common Pitfalls

### Pitfall 1: Range Parameter Interpretation Varies by IME
**What goes wrong:** Implement `setMarkedText:selectedRange:replacementRange:` using Apple docs,
Japanese reconversion or Chinese input inserts text at wrong position.

**Why it happens:** Apple documentation states `replacementRange` is "computed from beginning of
marked text" but Japanese IME sends absolute document positions for reconversion. Chinese
keyboard bug (FB13789916) sends bogus selectedRange mid-composition.

**How to avoid:**
```objc
if (replacementRange.location == NSNotFound) {
    // Signal: use current marked range or selection
    replacementRange = [self markedRange];
    if (replacementRange.location == NSNotFound) {
        replacementRange = [self selectedRange];
    }
} else {
    // Non-NSNotFound: treat as absolute document position
    // (Japanese reconversion sends this)
}
```

**Warning signs:** Japanese basic input works, reconversion fails. Chinese input duplicates text.

**Sources:** Mozilla Bug 875674, winit Issue #3617, Microsoft NSTextInputClient blog

### Pitfall 2: Candidate Window Coordinate System Confusion
**What goes wrong:** Return view-local or window-local coords from `firstRectForCharacterRange`,
candidate window appears at screen corner or wrong monitor.

**Why it happens:** macOS screen coords origin at bottom-left, multi-monitor extends coordinate
space, Retina has backing scale factor. Must convert through three coordinate systems.

**How to avoid:**
```objc
NSRect viewRect = /* from VGlyph layout */;
NSRect windowRect = [self convertRect:viewRect toView:nil];
NSRect screenRect = [[self window] convertRectToScreen:windowRect];
return screenRect; // MUST be screen coords
```

**Warning signs:** Candidate window at bottom-left corner, wrong monitor, 2x offset on Retina.

**Sources:** Zed Issue #46055, Mozilla Bug #296687, Apple Coordinate System docs

### Pitfall 3: Korean Backspace Deletes Entire Syllable
**What goes wrong:** Backspace during Korean composition deletes entire syllable (간) instead of
last jamo (ㄴ).

**Why it happens:** Application handles backspace as "delete character" instead of forwarding to
IME. Korean syllables are composed incrementally (ㄱ + ㅏ + ㄴ = 간), backspace should decompose.

**How to avoid:**
```objc
- (void)keyDown:(NSEvent*)event {
    if ([self hasMarkedText]) {
        // Let IME handle ALL keys during composition
        [self interpretKeyEvents:@[event]];
        return;
    }
    // Handle non-IME keys normally
}
```

**Warning signs:** Korean users complain can't fix typing mistakes, backspace feels "destructive".

**Sources:** FSNotes Issue #708, Spacemacs Issue #13303

### Pitfall 4: Out-of-Bounds Range Crash
**What goes wrong:** macOS calls `attributedSubstringForProposedRange:actualRange:` with range
beyond document end, app crashes.

**Why it happens:** macOS caches ranges, may request stale range after document changes.
App hide/show or focus loss can trigger with old ranges.

**How to avoid:**
```objc
- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)range
                                               actualRange:(NSRangePointer)actualRange {
    NSUInteger docLength = vglyph_document_length();
    if (range.location >= docLength) {
        if (actualRange) *actualRange = NSMakeRange(NSNotFound, 0);
        return nil; // Not an error, just out of bounds
    }
    // Clamp range
    range.length = MIN(range.length, docLength - range.location);
    if (actualRange) *actualRange = range;
    // Return substring...
}
```

**Warning signs:** Crash after app hide/show, crash with macOS Sequoia + AI features.

**Sources:** Flutter Issue #153157, Mozilla Bug #1692379, Apple NSTextInputClient docs

## Code Examples

### Complete NSTextInputClient Minimal Implementation
```objc
// Source: Mozilla/Flutter/GLFW implementations combined
@interface VGlyphIMEOverlayView : NSView <NSTextInputClient>
@property (nonatomic) NSRange markedRange;
@property (nonatomic) NSRange selectedRange;
@end

@implementation VGlyphIMEOverlayView

// Required: Accept first responder for IME
- (BOOL)acceptsFirstResponder { return YES; }

// Required: Route keyboard through IME
- (void)keyDown:(NSEvent*)event {
    [self interpretKeyEvents:@[event]];
}

// Required: Insert committed text
- (void)insertText:(id)string replacementRange:(NSRange)range {
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string] : string;
    vglyph_composition_commit([text UTF8String]);
    [self unmarkText];
}

// Required: Set composition preview
- (void)setMarkedText:(id)string
        selectedRange:(NSRange)selRange
     replacementRange:(NSRange)repRange {
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string] : string;

    // Handle NSNotFound (see Pitfall #1)
    if (repRange.location == NSNotFound) {
        repRange = self.markedRange.location != NSNotFound
                   ? self.markedRange : self.selectedRange;
    }

    self.markedRange = NSMakeRange(repRange.location, text.length);
    self.selectedRange = NSMakeRange(repRange.location + selRange.location, 0);

    vglyph_composition_set_preedit([text UTF8String], selRange.location);
}

// Required: Clear composition
- (void)unmarkText {
    self.markedRange = NSMakeRange(NSNotFound, 0);
    vglyph_composition_clear();
}

// Required: Query composition range
- (NSRange)markedRange {
    return _markedRange;
}

// Required: Query selection
- (NSRange)selectedRange {
    return _selectedRange;
}

// Required: Check if composing
- (BOOL)hasMarkedText {
    return _markedRange.location != NSNotFound;
}

// Required: Candidate window position (see Pitfall #2)
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    // Clamp to document bounds (Pitfall #4)
    NSUInteger docLength = vglyph_document_length();
    if (range.location >= docLength) return NSZeroRect;
    range.length = MIN(range.length, docLength - range.location);
    if (actualRange) *actualRange = range;

    // Get rect from VGlyph
    float x, y, w, h;
    vglyph_get_cursor_rect_for_index(range.location, &x, &y, &w, &h);
    NSRect viewRect = NSMakeRect(x, y, w, h);

    // Transform to screen
    NSRect windowRect = [self convertRect:viewRect toView:nil];
    return [[self window] convertRectToScreen:windowRect];
}

// Required: Return supported attributes
- (NSArray<NSAttributedStringKey>*)validAttributesForMarkedText {
    return @[NSUnderlineStyleAttributeName, NSUnderlineColorAttributeName];
}

// Required: Return text substring for IME
- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)range
                                               actualRange:(NSRangePointer)actualRange {
    // Clamp (Pitfall #4)
    NSUInteger docLength = vglyph_document_length();
    if (range.location >= docLength) {
        if (actualRange) *actualRange = NSMakeRange(NSNotFound, 0);
        return nil;
    }
    range.length = MIN(range.length, docLength - range.location);
    if (actualRange) *actualRange = range;

    // Get text from VGlyph
    char* text = vglyph_get_text_in_range(range.location, range.length);
    NSAttributedString* result = [[NSAttributedString alloc]
        initWithString:[NSString stringWithUTF8String:text]];
    free(text);
    return result;
}

// Required: Handle commands (non-character keys)
- (void)doCommandBySelector:(SEL)selector {
    // Forward to app (arrow keys, etc)
    if ([self.nextResponder respondsToSelector:selector]) {
        [self.nextResponder performSelector:selector withObject:nil];
    }
}

// Optional but recommended: Convert point to character index
- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    NSPoint viewPoint = [self convertPoint:point fromView:nil];
    return vglyph_hit_test(viewPoint.x, viewPoint.y);
}

@end
```

### Japanese/Chinese Input Flow
```
Japanese IME (Kotoeri):
1. Type "nihon"
   → setMarkedText:"にほん" selectedRange:{5,0} (cursor at end)
2. Press Space
   → firstRectForCharacterRange:{0,5} (position candidate window)
   → User sees: 日本, 二本, etc
3. Select candidate
   → insertText:"日本" replacementRange:{0,5}
   → unmarkText

Chinese IME (Pinyin):
1. Type "zhong"
   → setMarkedText:"zhōng" selectedRange:{5,0}
2. Press Space (auto-select first candidate)
   → insertText:"中" replacementRange:{0,5}
   → unmarkText
OR
3. Type "guo"
   → setMarkedText:"zhōnggúo" selectedRange:{7,0}
4. Press 1-9 to select candidate
   → insertText:"中国" replacementRange:{0,7}
   → unmarkText
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSTextInput | NSTextInputClient | Mac OS X 10.5 (2007) | New protocol required |
| Per-app IME state | NSTextInputContext | Mac OS X 10.5 | Centralized IME management |
| Manual coordinate scaling | convertRectToScreen: | macOS 10.7 (2011) | Automatic Retina handling |

**Deprecated/outdated:**
- NSTextInput protocol: Replaced by NSTextInputClient in 10.5, still supported but missing
  features (nested composition, reconversion)
- Manual Retina scaling: Use convertRectToScreen/convertRectToBacking, don't multiply by scale

## Open Questions

1. **Horizontal alignment of candidate window:** Should firstRectForCharacterRange return rect
   at preedit start or cursor position within preedit? **Recommendation:** Cursor position
   (selectedRange.location) — matches TextEdit behavior.

2. **Focus loss during composition:** Auto-commit or cancel preedit? **Recommendation:**
   Auto-commit (call unmarkText which triggers implicit commit) — preserves user work.

3. **Chinese commit method:** Space only, number keys only, or both? **Recommendation:** Both —
   system IME handles, we just implement insertText.

4. **Escape key behavior:** Clear preedit or restore pre-composition text?
   **Recommendation:** Clear preedit (cancel composition) — simpler, matches most apps.

5. **Post-commit cursor positioning:** After insertText, cursor at end of inserted text or
   next character? **Recommendation:** End of inserted text — natural continuation.

## Sources

### Primary (HIGH confidence)
- [NSTextInputClient Protocol](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [Apple TextInputView Sample](https://developer.apple.com/library/archive/samplecode/TextInputView/Introduction/Intro.html)
- [Apple Text Editing Architecture](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextEditing/TextEditing.html)
- [Mozilla Bug 875674: NSTextInputClient Implementation](https://bugzilla.mozilla.org/show_bug.cgi?id=875674)
- [winit Issue #3617: Range Parameters Ignored](https://github.com/rust-windowing/winit/issues/3617)
- [FB13789916: Chinese Keyboard bogus selectedRange](https://gist.github.com/krzyzanowskim/340c5810fc427e346b7c4b06d46b1e10)
- [Microsoft: Glaring Hole in NSTextInputClient](https://learn.microsoft.com/en-us/archive/blogs/rick_schaut/the-glaring-hole-in-the-nstextinputclient-protocol)

### Secondary (MEDIUM confidence)
- [Japanese Input Method User Guide](https://support.apple.com/guide/japanese-input-method/welcome/mac)
- [Chinese IME Candidate Window](https://support.apple.com/guide/chinese-input-method/use-the-candidate-window-cim12992/mac)
- [Japanese for Mac: Typing Guide](https://redcocoon.org/cab/j4mactyping.html)
- [Flutter macOS TextInputPlugin](https://api.flutter.dev/macos-embedder/_flutter_text_input_plugin_8mm_source.html)
- [GLFW NSTextInputClient Implementation](https://fsunuc.physics.fsu.edu/git/gwm17/glfw/commit/3107c9548d7911d9424ab589fd2ab8ca8043a84a)
- [jessegrosjean NSTextInputClient Example](https://github.com/jessegrosjean/NSTextInputClient)

### Tertiary (LOW confidence - needs validation)
- Web search findings about clause segmentation underlines (multiple sources agreed)
- Community reports of Korean backspace behavior (verified across multiple projects)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official Apple protocol, no alternatives exist
- Architecture: HIGH - Verified via Mozilla/Flutter/GLFW production implementations
- Pitfalls: HIGH - All backed by filed bugs or multiple project issues

**Research date:** 2026-02-03
**Valid until:** 90 days (stable API since macOS 10.5, unlikely to change)
