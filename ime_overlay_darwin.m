// IME Overlay Implementation for macOS
// Transparent NSView that implements NSTextInputClient protocol
// Positioned as sibling above MTKView to receive IME events

#import <Cocoa/Cocoa.h>
#import "ime_overlay_darwin.h"

// VGlyphIMEOverlayView - Transparent overlay implementing NSTextInputClient
@interface VGlyphIMEOverlayView : NSView <NSTextInputClient> {
    NSRange _markedRange;
    NSRange _selectedRange;
    BOOL _didInsertText; // Set by insertText during keyDown processing
}
@property (weak, nonatomic) NSView* mtkView; // Weak reference to underlying MTKView
@property (strong, nonatomic) NSString* fieldId; // Current focused field identifier
@property (nonatomic) VGlyphIMECallbacks callbacks; // IME event callbacks
@property (strong, nonatomic) NSTextInputContext* imeContext; // Own input context
@end

@implementation VGlyphIMEOverlayView

- (instancetype)init {
    self = [super init];
    if (self) {
        _markedRange = NSMakeRange(NSNotFound, 0);
        _selectedRange = NSMakeRange(0, 0);
        memset(&_callbacks, 0, sizeof(VGlyphIMECallbacks));
    }
    return self;
}

#pragma mark - NSView Overrides

// Override inputContext — the NSView category in ime_bridge_macos.m returns nil
// when global callbacks aren't registered, which breaks per-overlay IME.
- (NSTextInputContext*)inputContext {
    if (!_imeContext) {
        _imeContext = [[NSTextInputContext alloc] initWithClient:self];
    }
    return _imeContext;
}

- (BOOL)acceptsFirstResponder {
    // Must return YES to receive IME events
    return YES;
}

- (NSView*)hitTest:(NSPoint)point {
    // Return nil to pass clicks through to MTKView underneath
    return nil;
}

#pragma mark - NSTextInputClient Required Methods (Phase 18: Stubs)

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    if (!string) return;

    _didInsertText = YES; // Signal keyDown to stop processing

    // Extract text from NSString or NSAttributedString
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string]
                     : (NSString*)string;

    if (!text) return;

    // Invoke callback with committed text
    if (_callbacks.on_insert_text) {
        _callbacks.on_insert_text([text UTF8String], _callbacks.user_data);
    }

    // Clear composition state
    [self unmarkText];
}

- (void)setMarkedText:(id)string
       selectedRange:(NSRange)selectedRange
    replacementRange:(NSRange)replacementRange {
    if (!string) return;

    // Extract text from NSString or NSAttributedString
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string]
                     : (NSString*)string;

    if (!text) return;

    // Handle replacementRange edge cases per RESEARCH.md Pitfall #1
    // If NSNotFound, use current markedRange; if that's NSNotFound, use selectedRange
    if (replacementRange.location == NSNotFound) {
        if (_markedRange.location != NSNotFound) {
            replacementRange = _markedRange;
        } else {
            replacementRange = _selectedRange;
        }
    }

    // Update state
    _markedRange = NSMakeRange(replacementRange.location, text.length);
    _selectedRange = NSMakeRange(replacementRange.location + selectedRange.location, 0);

    // Validate selectedRange.location
    NSUInteger pos = selectedRange.location;
    if (pos == NSNotFound || pos > text.length) {
        pos = text.length;
    }
    int cursor_pos = (int)pos;

    // Invoke callback with preedit text and cursor position within preedit
    if (_callbacks.on_marked_text) {
        _callbacks.on_marked_text([text UTF8String], cursor_pos,
                                  _callbacks.user_data);
    }

    // Parse underline attributes for clause segmentation
    if ([string isKindOfClass:[NSAttributedString class]]) {
        NSAttributedString* attrString = (NSAttributedString*)string;

        if (_callbacks.on_clauses_begin) {
            _callbacks.on_clauses_begin(_callbacks.user_data);
        }

        [attrString enumerateAttribute:NSUnderlineStyleAttributeName
                               inRange:NSMakeRange(0, attrString.length)
                               options:0
                            usingBlock:^(id value, NSRange range, BOOL *stop) {
            if (value && _callbacks.on_clause) {
                NSUnderlineStyle style = [value integerValue];
                // Map: NSUnderlineStyleThick = selected (2), others = raw (0)
                int clauseStyle = (style == NSUnderlineStyleThick) ? 2 : 0;
                _callbacks.on_clause((int)range.location, (int)range.length,
                                     clauseStyle, _callbacks.user_data);
            }
        }];

        if (_callbacks.on_clauses_end) {
            _callbacks.on_clauses_end(_callbacks.user_data);
        }
    }
}

