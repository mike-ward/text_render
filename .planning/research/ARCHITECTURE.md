# Architecture Research: CJK IME Integration

**Domain:** CJK (Chinese/Japanese/Korean) Input Method Editor support for VGlyph
**Researched:** 2026-02-03
**Confidence:** MEDIUM (architecture patterns verified, sokol workaround requires implementation)

## Summary

CJK IME integration requires solving the "sokol MTKView problem": VGlyph's existing NSTextInputClient
implementation uses an NSView category, but sokol renders through MTKView which doesn't inherit
category methods. The IME system queries MTKView directly, bypassing VGlyph's bridge.

**Key architectural decision:** Use a transparent overlay NSView that sits above the MTKView, receives
IME events, and forwards them to VGlyph's existing CompositionState. This avoids modifying sokol while
leveraging VGlyph's existing infrastructure (composition.v, ime_bridge_macos.m, clause rendering).

The existing architecture is well-designed for this addition:
- `CompositionState` already tracks multi-clause preedit with style info
- `ClauseRects` provides geometry for underline rendering
- `get_composition_bounds()` returns bounds for candidate window
- Callbacks registered via `ime_register_callbacks()`

**What's missing:** The native bridge that actually receives IME events. The current NSView category
approach doesn't work; we need an overlay view that does.

## New Components

### Component 1: IMEOverlayView (Objective-C)

**Purpose:** Transparent NSView overlay conforming to NSTextInputClient protocol
**Location:** `ime_overlay_macos.m` (new file in vglyph root)
**Interfaces with:** ime_bridge_macos.h callbacks, sokol window via sapp_macos_get_window()

**Design:**
```objc
@interface VGlyphIMEOverlayView : NSView <NSTextInputClient>
@property (nonatomic, strong) NSTextInputContext* inputContext;
@property (nonatomic, assign) NSRect textBounds;  // Updated from V
@end

@implementation VGlyphIMEOverlayView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _inputContext = [[NSTextInputContext alloc] initWithClient:self];
        [self setWantsLayer:YES];
        [self.layer setBackgroundColor:CGColorGetConstantColor(kCGColorClear)];
    }
    return self;
}

// NSTextInputClient protocol methods forward to existing callbacks
- (void)insertText:(id)string replacementRange:(NSRange)range { ... }
- (void)setMarkedText:(id)string selectedRange:(NSRange)sel replacementRange:(NSRange)rep { ... }
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual { ... }
// ... etc
@end
```

**Key properties:**
- Transparent (no rendering, only event capture)
- First responder for key events during text editing
- Positioned exactly over text area (bounds updated from V)
- Owns NSTextInputContext for IME session management

### Component 2: IME Overlay Manager (V)

**Purpose:** Initialize, position, and manage the overlay view lifecycle
**Location:** `ime_manager_darwin.v` (new file)
**Interfaces with:** ime_overlay_macos.m via C FFI, editor state, sokol window

**API:**
```v
// Initialize overlay (call once at init)
pub fn ime_init_overlay(window voidptr) bool

// Update overlay bounds when text area moves/resizes
pub fn ime_set_overlay_bounds(x f32, y f32, width f32, height f32)

// Activate IME input (give overlay key focus)
pub fn ime_activate()

// Deactivate IME input (return key focus to main view)
pub fn ime_deactivate()

// Check if overlay is active
pub fn ime_is_active() bool
```

**Stub file for non-darwin:**
```v
// ime_manager_stub.v
@[if !darwin]
pub fn ime_init_overlay(window voidptr) bool { return false }
pub fn ime_set_overlay_bounds(x f32, y f32, width f32, height f32) {}
pub fn ime_activate() {}
pub fn ime_deactivate() {}
pub fn ime_is_active() bool { return false }
```

### Component 3: Extended ime_bridge_macos.h

**Purpose:** Add C declarations for overlay management
**Location:** Update existing `ime_bridge_macos.h`

**Additions:**
```c
// Overlay lifecycle
bool vglyph_ime_init_overlay(void* window);  // NSWindow*
void vglyph_ime_set_overlay_bounds(float x, float y, float width, float height);
void vglyph_ime_activate(void);
void vglyph_ime_deactivate(void);
bool vglyph_ime_is_active(void);

// Query callbacks for NSTextInputClient (called by overlay)
bool vglyph_ime_has_marked_text(void);
int vglyph_ime_marked_start(void);
int vglyph_ime_marked_length(void);
int vglyph_ime_selection_start(void);
int vglyph_ime_selection_length(void);
```

