// IME Bridge for macOS
// Implements NSTextInputClient protocol on sokol's NSView to receive IME events
// and forward them to VGlyph composition state via callbacks.
//
// BUILD INTEGRATION:
// To link this Objective-C file into V applications:
// 1. Add to V source: #flag darwin ime_bridge_macos.m
// 2. Or compile manually: clang -c -fobjc-arc ime_bridge_macos.m -o ime_bridge_macos.o
// 3. Link during V build: v -cflags "-framework Cocoa" your_app.v ime_bridge_macos.o
//
// The native bridge is initialized by calling vglyph_ime_register_callbacks() from V.

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

// Forward declarations for V callback types
typedef void (*IMEMarkedTextCallback)(const char* text, int cursor_pos, void* user_data);
typedef void (*IMEInsertTextCallback)(const char* text, void* user_data);
typedef void (*IMEUnmarkTextCallback)(void* user_data);
typedef bool (*IMEBoundsCallback)(void* user_data, float* x, float* y, float* width, float* height);

// Global callback state
static IMEMarkedTextCallback g_marked_callback = NULL;
static IMEInsertTextCallback g_insert_callback = NULL;
static IMEUnmarkTextCallback g_unmark_callback = NULL;
static IMEBoundsCallback g_bounds_callback = NULL;
static void* g_user_data = NULL;

// Track marked text state for hasMarkedText
static BOOL g_has_marked_text = NO;
static NSRange g_marked_range = {NSNotFound, 0};

// Input context for IME - created on demand
static NSTextInputContext* g_input_context = nil;

// Flag to suppress char events after IME handles input
static BOOL g_ime_handled_key = NO;

// Forward declaration for lazy swizzling
static void ensureSwizzling(void);

// Register callbacks from V code
void vglyph_ime_register_callbacks(IMEMarkedTextCallback marked,
                                   IMEInsertTextCallback insert,
                                   IMEUnmarkTextCallback unmark,
                                   IMEBoundsCallback bounds,
                                   void* user_data) {
    g_marked_callback = marked;
    g_insert_callback = insert;
    g_unmark_callback = unmark;
    g_bounds_callback = bounds;
    g_user_data = user_data;

    // Swizzle sokol's keyDown immediately when callbacks are registered.
    ensureSwizzling();
}

// Check if IME handled the last key event (and clear the flag)
bool vglyph_ime_did_handle_key(void) {
    bool result = g_ime_handled_key;
    g_ime_handled_key = NO;
    return result;
}

// Check if IME has active marked text (composition in progress)
bool vglyph_ime_has_marked_text(void) {
    return g_has_marked_text;
}

// Category to add NSTextInputClient protocol to sokol's NSView
// Sokol creates its view dynamically, so we add IME support via category.
// We add protocol conformance at runtime via +load so IME system recognizes the view.
@interface NSView (VGlyphIME) <NSTextInputClient>
@end

@implementation NSView (VGlyphIME)

// Original keyDown implementation (set by swizzling)
static IMP g_original_keyDown = NULL;
// Original insertText implementation (set by swizzling)
static IMP g_original_insertText = NULL;

// Check if keyCode is a navigation/function key (not character input)
static BOOL isNavigationKey(unsigned short keyCode) {
    // Arrow keys: 123=left, 124=right, 125=down, 126=up
    // Function keys, Home, End, Page Up/Down, etc.
    switch (keyCode) {
        case 123: case 124: case 125: case 126: // Arrow keys
        case 115: case 119: case 116: case 121: // Home, End, Page Up, Page Down
        case 51:  // Delete (backward/backspace)
        case 117: // Delete (forward)
        case 36:  // Return
        case 76:  // Enter (numpad)
        case 48:  // Tab
        case 122: case 120: case 99: case 118:  // F1-F4
        case 96: case 97: case 98: case 100:    // F5-F8
        case 101: case 109: case 103: case 111: // F9-F12
        case 53:  // Escape
            return YES;
        default:
            return NO;
    }
}

