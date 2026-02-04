// IME Overlay Implementation for macOS
// Transparent NSView that implements NSTextInputClient protocol
// Positioned as sibling above MTKView to receive IME events

#import <Cocoa/Cocoa.h>
#import "ime_overlay_darwin.h"

// VGlyphIMEOverlayView - Transparent overlay implementing NSTextInputClient
@interface VGlyphIMEOverlayView : NSView <NSTextInputClient> {
    NSRange _markedRange;
    NSRange _selectedRange;
}
@property (weak, nonatomic) NSView* mtkView; // Weak reference to underlying MTKView
@property (strong, nonatomic) NSString* fieldId; // Current focused field identifier
@property (nonatomic) VGlyphIMECallbacks callbacks; // IME event callbacks
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
    // Extract text from NSString or NSAttributedString
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string]
                     : (NSString*)string;

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
    // Extract text from NSString or NSAttributedString
    NSString* text = [string isKindOfClass:[NSAttributedString class]]
                     ? [(NSAttributedString*)string string]
                     : (NSString*)string;

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

    // Invoke callback with preedit text and cursor position within preedit
    if (_callbacks.on_marked_text) {
        _callbacks.on_marked_text([text UTF8String], (int)selectedRange.location,
                                  _callbacks.user_data);
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
    // Phase 19: Return composition bounds for candidate window
    // For now: return zero rect
    return NSZeroRect;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    // Not needed for IME - return not found
    return NSNotFound;
}

@end

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
        overlay.fieldId = [NSString stringWithUTF8String:field_id];
        [[overlay window] makeFirstResponder:overlay];
    } else {
        // Blur: Return first responder to MTKView
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