## Integration Points

### With composition.v (Existing)

No changes needed. IME overlay calls existing callbacks:
- `ime_marked_text` -> `CompositionState.set_marked_text()`
- `ime_insert_text` -> `CompositionState.commit()` + text insertion
- `ime_unmark_text` -> `CompositionState.cancel()`
- `ime_bounds` -> `CompositionState.get_composition_bounds()`

The overlay simply provides the native bridge that was missing.

### With editor_demo.v (Existing)

Minor additions for overlay lifecycle:
```v
fn init(state_ptr voidptr) {
    // ... existing init ...

    // Initialize IME overlay
    window := sapp_macos_get_window()  // sokol API
    vglyph.ime_init_overlay(window)
}

fn event(e &gg.Event, state_ptr voidptr) {
    match e.typ {
        .focus_in {
            // Activate IME when text field gains focus
            if state.text_focused {
                vglyph.ime_activate()
            }
        }
        .focus_out {
            // Deactivate IME, auto-commit if composing
            if state.composition.is_composing() {
                commit_text := state.composition.commit()
                apply_insert(mut state, commit_text)
            }
            vglyph.ime_deactivate()
        }
        // ... existing event handling ...
    }
}

fn frame(state_ptr voidptr) {
    // Update overlay bounds to match text area position
    vglyph.ime_set_overlay_bounds(50, 50, 600, 500)  // Match text area
    // ... existing rendering ...
}
```

### With existing Objective-C FFI

Uses same patterns as accessibility/objc_helpers.h:
- ARC-compatible void* bridging
- Static inline wrapper functions
- V fn C declarations map to inline C functions

### With sokol (Workaround Architecture)

**Problem:** sokol's MTKView owns Metal rendering, doesn't implement NSTextInputClient.
NSView categories don't apply to MTKView subclasses.

**Solution:** Position transparent NSView overlay above MTKView:
```
┌────────────────────────────────────────────┐
│ NSWindow                                    │
│ ┌────────────────────────────────────────┐ │
│ │ VGlyphIMEOverlayView (transparent)     │ │ <- Receives IME events
│ │ ┌────────────────────────────────────┐ │ │
│ │ │ sokol MTKView (Metal rendering)    │ │ │ <- Renders graphics
│ │ │                                    │ │ │
│ │ │  [text area with cursor]           │ │ │
│ │ │                                    │ │ │
│ │ └────────────────────────────────────┘ │ │
│ └────────────────────────────────────────┘ │
└────────────────────────────────────────────┘
```

**Key insight:** Overlay view doesn't need to cover entire window. It only needs to cover the text
editing area. When user clicks text area, overlay becomes first responder for key events. When user
clicks outside, focus returns to MTKView.

**First responder management:**
- When text field gains focus: `[overlayView.window makeFirstResponder:overlayView]`
- When text field loses focus: `[overlayView.window makeFirstResponder:mtkView]`
- Overlay passes mouse events through (hitTest returns nil for mouse events)

## State Management

### Existing State (No Changes)

**CompositionState** (composition.v) already handles:
- `phase: CompositionPhase` - none/composing
- `preedit_text: string` - current composition
- `preedit_start: int` - byte offset in document
- `cursor_offset: int` - cursor within preedit
- `clauses: []Clause` - segment info
- `selected_clause: int` - current clause index

**DeadKeyState** (composition.v) already handles:
- `pending: ?rune` - dead key waiting
- `pending_pos: int` - position where typed

### New State

**IME Overlay State** (in Objective-C static vars):
```objc
static VGlyphIMEOverlayView* g_overlay_view = nil;
static bool g_overlay_active = false;
```

**No new V state needed.** The overlay queries existing CompositionState via callbacks.

### State Synchronization

```
User types key
    │
    ├── Overlay active? ──No──> Normal key event to sokol
    │         │
    │        Yes
    │         │
    │         v
    │  [inputContext handleEvent:]
    │         │
    │    IME processes
    │         │
    │  ┌──────┴──────┐
    │  │             │
setMarkedText    insertText
    │             │
    v             v
CompositionState  CompositionState.commit()
.set_marked_text()     + insert_text()
    │             │
    v             v
Layout rebuilt    Layout rebuilt
(preedit shown)   (final text)
```