// Swizzled keyDown that forwards to input context for IME
static void vglyph_keyDown(id self, SEL _cmd, NSEvent* event) {
    unsigned short keyCode = [event keyCode];

    // When NOT composing, navigation keys go directly to sokol
    if (!g_has_marked_text && isNavigationKey(keyCode)) {
        if (g_original_keyDown) {
            ((void (*)(id, SEL, NSEvent*))g_original_keyDown)(self, _cmd, event);
        }
        return;
    }

    // During composition OR for non-navigation keys, try IME via interpretKeyEvents
    // This is the standard NSResponder approach and may handle edge cases better
    if (g_marked_callback) {
        g_ime_handled_key = NO;  // Reset flag before processing

        // Ensure input context exists and is active
        // Korean IME fix: Also call discardMarkedText to clear any stale state
        // This may help initialize Korean IME's internal state on first keypress
        NSTextInputContext* ctx = [self inputContext];
        if (ctx) {
            [ctx activate];
            // Clear any stale marked text state - may help Korean IME initialization
            if (!g_has_marked_text) {
                [ctx discardMarkedText];
            }
        }

        // Korean IME fix attempt: Try handleEvent directly first
        // Some apps report success calling handleEvent before interpretKeyEvents
        // handleEvent may initialize Korean IME state that interpretKeyEvents doesn't
        if ([ctx handleEvent:event]) {
            if (g_ime_handled_key) {
                return;  // IME handled the key via handleEvent
            }
        }

        // Fall back to interpretKeyEvents - the standard NSResponder approach
        // This may handle edge cases that handleEvent doesn't
        [(NSView*)self interpretKeyEvents:@[event]];

        if (g_ime_handled_key) {
            return;  // IME called setMarkedText or insertText
        }
    }

    // Fall through to original handler
    if (g_original_keyDown) {
        ((void (*)(id, SEL, NSEvent*))g_original_keyDown)(self, _cmd, event);
    }
}

// Swizzled insertText (old NSResponder method) - suppress during IME composition
static void vglyph_insertText(id self, SEL _cmd, id string) {
    // Suppress if IME has marked text (composition in progress)
    if (g_has_marked_text) {
        return;
    }
    // Fall through to original handler
    if (g_original_insertText) {
        ((void (*)(id, SEL, id))g_original_insertText)(self, _cmd, string);
    }
}

// Flag to track if swizzling has been done
static BOOL g_swizzling_done = NO;

// Perform swizzling of sokol's view class (called lazily on first IME use)
static void ensureSwizzling(void) {
    if (g_swizzling_done) return;
    g_swizzling_done = YES;

    Class sappViewClass = NSClassFromString(@"_sapp_macos_view");
    if (sappViewClass) {
        // Swizzle keyDown to forward to IME
        Method keyDownMethod = class_getInstanceMethod(sappViewClass, @selector(keyDown:));
        if (keyDownMethod) {
            g_original_keyDown = method_getImplementation(keyDownMethod);
            method_setImplementation(keyDownMethod, (IMP)vglyph_keyDown);
        }

        // Swizzle insertText: to suppress during IME composition
        Method insertTextMethod = class_getInstanceMethod(sappViewClass, @selector(insertText:));
        if (insertTextMethod) {
            g_original_insertText = method_getImplementation(insertTextMethod);
            method_setImplementation(insertTextMethod, (IMP)vglyph_insertText);
        }
    }
}

+ (void)load {
    // Add NSTextInputClient protocol conformance to NSView at runtime.
    // This is required because macOS IME checks conformsToProtocol:, not just respondsToSelector:.
    // The category provides method implementations; this adds the formal conformance.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Add to NSView
        Class viewClass = [NSView class];
        Protocol *protocol = @protocol(NSTextInputClient);
        if (!class_conformsToProtocol(viewClass, protocol)) {
            class_addProtocol(viewClass, protocol);
        }

        // Also add to MTKView if available (sokol uses Metal on macOS)
        Class mtkViewClass = NSClassFromString(@"MTKView");
        if (mtkViewClass && !class_conformsToProtocol(mtkViewClass, protocol)) {
            class_addProtocol(mtkViewClass, protocol);
        }

        // Note: Swizzling is done lazily in ensureSwizzling() when inputContext is first accessed.
        // This ensures sokol's view class exists before we try to swizzle it.

        // Pre-warm Korean IME by creating a dummy NSTextInputContext on main queue.
        // Korean IME (unlike Japanese/Chinese) appears to require the input context to exist
        // before first keypress. This may initialize internal Korean IME state.
        // Reported bug: Qt QTBUG-136128, Apple FB17460926, Alacritty #6942
        dispatch_async(dispatch_get_main_queue(), ^{
            // Create a temporary view that conforms to NSTextInputClient
            NSView* dummyView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
            // Create and activate an input context to warm up the IME subsystem
            NSTextInputContext* ctx = [[NSTextInputContext alloc] initWithClient:(id<NSTextInputClient>)dummyView];
            [ctx activate];
            // Deactivate after a brief moment to allow IME initialization
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [ctx deactivate];
                // Note: dummyView and ctx will be released by ARC after this block
            });
        });
    });
}