- (void)unmarkText {
    // Reset composition state
    _markedRange = NSMakeRange(NSNotFound, 0);

    // Invoke callback to notify composition cancelled
    if (_callbacks.on_unmark_text) {
        _callbacks.on_unmark_text(_callbacks.user_data);
    }
}

- (NSRange)selectedRange {
    return _selectedRange;
}

- (NSRange)markedRange {
    return _markedRange;
}

- (BOOL)hasMarkedText {
    return _markedRange.location != NSNotFound;
}

- (nullable NSAttributedString*)attributedSubstringForProposedRange:(NSRange)range
                                                        actualRange:(nullable NSRangePointer)actualRange {
    // Phase 19: Extract substring from document
    // For now: return nil
    return nil;
}

- (NSArray<NSAttributedStringKey>*)validAttributesForMarkedText {
    // No special attributes needed for marked text
    return @[];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(nullable NSRangePointer)actualRange {
    // Clamp range to valid bounds (Pitfall #4)
    if (range.location == NSNotFound) {
        return NSZeroRect;
    }

    // Call V callback to get bounds in view coordinates
    if (!_callbacks.on_get_bounds) {
        return NSZeroRect;
    }

    float x, y, w, h;
    bool valid = _callbacks.on_get_bounds(_callbacks.user_data, &x, &y, &w, &h);
    if (!valid) {
        return NSZeroRect;
    }

    if (actualRange) {
        *actualRange = _markedRange.location != NSNotFound ? _markedRange : range;
    }

    // Flip Y: VGlyph top-left origin -> macOS bottom-left origin
    NSRect viewRect = NSMakeRect(x, self.bounds.size.height - y - h, w, h);

    // Transform: view -> window -> screen (handles Retina + multi-monitor automatically)
    NSRect windowRect = [self convertRect:viewRect toView:nil];
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];

    return screenRect;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    // Not needed for IME - return not found
    return NSNotFound;
}

#pragma mark - Key Forwarding (Phase 20: Korean IME support)

- (void)keyDown:(NSEvent*)event {
    NSTextInputContext* ctx = [self inputContext];
    if (ctx) {
        [ctx activate];

        _didInsertText = NO;
        [self interpretKeyEvents:@[event]];
        if ([self hasMarkedText] || _didInsertText) {
            return; // Text input system handled this key
        }
    }

    // Forward ONLY keys the text input system didn't handle
    // (navigation, function keys, etc. — NOT regular characters)
    if (self.mtkView) {
        [self.mtkView keyDown:event];
    }
}

- (void)keyUp:(NSEvent*)event {
    if (self.mtkView) {
        [self.mtkView keyUp:event];
    }
}

- (void)flagsChanged:(NSEvent*)event {
    if (self.mtkView) {
        [self.mtkView flagsChanged:event];
    }
}

- (void)doCommandBySelector:(SEL)selector {
    // Called by IME for non-character commands (arrows during composition, etc)
    // Forward to next responder for application handling
    if ([self.nextResponder respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.nextResponder performSelector:selector withObject:nil];
#pragma clang diagnostic pop
    }
}

#pragma mark - Focus Management (Phase 20: Korean IME state cleanup)

- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    if (result) {
        // Explicitly activate IME context to prevent first-character issues
        NSTextInputContext* ctx = [self inputContext];
        [ctx activate];
        // Korean IME fix: Clear any stale marked text state on focus
        [ctx discardMarkedText];
    }
    return result;
}

- (BOOL)resignFirstResponder {
    // Auto-commit any pending composition (per CONTEXT.md: focus loss = commit)
    if ([self hasMarkedText]) {
        [self unmarkText]; // Triggers insertText with preedit contents
    }

    // Critical: Clear IME state cache to prevent dead key pollution (RESEARCH.md Pitfall #2)
    [[self inputContext] invalidateCharacterCoordinates];

    return [super resignFirstResponder];
}

- (void)cancelOperation:(id)sender {
    // Called when user presses Escape
    if ([self hasMarkedText]) {
        // Cancel composition without committing
        [self unmarkText];
        return;
    }

    // Not composing: forward to next responder
    if ([self.nextResponder respondsToSelector:@selector(cancelOperation:)]) {
        [self.nextResponder cancelOperation:sender];
    }
}

@end

#pragma mark - MTKView Discovery Helper