## Data Flow

### Keystroke -> IME -> Composition -> Commit -> VGlyph

```
1. User presses key (e.g., 'n' for Japanese input)
   │
   ├── VGlyphIMEOverlayView is first responder
   │
   └── keyDown: calls [[self inputContext] handleEvent:event]

2. NSTextInputContext forwards to active IME
   │
   ├── Japanese IME: 'n' → 'n' (preedit hiragana)
   │
   └── IME calls setMarkedText:selectedRange:replacementRange:

3. setMarkedText forwards to V callbacks
   │
   ├── g_marked_callback("n", cursor_pos, g_user_data)
   │
   └── V code: composition.set_marked_text("n", cursor_pos)

4. User continues typing 'i' → IME: 'ni' → 'に' (hiragana)
   │
   └── More setMarkedText calls, updating preedit

5. User presses Space to convert → '日' (kanji candidate)
   │
   ├── setMarkedText with clause info (selected clause marked)
   │
   └── V: composition.set_clauses([Clause{...}], selected: 0)

6. User confirms with Return
   │
   ├── IME calls insertText:"日"
   │
   └── g_insert_callback("日", g_user_data)

7. V code commits and inserts
   │
   ├── text := composition.commit()  // Returns "日", resets state
   │
   ├── mutation := insert_text(document, cursor, text)
   │
   └── layout := ts.layout_text(mutation.new_text, cfg)

8. Frame renders final text
```

### Candidate Window Positioning

```
IME needs position for candidate window
    │
    v
firstRectForCharacterRange:actualRange: called
    │
    v
g_bounds_callback(user_data, &x, &y, &w, &h)
    │
    v
V: composition.get_composition_bounds(layout)
    │
    ├── Returns layout-relative rect
    │
    └── (or cursor rect if no preedit yet)
    │
    v
Objective-C converts to screen coordinates:
    │
    ├── Add text area offset (where layout rendered in view)
    │
    ├── convertRect:toView:nil (view -> window)
    │
    └── convertRectToScreen: (window -> screen)
    │
    v
IME positions candidate window below/beside rect
```

### Focus Management

```
Mouse click on text area
    │
    v
Hit test: overlay covers text area?
    │
    ├──Yes──> [overlayView mouseDown:]
    │             │
    │             └── ime_activate()
    │                    │
    │                    └── [window makeFirstResponder:overlayView]
    │
    └──No──> sokol MTKView handles mouse

Mouse click outside text area
    │
    v
Hit test: outside overlay bounds
    │
    └── sokol MTKView handles mouse
           │
           └── ime_deactivate() (if was composing, auto-commit)
                   │
                   └── [window makeFirstResponder:mtkView]
```

## Build Order

### Phase 1: Overlay Infrastructure (Foundation)
**What:** Create VGlyphIMEOverlayView, basic NSTextInputClient skeleton
**Why first:** Must have native bridge before IME events can flow
**Files:**
- `ime_overlay_macos.m` (new)
- `ime_bridge_macos.h` (extend)
- `ime_manager_darwin.v` (new)
- `ime_manager_stub.v` (new)

**Verification:** Overlay appears, can become first responder

### Phase 2: Event Forwarding (Connection)
**What:** Wire overlay to existing callbacks, verify events reach V
**Why second:** Bridge is useless without event flow
**Files:**
- `ime_overlay_macos.m` (implement NSTextInputClient methods)

**Verification:** Japanese IME shows candidate window, setMarkedText reaches V

### Phase 3: Coordinate Conversion (Positioning)
**What:** Implement firstRectForCharacterRange with correct transforms
**Why third:** Candidate window must appear in correct position
**Files:**
- `ime_overlay_macos.m` (firstRectForCharacterRange)

**Verification:** Candidate window appears near cursor, not at corner

### Phase 4: Focus Management (Polish)
**What:** Handle activate/deactivate, click outside, focus loss
**Why fourth:** Must handle all edge cases for production use
**Files:**
- `ime_overlay_macos.m` (hit testing, responder chain)
- `editor_demo.v` (focus event handling)

**Verification:** Focus changes work correctly, auto-commit on focus loss