#pragma mark - Input Context

// Override inputContext to provide a valid NSTextInputContext for IME
- (NSTextInputContext *)inputContext {
    // Only create input context if callbacks are registered (i.e., this is the vglyph view)
    if (!g_marked_callback) {
        return nil;
    }

    // Ensure swizzling is done before first IME use
    ensureSwizzling();

    if (!g_input_context) {
        g_input_context = [[NSTextInputContext alloc] initWithClient:(id<NSTextInputClient>)self];
    }
    return g_input_context;
}

#pragma mark - NSTextInputClient Required Methods

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string]
                     : (NSString*)string;

    // Mark that IME handled this key (suppress char event)
    g_ime_handled_key = YES;

    // Clear marked state - composition ends on insert
    g_has_marked_text = NO;
    g_marked_range = NSMakeRange(NSNotFound, 0);

    if (g_insert_callback) {
        g_insert_callback([text UTF8String], g_user_data);
    }
}

- (void)setMarkedText:(id)string
       selectedRange:(NSRange)selectedRange
    replacementRange:(NSRange)replacementRange {
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string]
                     : (NSString*)string;

    // Mark that IME handled this key (suppress char event)
    g_ime_handled_key = YES;

    // Track marked text state
    if (text.length > 0) {
        g_has_marked_text = YES;
        g_marked_range = NSMakeRange(0, text.length);
    } else {
        g_has_marked_text = NO;
        g_marked_range = NSMakeRange(NSNotFound, 0);
    }

    // selectedRange.location is cursor position within preedit
    int cursor_pos = (int)selectedRange.location;

    if (g_marked_callback) {
        g_marked_callback([text UTF8String], cursor_pos, g_user_data);
    }
}

- (void)unmarkText {
    g_has_marked_text = NO;
    g_marked_range = NSMakeRange(NSNotFound, 0);
    if (g_unmark_callback) {
        g_unmark_callback(g_user_data);
    }
}

- (void)doCommandBySelector:(SEL)selector {
    // Required NSTextInputClient method - called for non-text commands during IME
    // Forward to next responder (sokol's original handling)
    NSResponder* next = [(NSView*)self nextResponder];
    if ([next respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [next performSelector:selector withObject:nil];
#pragma clang diagnostic pop
    }
}

- (NSRange)selectedRange {
    // Not tracking selection ranges in V yet - return empty
    return NSMakeRange(NSNotFound, 0);
}

- (NSRange)markedRange {
    return g_marked_range;
}

- (BOOL)hasMarkedText {
    return g_has_marked_text;
}

- (nullable NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
                                                         actualRange:(nullable NSRangePointer)actualRange {
    // Would need to extract substring from document
    return nil;
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
    return @[];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange {
    // Query V for composition bounds
    if (g_bounds_callback) {
        float x = 0, y = 0, width = 0, height = 0;
        if (g_bounds_callback(g_user_data, &x, &y, &width, &height)) {
            // Flip Y: VGlyph top-left origin -> macOS bottom-left origin
            NSRect viewRect = NSMakeRect(x, self.bounds.size.height - y - height, width, height);

            // Transform: view -> window -> screen (handles Retina + multi-monitor automatically)
            NSRect windowRect = [self convertRect:viewRect toView:nil];
            NSRect screenRect = [[self window] convertRectToScreen:windowRect];

            return screenRect;
        }
    }

    // Fallback: return zero rect (IME will use default position)
    return NSZeroRect;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    return NSNotFound;
}

@end
