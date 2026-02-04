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
    // Only intercept if callbacks are registered
    if (g_marked_callback) {
        NSTextInputContext* ctx = [self inputContext];
        if (ctx) {
            unsigned short keyCode = [event keyCode];

            if (g_has_marked_text) {
                // During composition, let IME handle everything
                if ([ctx handleEvent:event]) {
                    return;
                }
            } else if (!isNavigationKey(keyCode)) {
                // Not composing, not a navigation key - might start composition
                if ([ctx handleEvent:event]) {
                    return;
                }
            }
            // Navigation keys when not composing fall through to original handler
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

        // Swizzle keyDown and insertText on sokol's view class
        // We do this after a delay to ensure sokol's class is registered
        dispatch_async(dispatch_get_main_queue(), ^{
            Class sappViewClass = NSClassFromString(@"_sapp_macos_view");
            if (sappViewClass) {
                // Swizzle keyDown to forward to IME
                Method keyDownMethod = class_getInstanceMethod(sappViewClass, @selector(keyDown:));
                if (keyDownMethod) {
                    g_original_keyDown = method_getImplementation(keyDownMethod);
                    method_setImplementation(keyDownMethod, (IMP)vglyph_keyDown);
                }

                // Swizzle insertText: to suppress during IME composition
                // sokol uses this for character input
                Method insertTextMethod = class_getInstanceMethod(sappViewClass, @selector(insertText:));
                if (insertTextMethod) {
                    g_original_insertText = method_getImplementation(insertTextMethod);
                    method_setImplementation(insertTextMethod, (IMP)vglyph_insertText);
                }
            }
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
            // Convert from top-left origin to bottom-left (macOS screen coordinates)
            NSScreen* screen = [[NSScreen screens] firstObject];
            float screen_height = screen.frame.size.height;

            // Get window position
            NSWindow* window = [self window];
            NSRect windowFrame = [window frame];

            // Convert view coordinates to screen coordinates
            // y needs to be flipped: screen_height - (windowFrame.origin.y + windowFrame.size.height - y - height)
            float screen_x = windowFrame.origin.x + x;
            float screen_y = screen_height - (windowFrame.origin.y + windowFrame.size.height - y);

            return NSMakeRect(screen_x, screen_y, width, height);
        }
    }

    // Fallback: return caret position at window center
    NSRect windowFrame = [[self window] frame];
    return NSMakeRect(windowFrame.origin.x + 100, windowFrame.origin.y + 100, 1, 20);
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    return NSNotFound;
}

@end
