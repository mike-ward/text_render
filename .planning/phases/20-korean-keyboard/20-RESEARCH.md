# Phase 20: Korean + Keyboard Integration - Research

**Researched:** 2026-02-04
**Domain:** Korean hangul composition and IME keyboard edge cases
**Confidence:** MEDIUM

## Summary

Korean IME differs from Japanese/Chinese in fundamental composition model: jamo (consonants + vowels) combine algorithmically into syllables in real-time, requiring incremental backspace decomposition (간 → 가 → ㄱ → empty). macOS Korean IME uses both composition mode (preedit with underline like Japanese) and seamless mode (immediate commit with replacementRange edits). Keyboard edge cases (dead keys after CJK, focus loss, undo during composition) require explicit state management that NSTextInputClient protocol doesn't enforce.

**Primary recommendation:** Implement Korean-specific backspace forwarding to IME (don't handle in app), test both 2-beol and 3-beol layouts, explicitly reset IME state via NSTextInputContext on focus loss to prevent dead key pollution, block undo/redo when hasMarkedText is true.

**Key finding:** Korean IME behavior varies significantly between seamless mode (TSMDocumentAccess apps like Safari) vs composition mode (basic NSTextInputClient). VGlyph should use composition mode (simpler, matches Japanese implementation) but must handle replacementRange edits for syllable modification.

## Standard Stack

### Core Framework
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| NSTextInputClient | macOS 10.5+ | Korean IME protocol | Same as JP/CH, only official API |
| NSTextInputContext | macOS 10.5+ | IME activation/deactivation | State management across focus changes |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| Unicode Hangul Syllables (U+AC00-U+D7AF) | 11,172 precomposed syllables | Display committed text |
| Hangul Jamo (U+1100-U+11FF) | Conjoining jamo for composition | Decomposition algorithm reference |
| NSRange replacementRange | Edit previously committed syllables | Korean IME sends absolute ranges |

**Installation:** Built into macOS SDK, no external dependencies.

**Note:** Unlike Japanese (romaji table) or Chinese (pinyin), Korean composition is algorithmic. The OS performs jamo→syllable conversion, not a dictionary lookup.

## Architecture Patterns

### Recommended Implementation Structure
```
composition.v                    # Existing CompositionState
├── handle_marked_text()        # Already exists for JP/CH
├── handle_insert_text()        # Already exists
└── handle_unmark_text()        # Already exists

ime_overlay_darwin.m            # Existing overlay from Phase 19
├── setMarkedText:              # Korean sends single-syllable preedit
├── insertText:                 # Commits syllable, may use replacementRange
└── doCommandBySelector:        # Forward backspace to IME when composing

New additions needed:
├── Focus loss handling         # resignFirstResponder → auto-commit
├── State cleanup               # invalidateCharacterCoordinates on blur
└── Undo blocking logic         # Check hasMarkedText before undo/redo
```

### Pattern 1: Korean Composition Flow
**What:** Korean IME builds syllables incrementally via setMarkedText, commits with insertText.

**Composition sequence:**
```
User types "gks" (간):
1. keyDown:'g' → interpretKeyEvents → setMarkedText:"ㄱ" selectedRange:{1,0}
2. keyDown:'k' → interpretKeyEvents → setMarkedText:"가" selectedRange:{1,0}
3. keyDown:'s' → interpretKeyEvents → setMarkedText:"간" selectedRange:{1,0}
4. User types space or next consonant
5. IME → insertText:"간" replacementRange:{NSNotFound,0} (or absolute range)
6. IME → unmarkText (clear composition)
```

**When to use:** Every Korean input follows this pattern (2-beol and 3-beol layouts).

**Example (Objective-C):**
```objc
// Source: Existing Phase 19 implementation + Korean-specific notes
- (void)setMarkedText:(id)string
        selectedRange:(NSRange)selRange
     replacementRange:(NSRange)repRange {
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string] : string;

    // Korean IME: repRange often NSNotFound during composition
    if (repRange.location == NSNotFound) {
        repRange = self.markedRange.location != NSNotFound
                   ? self.markedRange : self.selectedRange;
    }

    // Korean preedit is typically single syllable (간) not multi-clause
    self.markedRange = NSMakeRange(repRange.location, text.length);
    self.selectedRange = NSMakeRange(repRange.location + selRange.location, 0);

    vglyph_ime_set_marked_text([text UTF8String], selRange.location);
}
```

### Pattern 2: Backspace Decomposition
**What:** Forward backspace to IME during composition for jamo-level decomposition.

**Decomposition sequence:**
```
Preedit shows "간":
1. User presses Backspace
2. keyDown:event → hasMarkedText == true
3. interpretKeyEvents:[event] (forward to IME, don't handle in app)
4. IME → setMarkedText:"가" (removed ㄴ)
5. User presses Backspace again
6. IME → setMarkedText:"ㄱ" (removed ㅏ)
7. User presses Backspace again
8. IME → unmarkText (composition ends, preedit cleared)
```

**When to use:** Any key press during composition must go through IME first.

**Example (Objective-C):**
```objc
// Source: Flutter macOS implementation + Mozilla patterns
- (void)keyDown:(NSEvent*)event {
    // CRITICAL: Let IME handle ALL keys during composition
    if ([self hasMarkedText]) {
        [self interpretKeyEvents:@[event]];
        return; // Do not pass to application layer
    }

    // No composition: handle normally (pass to next responder)
    [self.nextResponder keyDown:event];
}

- (void)doCommandBySelector:(SEL)selector {
    // Called by IME for non-composition keys (arrow keys, etc)
    // Forward to application
    if ([self.nextResponder respondsToSelector:selector]) {
        [self.nextResponder performSelector:selector withObject:nil];
    }
}
```

### Pattern 3: Focus Loss State Cleanup
**What:** Auto-commit preedit and reset NSTextInputContext to prevent state pollution.

**Focus loss sequence:**
```
1. Text field has focus, IME active (Korean 2-beol enabled)
2. User clicks outside field or tabs away
3. resignFirstResponder called on overlay
4. Auto-commit any preedit: [self unmarkText] → insertText
5. Reset IME context: [[self inputContext] invalidateCharacterCoordinates]
6. Return first responder to MTKView
7. User switches to US keyboard layout
8. Dead keys (Option+e) now work correctly (no IME state pollution)
```

**When to use:** Every focus loss event.

**Example (Objective-C):**
```objc
// Source: Recommended pattern based on IME state issues research
- (BOOL)resignFirstResponder {
    // Auto-commit any pending composition
    if ([self hasMarkedText]) {
        // Trigger implicit commit via unmarkText
        [self unmarkText];
        // Note: macOS will call insertText with preedit contents
    }

    // Clear any cached IME state
    [[self inputContext] invalidateCharacterCoordinates];

    return [super resignFirstResponder];
}
```

### Pattern 4: Undo Blocking During Composition
**What:** Prevent undo/redo when IME composition is active.

**Rationale:** Undo during composition confuses IME state. System apps (TextEdit, Safari) block Cmd+Z when hasMarkedText is true.

**When to use:** Key event handling for Cmd+Z, Cmd+Shift+Z.

**Example (V integration):**
```v
// In v-gui widget keyboard handler
fn on_key_down(event KeyEvent) {
    if event.mods.has(.command) {
        if event.key == .z {
            // Check IME state before undo
            if ime_overlay.has_marked_text() {
                // Option 1: Ignore (recommended)
                return
                // Option 2: Beep to signal unavailable
                // C.NSBeep()
                // return
            }
            // Proceed with undo
            undo_manager.undo()
        }
    }
}
```

### Anti-Patterns to Avoid
- **Handling backspace during composition in app code:** Deletes entire syllable instead of decomposing jamo (Pitfall #1)
- **Not forwarding all keys to IME:** Arrow keys, Escape during composition must go through interpretKeyEvents
- **Skipping invalidateCharacterCoordinates on blur:** Causes dead key state pollution (Pitfall #2)
- **Allowing undo during composition:** Breaks IME state, duplicates or loses text

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Jamo → syllable conversion | Unicode arithmetic (L×588 + V×28 + T + 0xAC00) | macOS Korean IME | Handles all 11,172 syllables, edge cases |
| Backspace decomposition | Reverse syllable formula | interpretKeyEvents (IME handles) | IME knows composition state, jamo order |
| 2-beol vs 3-beol layout | Key mapping tables | System keyboard layout | User-configured, handles all variants |
| Syllable validity checking | Valid jamo combination rules | System IME | Prevents invalid syllables (ㄱㄱ) |
| Dead key state reset | Manual NSTextInputContext flags | invalidateCharacterCoordinates | Official API for state cleanup |

**Key insight:** Korean composition is algorithmically simple (19 L × 21 V × 28 T = 11,172) but edge cases (invalid combinations, layout variants, double consonants) make IME essential. Don't reimplement what the system provides.

## Common Pitfalls

### Pitfall 1: Backspace Deletes Entire Syllable Instead of Decomposing
**What goes wrong:** App handles backspace as "delete previous character", Korean syllable (간) deletes entirely instead of decomposing to (가).

**Why it happens:** Application intercepts keyDown event before IME processes it. Korean syllables are single Unicode code points (U+AC04 for 간), so string deletion removes the whole character.

**How to avoid:**
```objc
- (void)keyDown:(NSEvent*)event {
    // ALWAYS check composition state first
    if ([self hasMarkedText]) {
        // Let IME handle decomposition
        [self interpretKeyEvents:@[event]];
        return; // Critical: do not pass to app
    }
    // Only handle keys when not composing
    [self.nextResponder keyDown:event];
}
```

**Warning signs:** Korean users complain "can't fix typos", backspace feels "destructive", must delete and retype entire word.

**Sources:** [FSNotes Issue #708](https://github.com/pbek/QOwnNotes/issues/708), [Spacemacs Issue #13303](https://github.com/syl20bnr/spacemacs/issues/13303), Phase 19 RESEARCH.md Pitfall #3

### Pitfall 2: Dead Keys Don't Work After Using Korean IME
**What goes wrong:** Switch from Korean IME to US International layout, press Option+e then e, get two separate characters (´e) instead of combined (é). Or dead key becomes "sticky" affecting all subsequent input.

**Why it happens:** NSTextInputContext caches IME state, doesn't automatically reset when keyboard layout changes or focus moves. Dead key processing depends on clean state.

**How to avoid:**
```objc
// Call on every focus loss, even if no composition active
- (BOOL)resignFirstResponder {
    [[self inputContext] invalidateCharacterCoordinates];
    [self unmarkText]; // Clear any pending composition
    return [super resignFirstResponder];
}

// Also call when explicitly deactivating IME overlay
void vglyph_ime_deactivate(VGlyphOverlayHandle handle) {
    VGlyphIMEOverlayView* view = (__bridge VGlyphIMEOverlayView*)handle;
    [[view inputContext] invalidateCharacterCoordinates];
    [view unmarkText];
    // Return first responder to MTKView...
}
```

**Warning signs:** Users report "dead keys broken after typing Korean", "accent keys insert double characters", "keyboard feels stuck".

**Sources:** [winit Issue #2651](https://github.com/rust-windowing/winit/issues/2651), [Removing Dead Keys on macOS](https://samuelmeuli.com/blog/2019-11-17-removing-dead-keys-on-macos/)

### Pitfall 3: Undo/Redo During Composition Causes Text Duplication
**What goes wrong:** User types Korean syllable (composing), presses Cmd+Z, sees duplicated text or loses composition.

**Why it happens:** Undo operates on committed text buffer, but composition is ephemeral. Undoing while composing can:
- Undo previous edit, leaving preedit orphaned
- Commit preedit first, then undo commits it AND previous text
- IME and app undo stacks get out of sync

**How to avoid:**
```v
// V-side keyboard handler
fn handle_keyboard_shortcut(key KeyEvent, mut comp CompositionState) {
    if key.is_command_z() {
        // Block undo during composition
        if comp.is_composing() {
            // Option 1: Silent ignore (recommended)
            return
            // Option 2: Beep
            // platform.beep()
            // return
        }
        app.undo_manager.undo()
    }
}
```

**Warning signs:** Korean users report "undo doesn't work", "text duplicates when I press Cmd+Z", "composition disappears unexpectedly".

**Sources:** [Ghostty Issue #7225](https://github.com/ghostty-org/ghostty/issues/7225), Standard macOS app behavior (TextEdit blocks Cmd+Z during composition)

### Pitfall 4: First Korean Character Lost After Focus Change
**What goes wrong:** Focus text field, type first Korean jamo, it appears as raw Latin character ('g') instead of hangul (ㄱ). Subsequent characters compose correctly.

**Why it happens:** NSTextInputContext not fully activated when first keyDown arrives. IME initialization race condition on focus gain.

**How to avoid:**
```objc
// Ensure IME context is active before accepting input
- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    if (result) {
        // Activate input context explicitly
        [[self inputContext] activate];
        // Small delay may help in some cases (not ideal but works)
        // dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_MSEC),
        //                dispatch_get_main_queue(), ^{
        //     [[self inputContext] activate];
        // });
    }
    return result;
}
```

**Warning signs:** Korean users report "first key always wrong", "have to type twice to start composing", "IME doesn't activate immediately".

**Sources:** [Qt Bug QTBUG-136128](https://bugreports.qt.io/browse/QTBUG-136128), [rdar://FB17460926](https://openradar.appspot.com/FB17460926)

### Pitfall 5: Option+Backspace Deletes Word During Composition
**What goes wrong:** User composing Korean syllable (간), presses Option+Backspace expecting to cancel composition, instead deletes previous word.

**Why it happens:** App interprets Option+Backspace as "delete word" command before checking composition state.

**How to avoid:**
Per CONTEXT.md user decision: Option+Backspace should cancel composition first, THEN delete previous word if not composing.

```objc
- (void)keyDown:(NSEvent*)event {
    // Special handling for Option+Backspace
    if ([event keyCode] == 51 && ([event modifierFlags] & NSEventModifierFlagOption)) {
        if ([self hasMarkedText]) {
            // Cancel composition without deleting
            [self unmarkText];
            return; // Do not proceed to word deletion
        }
        // Not composing: handle as delete-word
        [self deleteWordBackward:nil];
        return;
    }

    // Other keys...
}
```

**Warning signs:** Users report "Option+Backspace deletes too much during Korean typing", "can't cancel composition easily".

**Sources:** CONTEXT.md user decision, standard macOS IME behavior

## Code Examples

### Complete Korean IME Integration
```objc
// Source: Phase 19 implementation + Korean-specific handling
@implementation VGlyphIMEOverlayView

// Key routing: CRITICAL for Korean decomposition
- (void)keyDown:(NSEvent*)event {
    // Check composition state FIRST
    if ([self hasMarkedText]) {
        // Forward ALL keys to IME during composition
        // This enables jamo decomposition on backspace
        [self interpretKeyEvents:@[event]];
        return;
    }

    // Not composing: application handles
    [self.nextResponder keyDown:event];
}

// Focus management with state cleanup
- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    if (result) {
        // Explicitly activate IME context
        [[self inputContext] activate];
    }
    return result;
}

- (BOOL)resignFirstResponder {
    // Auto-commit any pending composition
    if ([self hasMarkedText]) {
        [self unmarkText]; // Triggers implicit insertText
    }

    // Critical: Clear IME state cache to prevent dead key pollution
    [[self inputContext] invalidateCharacterCoordinates];

    return [super resignFirstResponder];
}

// Command handling: Non-character keys during composition
- (void)doCommandBySelector:(SEL)selector {
    // IME calls this for arrow keys, Enter, Escape, etc during composition
    // Forward to application layer
    if ([self.nextResponder respondsToSelector:selector]) {
        [self.nextResponder performSelector:selector withObject:nil];
    }
}

@end
```

### V-Side Undo Blocking
```v
// Source: Recommended integration with CompositionState
pub struct TextField {
mut:
    composition CompositionState
    undo_manager UndoManager
}

pub fn (mut tf TextField) on_key_down(event KeyEvent) {
    // Block undo/redo during composition
    if event.mods.has(.command) {
        match event.key {
            .z {
                if tf.composition.is_composing() {
                    // Silently ignore Cmd+Z during composition
                    return
                }
                tf.undo_manager.undo()
            }
            .y { // Cmd+Shift+Z or Cmd+Y
                if tf.composition.is_composing() {
                    return
                }
                tf.undo_manager.redo()
            }
            else {}
        }
    }

    // Other key handling...
}
```

### Escape Key Behavior
```objc
// Source: Standard macOS IME behavior
- (void)cancelOperation:(id)sender {
    // Called when user presses Escape
    if ([self hasMarkedText]) {
        // Cancel composition (don't commit)
        [self unmarkText];
        // Callback to V code clears CompositionState
        return;
    }

    // Not composing: forward to application
    [self.nextResponder cancelOperation:sender];
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| TSMDocumentAccess seamless mode | NSTextInputClient composition mode | Mac OS X 10.5 (2007) | Apps choose mode via protocol conformance |
| Manual jamo combining | System Korean IME | Always | All modern apps use system IME |
| Global IME state | Per-view NSTextInputContext | Mac OS X 10.5 | Multiple fields can have different IME states |
| No dead key cleanup | invalidateCharacterCoordinates | macOS 10.6+ | Explicit state reset API |

**Deprecated/outdated:**
- TSMDocumentAccess protocol: Seamless mode (no composition underline) requires additional protocol, complex range tracking. Modern apps use NSTextInputClient composition mode.
- Manual backspace handling: Old apps parsed syllables themselves. Now forward to IME via interpretKeyEvents.

## Open Questions

### Q1: Underline Style for Korean Preedit
**What we know:** Japanese uses thin/thick underlines for clause segmentation. Korean typically has single syllable preedit (no clauses).

**What's unclear:** Should Korean preedit use same underline as Japanese (consistency) or Korean-specific style?

**Recommendation:** Use same underline as Japanese/Chinese (single thin line). Consistency across CJK. No user decision needed per CONTEXT.md "Claude's Discretion".

### Q2: Visual Feedback on Syllable Commit
**What we know:** Japanese commits multi-character phrases, visible change. Korean commits single syllable frequently, less visible.

**What's unclear:** Should Korean commit have brief highlight to indicate finalization?

**Recommendation:** Instant (no highlight). Korean commits are frequent (every syllable), highlighting would be distracting. Match system apps (TextEdit, Safari).

### Q3: Escape Key: Cancel vs Commit
**What we know:** Both behaviors exist in different apps. TextEdit cancels, some terminal apps commit.

**What's unclear:** User expectation for VGlyph context?

**Recommendation:** Cancel (per CONTEXT.md Pitfall #5 note). More predictable - Escape = "undo what I'm doing". Aligns with Japanese IME Escape behavior.

### Q4: Arrow Keys During Composition
**What we know:** Japanese IME uses arrows to navigate between clauses. Korean has single-syllable preedit (no navigation needed).

**What's unclear:** Should arrows commit-then-move or be blocked during Korean composition?

**Recommendation:** Commit-then-move. Forward arrow key via doCommandBySelector, triggers implicit commit, then move cursor. Natural for Korean single-syllable model.

### Q5: Cmd+A During Composition
**What we know:** Some apps block Cmd+A during composition, others commit-then-select.

**What's unclear:** Expected behavior for VGlyph?

**Recommendation:** Commit-then-select. Cmd+A is "select all", not a composition command. IME implicitly commits, then selection happens. Less surprising than blocking.

## Sources

### Primary (HIGH confidence)
- [NSTextInputClient Protocol](https://developer.apple.com/documentation/appkit/nstextinputclient) - Official Apple documentation
- [Unicode Hangul Syllables Block](https://en.wikipedia.org/wiki/Hangul_Syllables) - Unicode standard reference
- [Korean IME - Microsoft Learn](https://learn.microsoft.com/en-us/globalization/input/korean-ime) - Korean IME behavior patterns
- [Mozilla Bug 875674](https://bugzilla.mozilla.org/show_bug.cgi?id=875674) - NSTextInputClient implementation details
- Phase 19 RESEARCH.md - VGlyph's existing NSTextInputClient implementation

### Secondary (MEDIUM confidence)
- [FSNotes Issue #708](https://github.com/pbek/QOwnNotes/issues/708) - Korean backspace behavior
- [winit Issue #2651](https://github.com/rust-windowing/winit/issues/2651) - Dead key IME pollution
- [Qt Bug QTBUG-136128](https://bugreports.qt.io/browse/QTBUG-136128) - First character lost after focus
- [Ghostty Release Notes 1.1.0](https://ghostty.org/docs/install/release-notes/1-1-0) - IME improvements (CJK, dead keys tested)
- [Removing Dead Keys on macOS](https://samuelmeuli.com/blog/2019-11-17-removing-dead-keys-on-macos/) - Dead key state management

### Tertiary (LOW confidence - needs validation)
- Web search findings about jamo composition algorithm (verified via Unicode standard)
- Community reports about Cmd+Z during composition (pattern across multiple projects but no official docs)
- Korean keyboard layout details (2-beol vs 3-beol) from general web sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - NSTextInputClient is only API, proven by Phase 19
- Architecture: MEDIUM - Patterns extrapolated from JP/CH, Korean-specific untested in VGlyph
- Pitfalls: MEDIUM - Real bugs from other projects, but not all verified on macOS specifically
- Keyboard edge cases: MEDIUM - Standard practices inferred, not from official guidelines

**Research date:** 2026-02-04
**Valid until:** 60 days (Korean IME stable, but macOS updates may change behavior)

**Coverage:**
- KRIM-01 to KRIM-04: Covered (jamo composition, backspace, commit, preedit display)
- KEYB-01 to KEYB-04: Covered (backspace forwarding, dead keys, focus loss, undo blocking)
- Open questions answered for all Claude's Discretion areas in CONTEXT.md

**Next steps for planner:**
- No new V modules needed (reuse CompositionState from Phase 19)
- Objective-C changes: Add focus loss handling, undo blocking, state cleanup
- Testing critical: 2-beol and 3-beol layouts, dead keys after Korean input, focus transitions
