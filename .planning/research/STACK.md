# Technology Stack — Text Editing & IME

**Project:** VGlyph v1.3
**Focus:** Text editing capabilities and IME support
**Researched:** 2026-02-02 (updated 2026-02-03)
**Confidence:** HIGH

## Executive Summary

Text editing adds cursor positioning, selection, mutation, and IME on top of existing rendering.
No new C libraries — Pango provides all needed APIs. macOS IME via NSTextInputClient protocol.
V FFI handles Objective-C callbacks. Integration: existing hit testing foundation already built.

## Stack Additions Required

### None — Existing Stack Sufficient

**All needed APIs already available through existing dependencies:**
- Pango 1.0 (existing)
- macOS Cocoa/Foundation frameworks (existing via accessibility layer)
- Objective-C runtime (existing via accessibility/objc_helpers.h)

**Rationale:** Text editing is API extension, not new dependencies.

## API Details

### Pango APIs for Editing (Already Bound)

Most needed APIs already declared in `c_bindings.v`. Missing APIs listed below.

#### Already Available

| API | Purpose | File |
|-----|---------|------|
| `pango_layout_index_to_pos` | Cursor position -> rect | c_bindings.v:530 |
| `pango_layout_set_text` | Text mutation | c_bindings.v:524 |
| `pango_layout_xy_to_index` | Mouse -> text index | Needs binding |

#### Need to Add

| API | Signature | Purpose |
|-----|-----------|---------|
| `pango_layout_get_cursor_pos` | `void(PangoLayout*, int, PangoRectangle*, PangoRectangle*)` | Strong/weak cursor rects |
| `pango_layout_xy_to_index` | `bool(PangoLayout*, int, int, int*, int*)` | Screen coords -> byte index |
| `pango_layout_move_cursor_visually` | `void(PangoLayout*, bool, int, int, int, int*, int*)` | Keyboard navigation |

**Add to c_bindings.v:**
```v
fn C.pango_layout_get_cursor_pos(&C.PangoLayout, int, &C.PangoRectangle, &C.PangoRectangle)
fn C.pango_layout_xy_to_index(&C.PangoLayout, int, int, &int, &int) bool
fn C.pango_layout_move_cursor_visually(&C.PangoLayout, bool, int, int, int, &int, &int)
```

### Pango Cursor APIs — Detailed Behavior

#### pango_layout_get_cursor_pos

Returns two cursor rects (strong/weak) as zero-width rectangles with run height.

**Strong cursor:** Insertion point for text matching layout base direction
**Weak cursor:** Insertion point for opposite-direction text (bidi)

**Parameters accept NULL** if only one cursor needed.

