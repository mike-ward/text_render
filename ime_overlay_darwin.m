// IME Overlay Implementation for macOS
// Transparent NSView that implements NSTextInputClient protocol
// Positioned as sibling above MTKView to receive IME events

#import <Cocoa/Cocoa.h>
#import "ime_overlay_darwin.h"

// VGlyphIMEOverlayView - Transparent overlay implementing NSTextInputClient
@interface VGlyphIMEOverlayView : NSView <NSTextInputClient>
@property (weak, nonatomic) NSView* mtkView; // Weak reference to underlying MTKView
@property (strong, nonatomic) NSString* fieldId; // Current focused field identifier
@end

@implementation VGlyphIMEOverlayView

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
    // Phase 19: Forward to composition state
    // For now: stub (no-op)
}

- (void)setMarkedText:(id)string
       selectedRange:(NSRange)selectedRange
    replacementRange:(NSRange)replacementRange {
    // Phase 19: Update preedit composition
    // For now: stub (no-op)
}

- (void)unmarkText {
    // Phase 19: Cancel composition
    // For now: stub (no-op)
}

- (NSRange)selectedRange {
    // Phase 19: Query document selection
    // For now: return empty range
    return NSMakeRange(NSNotFound, 0);
}

- (NSRange)markedRange {
    // Phase 19: Query composition range
    // For now: return no marked text
    return NSMakeRange(NSNotFound, 0);
}

- (BOOL)hasMarkedText {
    // Phase 19: Query composition state
    // For now: return NO (not composing)
    return NO;
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
