# Phase 18: Overlay Infrastructure - Research

**Researched:** 2026-02-03
**Domain:** macOS NSView overlay with NSTextInputClient protocol
**Confidence:** HIGH

## Summary

Phase 18 creates a transparent NSView overlay positioned as sibling above MTKView to receive CJK IME
events. The overlay implements NSTextInputClient protocol skeleton (full protocol implementation is
Phase 19). Key challenge: overlay must become first responder for IME but pass clicks through to
MTKView.

**Existing code:** `ime_bridge_macos.m` uses NSView category approach (adds protocol to sokol's view).
Phase 18 replaces this with dedicated overlay class for better encapsulation and opt-in behavior.

**Primary recommendation:** Create VGlyphIMEOverlayView as transparent layer-backed NSView with
hitTest: returning nil, positioned via addSubview:positioned:relativeTo:, managed via C factory API.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AppKit | macOS 10.6+ | NSView, NSTextInputClient | Native IME integration requires AppKit |
| Objective-C | 2.0 | NSView subclass | Required for Cocoa classes |
| Auto Layout | macOS 10.7+ | Constraint-based overlay positioning | Standard for dynamic view bounds matching |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ARC | Xcode 4.2+ | Memory management | All new Objective-C code |
| Metal | macOS 10.11+ | MTKView rendering | Already used by sokol/VGlyph |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate overlay | NSView category | Category pollutes all NSView instances, can't opt-in |
| Auto Layout | Manual frame updates | Must track window resize, rotation, fullscreen manually |
| C factory API | Expose Objective-C class directly | V can't instantiate Objective-C classes without bridging |

**Installation:**
Already in AppKit framework. No additional dependencies.

## Architecture Patterns

### Recommended Project Structure
```
src/
├── ime_overlay_darwin.m     # VGlyphIMEOverlayView implementation
├── ime_overlay_darwin.h     # C API declarations
└── ime_overlay_stub.c       # Non-Darwin no-op stubs
```

### Pattern 1: Transparent Overlay with Click Pass-Through
**What:** NSView overlay that accepts first responder but doesn't block clicks to underlying views
**When to use:** IME overlay, accessibility overlays, debug overlays
**Example:**
```objective-c
// Override hitTest to pass clicks through
- (NSView *)hitTest:(NSPoint)point {
    // Always pass clicks to views underneath
    return nil;
}

// Accept first responder for keyboard input
- (BOOL)acceptsFirstResponder {
    return YES;
}
```

### Pattern 2: Sibling View with Auto Layout Bounds Matching
**What:** Position overlay as sibling (not child) of target view, match bounds via constraints
**When to use:** Overlay must be same size/position as another view without subview relationship
**Example:**
```objective-c
// Add as sibling above MTKView
NSView *parent = mtkView.superview;
[parent addSubview:overlay positioned:NSWindowAbove relativeTo:mtkView];

// Match MTKView bounds with Auto Layout
overlay.translatesAutoresizingMaskIntoConstraints = NO;
[NSLayoutConstraint activateConstraints:@[
    [overlay.leadingAnchor constraintEqualToAnchor:mtkView.leadingAnchor],
    [overlay.trailingAnchor constraintEqualToAnchor:mtkView.trailingAnchor],
    [overlay.topAnchor constraintEqualToAnchor:mtkView.topAnchor],
    [overlay.bottomAnchor constraintEqualToAnchor:mtkView.bottomAnchor]
]];
```

### Pattern 3: C API for Objective-C Classes
**What:** Factory functions return opaque void* handles to Objective-C objects
**When to use:** Expose Objective-C classes to C/V code without bridging headers
**Example:**
```objective-c
// Header: ime_overlay_darwin.h
typedef void* VGlyphOverlayHandle;
VGlyphOverlayHandle vglyph_create_ime_overlay(void* mtkView);
void vglyph_set_focused_field(VGlyphOverlayHandle handle, const char* field_id);

// Implementation: ime_overlay_darwin.m
VGlyphOverlayHandle vglyph_create_ime_overlay(void* mtkView) {
    VGlyphIMEOverlayView *overlay = [[VGlyphIMEOverlayView alloc] init];
    // Configure overlay...
    return (__bridge_retained void*)overlay;
}
```

### Pattern 4: First Responder Management
**What:** Use window.makeFirstResponder: to change keyboard focus, override
becomeFirstResponder/resignFirstResponder for notifications
**When to use:** Custom views that need keyboard input
**Example:**
```objective-c
// Host calls this when text field gains focus
void vglyph_set_focused_field(VGlyphOverlayHandle handle, const char* field_id) {
    VGlyphIMEOverlayView *overlay = (__bridge VGlyphIMEOverlayView*)handle;
    if (field_id != NULL) {
        [overlay.window makeFirstResponder:overlay];
    } else {
        [overlay.window makeFirstResponder:overlay.superview]; // Return to MTKView
    }
}

// In VGlyphIMEOverlayView:
- (BOOL)becomeFirstResponder {
    // Notify CompositionState that overlay is active
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder {
    // Auto-commit preedit on focus loss
    return [super resignFirstResponder];
}
```

### Anti-Patterns to Avoid
- **Child view of MTKView:** Layer-hosted views (MTKView uses CAMetalLayer) shouldn't have children.
Overlay as child breaks Metal rendering or becomes invisible.
- **Manual frame updates:** Don't use setFrame: in response to resize notifications. Auto Layout
handles bounds matching automatically, including fullscreen, rotation, split screen.
- **alphaValue = 0 for transparency:** Doesn't affect hit testing. View with alphaValue=0 still
blocks clicks. Must override hitTest: explicitly.
- **Calling becomeFirstResponder directly:** Don't call [overlay becomeFirstResponder]. Use
[window makeFirstResponder:overlay] which handles resignation protocol correctly.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| View bounds matching | Manual frame tracking | Auto Layout constraints | Handles resize, fullscreen, multiple displays automatically |
| First responder protocol | Custom focus tracking | makeFirstResponder: | System sends resign/become messages, checks acceptsFirstResponder |
| Click pass-through | Event forwarding | hitTest: returning nil | System routes events correctly through view hierarchy |
| C-to-Objective-C | Custom bridging layer | __bridge_retained/__bridge cast | ARC-aware, compiler-checked memory management |
| Platform detection | Custom macros | #ifdef __APPLE__ with TargetConditionals.h | Standard, reliable, Xcode-aware |

**Key insight:** AppKit's responder chain, hit testing, and Auto Layout are mature, tested systems.
Custom implementations introduce bugs around edge cases (multiple displays, fullscreen transitions,
accessibility, system keyboard navigation).

## Common Pitfalls

### Pitfall 1: Overlay Blocks Clicks to MTKView
**What goes wrong:** Transparent overlay positioned above MTKView prevents mouse events from
reaching Metal view, breaking all interaction.
**Why it happens:** By default, NSView instances handle mouse events even when transparent.
alphaValue doesn't affect hit testing.
**How to avoid:** Override hitTest: to return nil. System then passes event to next view in
hierarchy (MTKView below).
**Warning signs:** Clicks on MTKView don't register, drag events don't work, but overlay receives
keyboard input correctly.

### Pitfall 2: Layer-Backed View Hierarchy Confusion
**What goes wrong:** Setting wantsLayer on overlay or making it child of MTKView causes rendering
glitches or invisible overlay.
**Why it happens:** MTKView is layer-hosted (owns CAMetalLayer directly). Layer-hosted views
shouldn't have children. Mixing layer-backed and layer-hosted breaks assumptions.
**How to avoid:** Position overlay as sibling in same parent container, not as child of MTKView.
Don't set wantsLayer unless explicitly needed (default layer-backed inheritance usually works).
**Warning signs:** Overlay doesn't appear, Metal rendering stops working, z-order wrong.

### Pitfall 3: First Responder State Desync
**What goes wrong:** Overlay becomes first responder but VGlyph thinks MTKView still has focus, or
vice versa. IME events go to wrong handler.
**Why it happens:** Calling becomeFirstResponder directly bypasses system protocol. Window doesn't
send resignFirstResponder to previous responder.
**How to avoid:** Always use [window makeFirstResponder:view]. System handles resignation sequence
correctly. Override becomeFirstResponder/resignFirstResponder for notifications only, never call
directly.
**Warning signs:** Two views think they have focus, IME events don't arrive, text appears in wrong
field.

### Pitfall 4: Auto Layout Without Disabling Autoresizing
**What goes wrong:** Auto Layout constraints fight with autoresizing masks, causing constraint
conflicts or views positioned incorrectly.
**Why it happens:** By default, NSView uses autoresizing masks (springs and struts). When Auto
Layout constraints added, both systems try to position view.
**How to avoid:** Set translatesAutoresizingMaskIntoConstraints = NO before adding constraints.
Disables autoresizing mask translation.
**Warning signs:** Xcode console shows "Unable to simultaneously satisfy constraints", view jumps
to wrong position on window resize.

### Pitfall 5: Screen Coordinates Confusion
**What goes wrong:** firstRectForCharacterRange: returns wrong coordinates, candidate window
appears in wrong location or off-screen.
**Why it happens:** NSTextInputClient expects screen coordinates (origin bottom-left), but VGlyph
uses view coordinates (origin top-left). Coordinate systems differ.
**How to avoid:** Convert view rect to window coordinates via [view convertRect:toView:nil], then
window to screen via [window convertRectToScreen:]. Account for screen origin flip (bottom-left vs
top-left).
**Warning signs:** IME candidate window appears far from cursor, wrong monitor, or off-screen
entirely.

### Pitfall 6: Non-Darwin Build Failure
**What goes wrong:** Project fails to compile on Windows/Linux because Objective-C code or AppKit
headers included unconditionally.
**Why it happens:** .m files compiled on non-Apple platforms, or headers included without
platform guards.
**How to avoid:** Guard .m file with #ifdef __APPLE__, provide stub .c file for non-Darwin. Build
system should conditionally compile .m only on Darwin.
**Warning signs:** Compilation errors on Windows/Linux about unknown types (NSView, NSRect), linker
errors about missing Objective-C runtime.

## Code Examples

Verified patterns from official sources and production implementations:

### NSTextInputClient Protocol Skeleton
```objective-c
// Minimal stub implementation for Phase 18
// Source: NSTextInputClient header, Flutter/Mozilla implementations
@interface VGlyphIMEOverlayView : NSView <NSTextInputClient>
@end

@implementation VGlyphIMEOverlayView

#pragma mark - Required NSTextInputClient Methods

- (void)insertText:(id)string replacementRange:(NSRange)range {
    // Phase 19: forward to CompositionState
}

- (void)setMarkedText:(id)string
       selectedRange:(NSRange)selectedRange
    replacementRange:(NSRange)replacementRange {
    // Phase 19: forward to CompositionState
}

- (void)unmarkText {
    // Phase 19: forward to CompositionState
}

- (NSRange)selectedRange {
    return NSMakeRange(NSNotFound, 0);
}

- (NSRange)markedRange {
    return NSMakeRange(NSNotFound, 0);
}

- (BOOL)hasMarkedText {
    return NO;
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
                                                 actualRange:(NSRangePointer)actualRange {
    return nil;
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
    return @[];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    // Phase 19: query CompositionState for bounds
    return NSMakeRect(0, 0, 1, 20);
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    return NSNotFound;
}

- (void)doCommandBySelector:(SEL)selector {
    // Phase 19: forward special keys (arrows, escape)
}

@end
```

### Factory Function Implementation
```objective-c
// Source: Opaque pointer pattern from C interop best practices
// Header: ime_overlay_darwin.h
#ifdef __APPLE__

typedef void* VGlyphOverlayHandle;

VGlyphOverlayHandle vglyph_create_ime_overlay(void* mtkView);
void vglyph_overlay_free(VGlyphOverlayHandle handle);
void vglyph_set_focused_field(VGlyphOverlayHandle handle, const char* field_id);

#endif // __APPLE__

// Implementation: ime_overlay_darwin.m
VGlyphOverlayHandle vglyph_create_ime_overlay(void* mtkView) {
    NSView *metalView = (__bridge NSView*)mtkView;
    NSView *parent = metalView.superview;

    VGlyphIMEOverlayView *overlay = [[VGlyphIMEOverlayView alloc] init];

    // Position as sibling above MTKView
    [parent addSubview:overlay positioned:NSWindowAbove relativeTo:metalView];

    // Match MTKView bounds
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:metalView.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:metalView.trailingAnchor],
        [overlay.topAnchor constraintEqualToAnchor:metalView.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:metalView.bottomAnchor]
    ]];

    return (__bridge_retained void*)overlay;
}

void vglyph_set_focused_field(VGlyphOverlayHandle handle, const char* field_id) {
    VGlyphIMEOverlayView *overlay = (__bridge VGlyphIMEOverlayView*)handle;

    if (field_id != NULL) {
        [overlay.window makeFirstResponder:overlay];
    } else {
        // Resign first responder, return to MTKView
        NSView *metalView = nil;
        for (NSView *sibling in overlay.superview.subviews) {
            if ([sibling isKindOfClass:NSClassFromString(@"MTKView")]) {
                metalView = sibling;
                break;
            }
        }
        [overlay.window makeFirstResponder:metalView ?: overlay.superview];
    }
}

void vglyph_overlay_free(VGlyphOverlayHandle handle) {
    VGlyphIMEOverlayView *overlay = (__bridge_transfer VGlyphIMEOverlayView*)handle;
    [overlay removeFromSuperview];
    // overlay released by ARC
}
```

### Non-Darwin Stub
```c
// File: ime_overlay_stub.c
// Source: Standard cross-platform stub pattern
#ifndef __APPLE__

#include <stddef.h>

typedef void* VGlyphOverlayHandle;

VGlyphOverlayHandle vglyph_create_ime_overlay(void* mtkView) {
    return NULL;
}

void vglyph_overlay_free(VGlyphOverlayHandle handle) {
    // No-op
}

void vglyph_set_focused_field(VGlyphOverlayHandle handle, const char* field_id) {
    // No-op
}

#endif // !__APPLE__
```

### Click Pass-Through hitTest
```objective-c
// Source: Apple Event Handling documentation, CocoaDev examples
@implementation VGlyphIMEOverlayView

- (NSView *)hitTest:(NSPoint)point {
    // Pass all clicks to views underneath
    // Overlay only receives keyboard input when first responder
    return nil;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

@end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSTextInput protocol | NSTextInputClient | macOS 10.6 (2009) | New protocol adds replacementRange for better editing |
| Manual frame tracking | Auto Layout | macOS 10.7 (2011) | Constraints handle complex layouts automatically |
| NSView category on MTKView | Separate overlay sibling | Current practice | Better encapsulation, opt-in, no pollution |
| Autoresizing masks | Auto Layout constraints | macOS 10.7+ | Constraint-based more powerful for complex relationships |

**Deprecated/outdated:**
- NSTextInput: Replaced by NSTextInputClient in 10.6. Still works but missing replacementRange
  parameter.
- setFrame: in layoutSubviews: Replaced by Auto Layout. Manual frame calculations error-prone for
  multiple displays, fullscreen, split screen.

## Open Questions

Things that couldn't be fully resolved:

1. **MTKView class name detection**
   - What we know: sokol creates MTKView dynamically, class name is "MTKView"
   - What's unclear: Safe to use NSClassFromString(@"MTKView"), or should we store reference
     during factory call?
   - Recommendation: Store weak reference to MTKView during vglyph_create_ime_overlay, use for
     makeFirstResponder. Avoids string matching, faster, more reliable.

2. **Overlay cleanup responsibility**
   - What we know: Host calls vglyph_overlay_free when done
   - What's unclear: Should overlay auto-remove on window close, or rely on explicit free?
   - Recommendation: Both. Implement dealloc to removeFromSuperview for safety, but expect host to
     call free explicitly. Prevents leaks if host forgets.

3. **Multiple text fields focus tracking**
   - What we know: vglyph_set_focused_field(field_id) signals which field has focus
   - What's unclear: Does overlay need to track field_id, or just become/resign responder?
   - Recommendation: Phase 18 only tracks responder state. Phase 19 adds field_id tracking for
     multi-field apps. Keep simple for infrastructure phase.

## Sources

### Primary (HIGH confidence)
- [NSTextInputClient Protocol Reference](https://leopard-adc.pepas.com/documentation/Cocoa/Reference/NSTextInputClient_Protocol/Reference/Reference.html) - Protocol definition
- [MacOSX SDK Headers](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.6.sdk/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSTextInputClient.h) - Required/optional methods
- [Apple Auto Layout Guide](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/AutolayoutPG/WorkingwithSimpleConstraints.html) - Sibling constraints
- [Apple Event Handling Basics](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/EventHandlingBasics/EventHandlingBasics.html) - First responder management

### Secondary (MEDIUM confidence)
- [Mozilla NSTextInputClient Implementation](https://bugzilla.mozilla.org/show_bug.cgi?id=875674) - Production implementation insights
- [Flutter macOS embedder](https://api.flutter.dev/macos-embedder/_flutter_text_input_plugin_8mm_source.html) - Real-world stub patterns
- [Hit Testing Sub Views](https://eon.codes/blog/2016/01/28/Hit-testing-sub-views/) - hitTest: pass-through pattern
- [Opaque Pointers Pattern](https://interrupt.memfault.com/blog/opaque-pointers) - C API design

### Tertiary (LOW confidence)
- [GitHub NSTextInputClient Reference](https://github.com/jessegrosjean/NSTextInputClient) - Community reference (noted as "probably not 100% right")
- Various Stack Overflow discussions about layer-backed views and MTKView

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - AppKit/NSTextInputClient well-documented, mature APIs
- Architecture: HIGH - Patterns verified in production (Mozilla, Flutter, SDL)
- Pitfalls: MEDIUM - Extrapolated from bug reports and forum discussions, not all tested firsthand

**Research date:** 2026-02-03
**Valid until:** ~90 days (AppKit APIs very stable, changes rare)