**Source:** [Pango.Layout.get_cursor_pos](https://docs.gtk.org/Pango/method.Layout.get_cursor_pos.html)

#### pango_layout_xy_to_index

Converts screen coordinates to byte index. Returns TRUE if coords inside layout, FALSE outside.

**Clamping behavior:**
- Y outside: snaps to nearest line
- X outside: snaps to line start/end

**Trailing output:** 0 for leading edge, N for trailing edge (grapheme position)

**Source:** [Pango.Layout.xy_to_index](https://docs.gtk.org/Pango/method.Layout.xy_to_index.html)

#### pango_layout_move_cursor_visually

Computes new cursor position from old position + direction (visual order).

**Key for:** Left/right arrow navigation respecting bidi text order

**Handles:**
- Bidirectional text jumps
- Grapheme boundaries (multi-char glyphs like emoji)
- Visual vs logical order differences

**Source:** [Pango.Layout.move_cursor_visually](https://docs.gtk.org/Pango/method.Layout.move_cursor_visually.html)

### macOS IME — NSTextInputClient Protocol

**Protocol:** `NSTextInputClient`
**Framework:** AppKit (Cocoa)
**Purpose:** IME composition window positioning and marked text handling

#### Required Methods

| Method | Purpose |
|--------|---------|
| `insertText:replacementRange:` | Insert committed text |
| `setMarkedText:selectedRange:replacementRange:` | Handle composition |
| `markedRange()` | Get marked text range |
| `selectedRange()` | Get current selection |
| `firstRectForCharacterRange:actualRange:` | Position IME candidate window |
| `unmarkText()` | Clear composition |
| `validAttributesForMarkedText()` | Supported attributes |
| `hasMarkedText()` | Check composition state |
| `attributedSubstringForProposedRange:actualRange:` | Text for IME |

**Source:** [NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient)

---

## CJK IME Workarounds (Without Sokol Modification)

**Added:** 2026-02-03
**Confidence:** MEDIUM

### Problem Statement

The core problem: sokol creates its own MTKView subclass (`_sapp_macos_view`) that doesn't implement
`NSTextInputClient`. The existing VGlyph approach using an NSView category fails because category
methods on NSView don't automatically inherit to MTKView subclasses in a way that macOS's text input
system recognizes for protocol conformance.

**Constraint:** No sokol modifications allowed.

### Approaches Evaluated

#### 1. Overlay NSView (Transparent Sibling) — RECOMMENDED

**How it works:**
- Create a custom NSView subclass implementing NSTextInputClient
- Add as sibling to sokol's MTKView (not child, to avoid Metal layer issues)
- Make it first responder during text editing mode
- Forward keyboard events through NSTextInputContext to this view
- Render results in VGlyph (overlay view remains visually transparent)

**Pros:**
- No sokol modification required
- Clean separation of concerns (IME handling vs rendering)
- Matches CEF's proven architecture for offscreen IME
- Can be enabled/disabled per text field focus
- Doesn't interfere with Metal rendering pipeline

**Cons:**
- Requires careful first responder management
- Must coordinate event routing between views
- Adds complexity to initialization (need NSWindow access)
- Candidate window positioning requires coordinate transforms

**Feasibility:** HIGH

**Implementation pattern (Objective-C):**
```objc
// VGlyphTextInputView.h
@interface VGlyphTextInputView : NSView <NSTextInputClient>
@property (nonatomic) NSMutableAttributedString *markedText;
@property (nonatomic) NSRange markedRange;
@property (nonatomic) NSRange selectedRange;
// Callbacks to V code
@property (nonatomic) IMEMarkedTextCallback markedCallback;
@property (nonatomic) IMEInsertTextCallback insertCallback;
@property (nonatomic) IMEBoundsCallback boundsCallback;
@property (nonatomic) void* userData;
@end

// Initialization from V (after sokol window created)
void vglyph_ime_init(void) {
    NSWindow* window = sapp_macos_get_window();
    NSView* contentView = [window contentView];

    // Create invisible input view
    VGlyphTextInputView* inputView = [[VGlyphTextInputView alloc]
        initWithFrame:contentView.bounds];
    inputView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Add as sibling (not subview of MTKView)
    [contentView addSubview:inputView positioned:NSWindowAbove relativeTo:nil];

    // Store reference for later activation
    g_input_view = inputView;
}

// Activate when text field gains focus
void vglyph_ime_activate(void) {
    [g_input_view.window makeFirstResponder:g_input_view];
}

// Deactivate when text field loses focus
void vglyph_ime_deactivate(void) {
    // Return first responder to MTKView for normal input
    NSView* mtkView = [[sapp_macos_get_window() contentView] subviews][0];
    [g_input_view.window makeFirstResponder:mtkView];
}
```

**Key NSTextInputClient methods:**
```objc
@implementation VGlyphTextInputView

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    // Route through text input system
    [self.inputContext handleEvent:event];
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string] : string;
    if (self.insertCallback) {
        self.insertCallback([text UTF8String], self.userData);
    }
    [self unmarkText];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selRange
      replacementRange:(NSRange)repRange {
    // ... store marked text, notify V
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    if (self.boundsCallback) {
        float x, y, w, h;
        self.boundsCallback(self.userData, &x, &y, &w, &h);
        NSRect viewRect = NSMakeRect(x, y, w, h);
        return [[self window] convertRectToScreen:
                    [self convertRect:viewRect toView:nil]];
    }
    return NSZeroRect;
}

// ... other NSTextInputClient methods
@end
```

---

#### 2. Runtime Method Injection (class_addMethod + class_addProtocol)

**How it works:**
- At runtime, find sokol's `_sapp_macos_view` class
- Use `class_addMethod` to add all NSTextInputClient methods
- Use `class_addProtocol` to declare protocol conformance
- MTKView instance now responds to NSTextInputClient messages

**Pros:**
- No new views or responder chain changes
- Methods live on actual rendering view
- Theoretically clean integration

**Cons:**
- Requires knowing sokol's internal class name (`_sapp_macos_view`)
- Fragile — breaks if sokol renames internal class
- Must be called before sokol creates its view (timing sensitive)
- Type encoding strings must match exactly
- `conformsToProtocol:` check may still fail (protocol not in class declaration)

**Feasibility:** MEDIUM

**Implementation pattern:**
```objc
#import <objc/runtime.h>

void vglyph_ime_inject_protocol(void) {
    // Get sokol's view class (internal name may change)
    Class viewClass = NSClassFromString(@"_sapp_macos_view");
    if (!viewClass) {
        // Fallback: search window's content view subviews for MTKView
        NSWindow* window = sapp_macos_get_window();
        for (NSView* subview in [[window contentView] subviews]) {
            if ([subview isKindOfClass:[MTKView class]]) {
                viewClass = [subview class];
                break;
            }
        }
    }
    if (!viewClass) return; // Failed to find view

    // Add protocol conformance
    Protocol* protocol = @protocol(NSTextInputClient);
    class_addProtocol(viewClass, protocol);

    // Add each required method
    // insertText:replacementRange:
    class_addMethod(viewClass,
        @selector(insertText:replacementRange:),
        (IMP)vglyph_insertText_imp,
        "v@:@{NSRange=QQ}");

    // setMarkedText:selectedRange:replacementRange:
    class_addMethod(viewClass,
        @selector(setMarkedText:selectedRange:replacementRange:),
        (IMP)vglyph_setMarkedText_imp,
        "v@:@{NSRange=QQ}{NSRange=QQ}");

    // ... all other NSTextInputClient methods
}

// Method implementations
void vglyph_insertText_imp(id self, SEL _cmd, id string, NSRange range) {
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string] : string;
    if (g_insert_callback) {
        g_insert_callback([text UTF8String], g_user_data);
    }
}
```

**Why MEDIUM feasibility:**
- Works technically but depends on sokol internals
- Type encoding strings are error-prone
- May not survive sokol updates

---

#### 3. ISA Swizzling (object_setClass)

**How it works:**
- Create custom subclass of sokol's view class at runtime
- Add NSTextInputClient methods to this subclass
- Use `object_setClass` to change existing view's class to subclass

**Pros:**
- Works on existing instance (no timing issues)
- Subclass properly inherits all MTKView behavior
- Protocol conformance can be declared on subclass

**Cons:**
- Must ensure subclass has same instance variable layout
- Requires finding the view instance after sokol creates it
- Still depends on sokol's internal class structure
- Complex setup with `objc_allocateClassPair`/`objc_registerClassPair`

**Feasibility:** MEDIUM

**Implementation pattern:**
```objc
void vglyph_ime_swizzle_view(void) {
    NSWindow* window = sapp_macos_get_window();
    NSView* mtkView = nil;

    // Find sokol's MTKView
    for (NSView* subview in [[window contentView] subviews]) {
        if ([subview isKindOfClass:[MTKView class]]) {
            mtkView = subview;
            break;
        }
    }
    if (!mtkView) return;

    // Create subclass dynamically
    Class originalClass = [mtkView class];
    const char* subclassName = "VGlyphIMEView";
    Class subclass = objc_allocateClassPair(originalClass, subclassName, 0);

    // Add protocol
    class_addProtocol(subclass, @protocol(NSTextInputClient));

    // Add methods
    class_addMethod(subclass, @selector(insertText:replacementRange:),
                    (IMP)vglyph_insertText_imp, "v@:@{NSRange=QQ}");
    // ... other methods

    // Register the class
    objc_registerClassPair(subclass);

    // Swizzle the instance's class
    object_setClass(mtkView, subclass);
}
```

---

#### 4. NSTextInputContext with Remote Client (CEF Pattern)

**How it works:**
- Create standalone NSTextInputClient object (not a view)
- Create NSTextInputContext initialized with this client
- Override MTKView's `-inputContext` to return custom context
- Key events routed through this context

**Pros:**
- Proven pattern (used by CEF/Chromium)
- Minimal view hierarchy changes
- Client can be pure Objective-C object

**Cons:**
- Still requires modifying MTKView's `-inputContext` method (via swizzling)
- Coordinate conversion more complex (client isn't a view)
- Less straightforward than overlay approach

**Feasibility:** MEDIUM

**Implementation pattern:**
```objc
// Standalone client (not a view)
@interface VGlyphTextInputClient : NSObject <NSTextInputClient>
@end

@implementation VGlyphTextInputClient
// ... implement all NSTextInputClient methods
@end

void vglyph_ime_setup_context(void) {
    // Create client and context
    g_input_client = [[VGlyphTextInputClient alloc] init];
    g_input_context = [[NSTextInputContext alloc] initWithClient:g_input_client];

    // Swizzle MTKView's -inputContext to return our context
    Class mtkViewClass = [MTKView class];
    Method originalMethod = class_getInstanceMethod(mtkViewClass, @selector(inputContext));
    Method swizzledMethod = class_getInstanceMethod([self class],
                                                    @selector(vglyph_inputContext));
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

- (NSTextInputContext*)vglyph_inputContext {
    return g_input_context;  // Return our custom context
}
```

---

### Recommendation

**Use Approach 1: Overlay NSView**

Rationale:
1. **Most robust:** No dependency on sokol internals or class names
2. **Proven pattern:** CEF uses similar architecture for off-screen rendering
3. **Clean separation:** IME handling isolated from rendering
4. **Survivable:** Won't break when sokol updates
5. **Reversible:** Can be disabled without affecting core functionality

The overlay approach requires more initial setup (view creation, responder management) but provides
the most maintainable solution. The runtime injection approaches (2, 3, 4) are fragile and depend on
implementation details that may change.

### Implementation Notes for Overlay Approach

#### Initialization Sequence

```
1. sokol creates window and MTKView (automatic via sapp)
2. After first frame (ensure window exists):
   - Call vglyph_ime_init() to create overlay NSView
   - Register V callbacks for marked text, insert, bounds
3. When text field gains focus:
   - Call vglyph_ime_activate() to make overlay first responder
4. During text input:
   - Keyboard events go to overlay -> NSTextInputContext -> callbacks -> V
   - V updates CompositionState, triggers redraw with preedit underlines
5. When text field loses focus:
   - Call vglyph_ime_deactivate() to return responder to MTKView
```

#### Coordinate Transformation

The candidate window needs screen coordinates. Transform chain:
```
Layout coordinates (VGlyph)
    -> View coordinates (add text field offset)
    -> Window coordinates (convertRect:toView:nil)
    -> Screen coordinates (convertRectToScreen:)
```

#### First Responder Management

Critical: Only make overlay first responder when VGlyph text editing is active.
Otherwise normal sokol keyboard events won't work.

```v
// V-side integration
fn on_text_field_focus(field &TextField) {
    C.vglyph_ime_activate()
    field.is_ime_active = true
}

fn on_text_field_blur(field &TextField) {
    if field.composition.is_composing() {
        // Commit pending composition before deactivating
        commit_text := field.composition.commit()
        field.insert_text(commit_text)
    }
    C.vglyph_ime_deactivate()
    field.is_ime_active = false
}
```

### What NOT to Try

1. **NSView Category on NSView base class** — Already tried, doesn't work. MTKView subclasses don't
   pick up category methods for protocol conformance checks.

2. **Method swizzling -keyDown: alone** — Not enough. Need full NSTextInputClient protocol for IME
   candidate window, marked text ranges, etc.

3. **Hidden NSTextField** — Heavyweight, brings AppKit text system baggage, coordinate sync issues.

4. **Forking sokol** — Violates constraint. Also creates maintenance burden.

---

## Integration Strategy (Original)

**Reuse existing Objective-C bridge** from accessibility layer:
- `accessibility/objc_helpers.h` (C wrapper for objc_msgSend)
- `accessibility/objc_bindings_darwin.v` (V FFI declarations)
- Pattern: wrap NSTextInputClient methods as C functions callable from V

**Implementation approach:**
1. Create `text_input_objc_darwin.v` with NSTextInputClient wrapper
2. Add helper functions to `objc_helpers.h` for NSTextInputClient callbacks
3. V widget layer calls Objective-C bridge, bridge calls back to V

**Example existing pattern (from accessibility):**
```v
fn C.v_msgSend_void_id(self Id, op SEL, arg1 voidptr)
pub fn set_accessibility_label(elem Id, label string) {
    label_ns := ns_string(label)
    C.v_msgSend_void_id(elem, sel_register_name('setAccessibilityLabel:'), label_ns)
}
```

**New pattern for IME:**
```v
fn C.v_msgSend_nsrange(self Id, op SEL) C.NSRange
pub fn get_marked_range(input_context Id) NSRange {
    return C.v_msgSend_nsrange(input_context, sel_register_name('markedRange'))
}
```

### Text Mutation Strategy

**Pango has no incremental mutation API.** Must rebuild layout on every change.

**Process:**
1. Maintain text buffer in V (string)
2. On insert/delete: V string manipulation (`s[..pos] + new_text + s[pos..]`)
3. Call `pango_layout_set_text(layout, buffer.str, buffer.len)`
4. Invalidate layout cache (create new cache entry)

**Optimization:** Layout cache handles repeated renders of same text.
**Tradeoff:** Simple API, slightly higher latency on edits vs incremental update.

**Source:** [Pango.Layout.set_text](https://docs.gtk.org/Pango/method.Layout.set_text.html)

## Integration with Existing Stack

### Hit Testing Foundation (Existing)

**Already implemented in `layout_query.v`:**

| Function | Status | Use |
|----------|--------|-----|
| `hit_test(x, y)` | Exists | Mouse -> byte index |
| `get_char_rect(index)` | Exists | Index -> rect |
| `get_closest_offset(x, y)` | Exists | Snap to nearest char |
| `get_selection_rects(start, end)` | Exists | Selection highlighting |

**These are foundational for editing. No changes needed.**

### Cursor Position API (New)

**Add to `layout_query.v`:**
```v
pub fn (l Layout) get_cursor_pos(index int) ?(gg.Rect, gg.Rect) {
    // Call pango_layout_get_cursor_pos
    // Convert PangoRectangle to gg.Rect
    // Return (strong_cursor, weak_cursor)
}

pub fn (l Layout) move_cursor(index int, direction int, visual bool) int {
    // Call pango_layout_move_cursor_visually
    // Return new index
}
```

### Text Mutation API (New)

**Add to `api.v` (TextSystem):**
```v
pub fn (mut ts TextSystem) mutate_text(original string, pos int, insert string,
                                        delete_len int) !Layout {
    // 1. String manipulation
    mut buf := original[..pos] + insert
    if pos + delete_len < original.len {
        buf += original[pos + delete_len..]
    }

    // 2. Rebuild layout
    return ts.ctx.layout_text(buf, cfg)
}
```

**Alternative:** Widget layer handles mutation, VGlyph just re-layouts.

### IME Integration (New Module)

**Create `text_input_darwin.v` (parallel to accessibility layer):**

```v
module vglyph

@[if darwin]
struct TextInputContext {
mut:
    input_client Id
    marked_range NSRange
}

pub fn (mut ctx TextInputContext) set_marked_text(text string, sel_range NSRange) {
    // Bridge to NSTextInputClient
}

pub fn (ctx TextInputContext) get_first_rect_for_range(range NSRange) gg.Rect {
    // Query layout for character rects
    // Convert to screen coords
    // Return for IME candidate window positioning
}
```

**Platform abstraction:** Stub implementation for non-macOS (no-op).

## V Language FFI Considerations

### C Function Binding Pattern

V requires explicit C function declarations. Pattern already established:

```v
// In c_bindings.v
fn C.pango_layout_get_cursor_pos(&C.PangoLayout, int, &C.PangoRectangle, &C.PangoRectangle)

// In V code
pub fn (l Layout) get_cursor_pos(index int) ?(gg.Rect, gg.Rect) {
    mut strong := C.PangoRectangle{}
    mut weak := C.PangoRectangle{}
    unsafe {
        C.pango_layout_get_cursor_pos(l.handle, index, &strong, &weak)
    }
    return (pango_rect_to_gg(strong), pango_rect_to_gg(weak))
}
```

**Source:** [V Calling C](https://docs.vlang.io/v-and-c.html)

### Objective-C Bridge Pattern

Already working in accessibility layer. Pattern:

1. **C header** (`objc_helpers.h`): Inline wrapper for `objc_msgSend` with typed signatures
2. **V FFI** (`objc_bindings_darwin.v`): Declare C wrappers as `fn C.v_msgSend_XXX(...)`
3. **V wrapper** (`backend_darwin.v`): V functions call C wrappers

**No new infrastructure needed.** Extend existing pattern for NSTextInputClient.

### Struct Handling

Pango structs already defined in `c_bindings.v`. NSRange/NSRect needed:

```v
@[typedef]
pub struct C.NSRange {
pub:
    location int
    length int
}
```

**Add to `objc_bindings_darwin.v` alongside existing NSRect.**

### Callback Handling

V supports callbacks via function types:

```v
type TextInputCallback = fn (mut ctx TextInputContext, text string)

// Register with Objective-C runtime via class_addMethod
```

**Precedent:** V channels and closures handle async C callbacks.

**Limitation:** Global function pointers only (no closures across FFI boundary).
**Mitigation:** Single global input context, dispatch to active widget.

## What NOT to Add

### ICU (International Components for Unicode)

**Why skip:** Pango already handles Unicode normalization, grapheme breaking, bidi.
**Redundant with:** HarfBuzz (via Pango), FriBidi (via Pango).
**Cost:** 25+ MB dependency for capabilities already present.

### Platform-Specific Text APIs

**Why skip:**
- Windows Text Services Framework (TSF): Windows IME
- Linux IBus/Fcitx: Linux IME

**Rationale:** v1.3 scope is macOS primary. Other platforms later.
**Decision:** Stub implementations for non-Darwin builds.

### Text Input Method Engines

**Why skip:** VGlyph consumes IME output, doesn't implement IME.
**Responsibility:** OS provides IME (Japanese, Chinese input methods).
**VGlyph role:** Display composition, position candidate window, commit text.

### Undo/Redo Infrastructure

**Why skip:** Widget layer concern, not text rendering.
**Rationale:** VGlyph provides primitives (cursor pos, mutation). v-gui handles state.
**Decision:** Document undo/redo patterns in v-gui integration examples.

### Text Editing Commands (Copy/Paste/Select All)

**Why skip:** v-gui event handlers manage clipboard, commands.
**VGlyph provides:** Selection rects, hit testing, cursor geometry.
**v-gui provides:** Keyboard events, clipboard access, command dispatch.

## API Surface Summary

### Core Editing Primitives (VGlyph)

| API | Input | Output | Layer |
|-----|-------|--------|-------|
| `get_cursor_pos(index)` | Byte index | Strong/weak cursor rects | layout_query.v |
| `move_cursor(index, dir)` | Index, direction | New index | layout_query.v |
| `get_char_rect(index)` | Byte index | Character rect | layout_query.v (exists) |
| `get_selection_rects(start, end)` | Range | Highlight rects | layout_query.v (exists) |
| `hit_test(x, y)` | Coords | Byte index | layout_query.v (exists) |
| `layout_text(text, cfg)` | Text, config | Layout | api.v (exists) |

### IME Support (VGlyph — macOS only)

| API | Purpose | Layer |
|-----|---------|-------|
| `new_text_input_context()` | Create IME context | text_input_darwin.v |
| `set_marked_text(text, range)` | Composition preview | text_input_darwin.v |
| `commit_text(text)` | Finalize input | text_input_darwin.v |
| `get_marked_range()` | Query composition | text_input_darwin.v |
| `first_rect_for_range(range)` | Candidate window pos | text_input_darwin.v |

### Widget Integration (v-gui)

| Component | Responsibility |
|-----------|---------------|
| TextField/TextArea | State management, event handling, focus |
| VGlyph | Cursor geometry, selection rects, rendering |
| v-gui event loop | Keyboard events, mouse events, blink timer |

## Build Configuration

### No New Dependencies

```bash
# v1.2 build (unchanged)
v -cc clang -cflags "`pkg-config --cflags pango pangoft2`" \
  -ldflags "`pkg-config --libs pango pangoft2`" .

# macOS adds existing frameworks (no change)
-framework Foundation -framework Cocoa
```

### Conditional Compilation

```v
// Existing pattern from accessibility layer
@[if darwin]
struct TextInputContext { ... }

@[if !darwin]
struct TextInputContext { } // Stub
```

### No Profile Flag Changes

Editing features are unconditional. No `-d editing` flag needed.

## Testing Strategy

### Unit Tests (Pango APIs)

```v
// _cursor_test.v
fn test_cursor_position() {
    mut ts := vglyph.new_text_system(mut ctx)!
    layout := ts.layout_text('Hello', cfg)!

    pos := layout.get_cursor_pos(0) or { panic(err) }
    assert pos.0.width == 0 // Zero-width cursor
}
```

### Integration Tests (IME)

**Manual testing required** for IME on macOS:
1. Enable Japanese input method
2. Type "nihon" -> see composition
3. Press Space -> see candidates
4. Press Enter -> commit

**Automated:** Difficult (requires OS input method simulation).

### Demo (`editor_demo.v` extension)

**Extend existing demo:**
- Add cursor rendering
- Add selection highlighting
- Add keyboard navigation
- Add IME composition preview

## Version Planning

### v1.3.0 Scope

**Minimum for release:**
- Cursor positioning API (`get_cursor_pos`, `move_cursor`)
- Text mutation (string ops + re-layout)
- macOS IME via NSTextInputClient
- v-gui TextField widget (basic)
- Working demo

**Deferred to v1.3.1+:**
- Multi-line editing improvements (TextArea)
- Linux/Windows IME (IBus, TSF)
- Advanced keyboard navigation (word jump, etc.)

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Objective-C callback complexity | Medium | Reuse accessibility pattern |
| IME candidate window positioning | Medium | Test early with CJK input |
| V string mutation performance | Low | Layout cache handles repeated text |
| Platform-specific IME bugs | High | Limit v1.3 to macOS, stub others |
| Sokol MTKView constraint | High | Use overlay NSView approach |

## Open Questions

1. **Overlay NSView z-order with sokol?** — Need to verify overlay stays above MTKView after window
   resize or fullscreen transitions.

## Sources

**Pango Documentation (HIGH confidence):**
- [pango_layout_get_cursor_pos](https://docs.gtk.org/Pango/method.Layout.get_cursor_pos.html)
- [pango_layout_xy_to_index](https://docs.gtk.org/Pango/method.Layout.xy_to_index.html)
- [pango_layout_move_cursor_visually](https://docs.gtk.org/Pango/method.Layout.move_cursor_visually.html)
- [pango_layout_set_text](https://docs.gtk.org/Pango/method.Layout.set_text.html)

**Apple Documentation (HIGH confidence):**
- [NSTextInputClient Protocol](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [class_addMethod](https://developer.apple.com/documentation/objectivec/1418901-class_addmethod)
- [class_addProtocol](https://developer.apple.com/documentation/objectivec/1418773-class_addprotocol)

**V Language (HIGH confidence):**
- [V Calling C](https://docs.vlang.io/v-and-c.html)

**IME Workaround Sources (MEDIUM confidence):**
- [CEF IME for Mac Off-Screen Rendering](https://www.magpcss.org/ceforum/viewtopic.php?f=8&t=10470) —
  Proven architecture using NSTextInputContext with remote client
- [Sokol IME Issue #595](https://github.com/floooh/sokol/issues/595) — Confirms sokol doesn't
  implement IME, recommends application-level hooks
- [GLFW NSTextInputClient Implementation](https://fsunuc.physics.fsu.edu/git/gwm17/glfw/commit/3107c9548d7911d9424ab589fd2ab8ca8043a84a) —
  Reference implementation of NSTextInputClient methods
- [Method Swizzling - NSHipster](https://nshipster.com/method-swizzling/) — Swizzling best practices
- [mikeash.com - Creating Classes at Runtime](https://www.mikeash.com/pyblog/friday-qa-2010-11-6-creating-classes-at-runtime-in-objective-c.html) —
  Dynamic class creation patterns

**v-gui Framework (MEDIUM confidence):**
- [vlang/gui Repository](https://github.com/vlang/gui)
- [vlang/ui Repository](https://github.com/vlang/ui)

**Implementation Examples (MEDIUM confidence):**
- [NSTextInputClient Example](https://github.com/jessegrosjean/NSTextInputClient)
- Mozilla Firefox NSTextInputClient implementation

---

*Research complete. Stack sufficient. CJK IME requires overlay NSView approach.*