// Recursive helper to find view by class name in view hierarchy
static NSView* findViewByClass(NSView* root, NSString* className, int depth) {
    if (!root) {
        return nil;
    }

    // Depth limit sanity check (real hierarchy is 2-3 levels)
    if (depth > 100) {
        return nil;
    }

    // Check if root matches (isKindOfClass handles subclasses like _sapp_macos_view)
    Class targetClass = NSClassFromString(className);
    if (targetClass && [root isKindOfClass:targetClass]) {
        return root;
    }

    // Recurse into subviews
    for (NSView* subview in root.subviews) {
        NSView* found = findViewByClass(subview, className, depth + 1);
        if (found) {
            return found;
        }
    }

    return nil;
}

void* vglyph_discover_mtkview_from_window(void* ns_window) {
    if (!ns_window) {
        return NULL;
    }

    NSWindow* window = (__bridge NSWindow*)ns_window;
    NSView* contentView = window.contentView;

    if (!contentView) {
        return NULL;
    }

    NSView* mtkView = findViewByClass(contentView, @"MTKView", 0);

    if (!mtkView) {
        fprintf(stderr, "vglyph: MTKView not found in window view hierarchy\n");
        return NULL;
    }

    return (__bridge void*)mtkView;
}

VGlyphOverlayHandle vglyph_create_ime_overlay_auto(void* ns_window) {
    void* mtkView = vglyph_discover_mtkview_from_window(ns_window);

    if (!mtkView) {
        return NULL; // Hard error per CONTEXT.md - no silent fallback
    }

    return vglyph_create_ime_overlay(mtkView);
}

#pragma mark - C API Implementation

VGlyphOverlayHandle vglyph_create_ime_overlay(void* mtk_view) {
    if (!mtk_view) {
        return NULL;
    }

    // Cast MTKView from void*
    NSView* mtkView = (__bridge NSView*)mtk_view;
    NSView* parent = mtkView.superview;

    if (!parent) {
        return NULL; // MTKView has no parent
    }

    // Create overlay
    VGlyphIMEOverlayView* overlay = [[VGlyphIMEOverlayView alloc] init];
    overlay.mtkView = mtkView; // Store weak reference for returning focus
    overlay.wantsLayer = YES; // Required for transparency
    overlay.layer.backgroundColor = [[NSColor clearColor] CGColor];

    // Add as sibling above MTKView
    [parent addSubview:overlay positioned:NSWindowAbove relativeTo:mtkView];

    // Set up Auto Layout constraints to match MTKView bounds
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:mtkView.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:mtkView.trailingAnchor],
        [overlay.topAnchor constraintEqualToAnchor:mtkView.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:mtkView.bottomAnchor]
    ]];

    // Return handle (transfer ownership to caller)
    return (__bridge_retained void*)overlay;
}

void vglyph_set_focused_field(VGlyphOverlayHandle handle, const char* field_id) {
    if (!handle) {
        return;
    }

    VGlyphIMEOverlayView* overlay = (__bridge VGlyphIMEOverlayView*)handle;

    if (field_id != NULL) {
        // Focus: Make overlay first responder
        // Defer to next run loop — may be called during render callback
        overlay.fieldId = [NSString stringWithUTF8String:field_id];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[overlay window] makeFirstResponder:overlay];
        });
    } else {
        // Blur: commit and clean state
        if ([overlay hasMarkedText]) {
            [overlay unmarkText];
        }
        [[overlay inputContext] invalidateCharacterCoordinates];
        overlay.fieldId = nil;
        if (overlay.mtkView) {
            [[overlay window] makeFirstResponder:overlay.mtkView];
        }
    }
}

void vglyph_overlay_free(VGlyphOverlayHandle handle) {
    if (!handle) {
        return;
    }

    // Transfer ownership and release
    VGlyphIMEOverlayView* overlay = (__bridge_transfer VGlyphIMEOverlayView*)handle;

    // Force-cancel any active IME composition (CONTEXT.md: no cross-handler routing)
    if ([overlay hasMarkedText]) {
        // Discard composition without routing to global callbacks
        [overlay unmarkText];
    }
    // Resign first responder if this overlay had it
    if ([[overlay window] firstResponder] == overlay) {
        [[overlay window] makeFirstResponder:overlay.mtkView];
    }

    [overlay removeFromSuperview];
    // ARC will deallocate overlay after this scope
}

void vglyph_overlay_register_callbacks(VGlyphOverlayHandle handle, VGlyphIMECallbacks callbacks) {
    if (!handle) {
        return;
    }

    VGlyphIMEOverlayView* overlay = (__bridge VGlyphIMEOverlayView*)handle;
    overlay.callbacks = callbacks;
}