### Phase 5: CJK Testing (Validation)
**What:** Test with Japanese, Chinese, Korean IMEs
**Why last:** Need all pieces working before comprehensive testing
**Testing:**
- Japanese: Hiragana -> Kanji with clause selection
- Chinese Pinyin: Tone selection, character selection
- Korean: Hangul jamo composition

**Verification:** All three CJK input methods work correctly

## Alternative Approaches Considered

### Alternative 1: Swizzle MTKView
**Approach:** Use Objective-C runtime to add NSTextInputClient methods to MTKView at runtime
**Pros:** No new views, potentially simpler
**Cons:** Fragile (sokol may change), runtime manipulation risky
**Decision:** Rejected - too fragile, overlay is safer

### Alternative 2: Fork/Modify Sokol
**Approach:** Add NSTextInputClient conformance directly to sokol's MTKView subclass
**Pros:** Clean solution, proper integration
**Cons:** Maintenance burden, diverges from upstream sokol
**Decision:** Rejected per project requirements (no sokol modifications)

### Alternative 3: NSTextInputContext Remote Client
**Approach:** Create NSTextInputContext with remote client, not tied to view hierarchy
**Pros:** No overlay view needed
**Cons:** Still needs a NSView for inputContext, complex activation handling
**Decision:** Partially used - overlay uses this pattern internally

### Alternative 4: Replace Sokol Rendering
**Approach:** Use CAMetalLayer directly instead of MTKView
**Pros:** More control, sokol issue #727 suggests this
**Cons:** Requires significant rendering architecture changes
**Decision:** Rejected - too invasive for IME-only goal

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Overlay doesn't receive events | Medium | High | Verify responder chain, test hit testing |
| Coordinate transform incorrect | Medium | Medium | Test on multiple screen configurations |
| Focus management race conditions | Low | Medium | Serialize focus changes, debounce |
| Performance overhead from overlay | Low | Low | Overlay is transparent, minimal overhead |
| Breaks existing dead key handling | Low | High | Test dead keys with each phase |

## Dependencies

**External (no changes needed):**
- sokol: Uses sapp_macos_get_window() to get NSWindow
- gg: Unchanged, continues using sokol backend
- Pango/FreeType: Unchanged

**Internal (leveraged):**
- composition.v: CompositionState, ClauseStyle, get_composition_bounds
- ime_bridge_macos.h: Callback type definitions
- c_bindings.v: ime_register_callbacks wrapper

## Testing Strategy

### Unit Tests
- CompositionState transitions (none -> composing -> none)
- Clause rect calculation
- Coordinate conversion math

### Integration Tests
- Overlay creation and positioning
- Event forwarding to callbacks
- Focus management

### Manual Tests
- Japanese IME: Type "nihongo" -> convert to "日本語"
- Chinese Pinyin: Type "zhongwen" -> select "中文"
- Korean Hangul: Type "hangul" -> compose to "한글"
- Mixed: Start Japanese, switch to English, back to Japanese

### Regression Tests
- Dead key composition still works
- Normal character input unaffected
- Accessibility announcements still work

## Sources

**HIGH confidence (official documentation):**
- [NSTextInputClient Protocol](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [NSTextInputContext](https://developer.apple.com/documentation/appkit/nstextinputcontext)
- [MTKView](https://developer.apple.com/documentation/metalkit/mtkview)

**MEDIUM confidence (implementation references):**
- [GLFW NSTextInputClient Implementation](https://fsunuc.physics.fsu.edu/git/gwm17/glfw/commit/3107c9548d7911d9424ab589fd2ab8ca8043a84a)
- [Sokol IME Issue #595](https://github.com/floooh/sokol/issues/595)
- [Sokol MTKView Issue #727](https://github.com/floooh/sokol/issues/727)
- [jessegrosjean NSTextInputClient Reference](https://github.com/jessegrosjean/NSTextInputClient)
- [CEF IME for Off-Screen Rendering](https://www.magpcss.org/ceforum/viewtopic.php?f=8&t=10470)

**LOW confidence (patterns only, not verified):**
- [Mozilla Bug 875674](https://bugzilla.mozilla.org/show_bug.cgi?id=875674)
- [winit NSTextInputClient Issues](https://github.com/rust-windowing/winit/issues/3617)
