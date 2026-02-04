# Phase 21: Multi-Display & Polish - Research

**Researched:** 2026-02-04
**Domain:** Multi-monitor coordinate systems and Retina display scaling for IME
**Confidence:** MEDIUM

## Summary

Multi-display IME coordinate handling requires proper screen detection and Retina scale transforms.
macOS merges display coordinate spaces with the menu bar screen as origin (0,0). NSWindow.screen
property identifies which monitor contains the window. firstRectForCharacterRange must return
coordinates in global screen space (not view/window local). Retina displays use 2x backing scale
factor but NSWindow.convertRectToScreen handles this automatically. Current ime_bridge_macos.m
has bug: uses [[NSScreen screens] firstObject] (primary screen) instead of [[self window] screen]
(window's actual screen), causing candidate windows to jump to primary monitor.

**Primary recommendation:** Replace [[NSScreen screens] firstObject] with [[self window] screen]
in firstRectForCharacterRange, use convertRectToScreen (handles Retina automatically), test
spanning monitors (use window's majority screen).

**Key finding:** Korean IME first-keypress issue appears system-level, reported across Qt, Godot,
Alacritty (Apple FB17460926). No known fix via NSTextInputClient implementation. Godot fixed
separate issue (insertText+setMarkedText simultaneous call corruption) but first-keypress remains.
May require workaround (e.g., pre-warm IME context on app launch) rather than protocol fix.

## Standard Stack

### Core APIs
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| NSWindow.screen | macOS 10.0+ | Determine window's monitor | Only API for screen detection |
| NSWindow.convertRectToScreen | macOS 10.7+ | Transform to global coords | Handles Retina automatically |
| NSScreen.frame | macOS 10.0+ | Screen coordinate bounds | Global coordinate space definition |
| NSWindow.backingScaleFactor | macOS 10.7+ | Retina scale query | Per-window scale (not global) |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| NSScreen.screens | List all monitors | Debugging, config UI (not coordinate calc) |
| NSScreen.backingScaleFactor | Per-screen Retina scale | Only if not using convertRectToScreen |
| NSView.convertRect:toView:nil | View to window transform | First step before convertRectToScreen |

**Installation:** Built into macOS SDK, no dependencies.

**Note:** convertRectToScreen introduced macOS 10.7 (2011), handles Retina scaling internally.
Don't manually multiply by backingScaleFactor.

## Architecture Patterns

### Recommended Coordinate Flow
```
VGlyph layout (UTF-8 byte offset)
  → pango_layout_index_to_pos() → Pango rect (pixels, top-left origin)
  → Add text field offset → View coords (pixels, top-left origin)
  → Flip Y: bounds.height - y - h → View coords (macOS bottom-left)
  → convertRect:toView:nil → Window coords (points, bottom-left)
  → convertRectToScreen: → Screen coords (points, bottom-left, Retina-aware)
```

### Pattern 1: Screen Detection for Window
**What:** Determine which monitor contains the window for correct coordinate space.

**When to use:** Every firstRectForCharacterRange call.

**Example:**
```objc
// Source: Official pattern from NSWindow documentation
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    // Get VGlyph rect (implementation omitted)
    NSRect viewRect = /* from layout */;

    // Transform view → window → screen
    NSRect windowRect = [self convertRect:viewRect toView:nil];
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];

    // screenRect is now in global screen space on correct monitor
    // IME will position candidate window relative to this rect
    return screenRect;
}
```

**Critical:** convertRectToScreen uses window's current screen automatically. No manual screen
detection needed.

### Pattern 2: Retina Scale Handling
**What:** Handle 2x pixel density on Retina displays transparently.

**Approach:** Use convertRectToScreen (automatic) not manual backingScaleFactor multiplication.

**When to use:** All coordinate transforms.

**Example (CORRECT):**
```objc
// Source: Apple High Resolution APIs documentation
NSRect viewRect = NSMakeRect(100, 100, 50, 20); // Points
NSRect windowRect = [self convertRect:viewRect toView:nil];
NSRect screenRect = [[self window] convertRectToScreen:windowRect];
// screenRect is in screen points (1 point = 2 pixels on Retina)
// IME system handles backing scale internally
return screenRect;
```

**Example (INCORRECT — don't do this):**
```objc
// DON'T manually scale
float scale = [[self window] backingScaleFactor]; // 2.0 on Retina
NSRect viewRect = NSMakeRect(100 * scale, 100 * scale, 50 * scale, 20 * scale);
// convertRectToScreen will DOUBLE-SCALE, wrong position
```

**Why:** convertRectToScreen operates on points (logical units), not pixels. Retina backing store
mapping happens at render time, coordinate APIs work in points.

### Pattern 3: Window Spanning Multiple Monitors
**What:** Handle window straddling two displays.

**macOS behavior:** NSWindow.screen returns the screen containing majority of window. Candidate
window appears on same screen (natural for user).

**When to use:** All multi-monitor scenarios (automatic via NSWindow.screen).

**Example:**
```objc
// No special handling needed — NSWindow.screen handles spanning
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    NSRect viewRect = /* get from layout */;
    NSRect windowRect = [self convertRect:viewRect toView:nil];
    // convertRectToScreen queries [[self window] screen] internally
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];
    return screenRect; // Correct screen even if window spans monitors
}
```

**Fallback edge case:** If window is offscreen or minimized, [[self window] screen] may be nil.
Return NSZeroRect (IME will use default position).

### Pattern 4: Monitor Hot-Plug During Composition
**What:** Handle external monitor disconnect mid-composition.

**macOS behavior:** Window auto-migrates to remaining screen. NSWindow.screen updates
automatically. NSTextInputContext calls invalidateCharacterCoordinates, then
firstRectForCharacterRange again.

**When to use:** No special handling needed (system manages).

**Example:**
```objc
// System handles hot-plug automatically
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    // Query fresh screen on every call (not cached)
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];
    // If monitor disconnected, window.screen updated by system
    return screenRect;
}
```

**Don't cache:** Never cache NSWindow.screen or NSScreen.frame — query at call time. System
sends invalidateCharacterCoordinates after screen changes.

### Anti-Patterns to Avoid
- **Using [[NSScreen screens] firstObject]:** Returns primary screen (menu bar), not window's
  screen (current ime_bridge_macos.m bug)
- **Manual backingScaleFactor multiplication:** convertRectToScreen handles Retina
- **Caching NSWindow.screen:** Screen changes on window drag, hot-plug
- **Using NSScreen.mainScreen:** Main = keyboard focus, not window location

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Screen coordinate conversion | Manual frame arithmetic | convertRectToScreen | Handles Retina, multi-monitor, coordinate flipping |
| Retina pixel scaling | Multiply by backingScaleFactor | Use points (not pixels) | APIs work in points, render pipeline handles pixels |
| Screen detection | Frame intersection tests | NSWindow.screen property | System tracks spanning, updates on drag |
| Coordinate caching | Cache screen rects | Query per-call | invalidateCharacterCoordinates signals recalc |
| Edge-of-screen clamping | Manual bounds checking | Return raw rect | IME system clamps candidate window |

**Key insight:** macOS coordinate APIs are resolution-independent (work in points). Backing store
(pixels) is render-time concern, not coordinate-time. Using points throughout prevents Retina
bugs.

## Common Pitfalls

### Pitfall 1: Candidate Window Jumps to Primary Monitor
**What goes wrong:** Window on external monitor, type CJK, candidate window appears on MacBook
screen (primary) not external monitor.

**Why it happens:** Using [[NSScreen screens] firstObject] instead of [[self window] screen].
firstObject is primary screen (menu bar), not window's actual screen.

**How to avoid:**
```objc
// WRONG (current ime_bridge_macos.m):
NSScreen* screen = [[NSScreen screens] firstObject]; // Always primary
float screen_height = screen.frame.size.height;
// Manual coordinate math using wrong screen...

// CORRECT:
NSRect viewRect = NSMakeRect(x, bounds.height - y - h, w, h);
NSRect windowRect = [self convertRect:viewRect toView:nil];
NSRect screenRect = [[self window] convertRectToScreen:windowRect];
return screenRect; // Automatic screen detection
```

**Warning signs:** IME candidate window on wrong monitor, coordinate offset by screen width.

**Sources:** Common multi-monitor bug pattern, [R0uter's Blog on multi-monitor
positioning](https://www.logcg.com/en/archives/2771.html)

### Pitfall 2: Double-Scaling on Retina Displays
**What goes wrong:** Candidate window appears 2x farther from cursor than expected on Retina.

**Why it happens:** Manually multiplying by backingScaleFactor (2.0) then passing to
convertRectToScreen which expects points (already logical units).

**How to avoid:**
```objc
// Get rect in pixels from VGlyph layout
float x, y, w, h;
vglyph_get_cursor_rect(&x, &y, &w, &h); // Pixels

// Convert to view points (if needed)
NSRect viewRect = NSMakeRect(x, y, w, h);

// DON'T do this:
float scale = [[self window] backingScaleFactor];
viewRect.origin.x *= scale; // WRONG

// DO transform directly:
NSRect windowRect = [self convertRect:viewRect toView:nil];
NSRect screenRect = [[self window] convertRectToScreen:windowRect];
return screenRect; // Correct on Retina and non-Retina
```

**Warning signs:** Candidate window far from cursor on Retina, correct on non-Retina.

**Sources:** [Apple High Resolution APIs
docs](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/APIs/APIs.html)

### Pitfall 3: Coordinate Stale After Window Drag
**What goes wrong:** Drag window to different monitor, type CJK, candidate appears at old
position (wrong screen).

**Why it happens:** Caching screen bounds or NSWindow.screen. System expects fresh query on each
firstRectForCharacterRange call.

**How to avoid:**
```objc
// DON'T cache:
static NSScreen* cached_screen = nil; // WRONG
if (!cached_screen) cached_screen = [[self window] screen];

// DO query per-call:
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    // Fresh query every time
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];
    return screenRect;
}
```

**Why it's okay:** convertRectToScreen is lightweight (no rendering), query cost negligible.

**Warning signs:** Candidate window at wrong position after window drag between monitors.

**Sources:** NSTextInputClient protocol contract (expects per-call position)

### Pitfall 4: Y-Axis Confusion (Top-Left vs Bottom-Left)
**What goes wrong:** Candidate window appears vertically flipped (above cursor instead of below).

**Why it happens:** macOS uses bottom-left origin for screen/window coords, but VGlyph/Pango use
top-left. Forgetting to flip Y before convertRect.

**How to avoid:**
```objc
// VGlyph gives rect with top-left origin
float x, y, w, h;
vglyph_get_cursor_rect(&x, &y, &w, &h); // y=0 at top

// Flip Y for macOS view coordinate system
NSRect viewRect = NSMakeRect(x, self.bounds.size.height - y - h, w, h);
// Now y=0 at bottom (macOS convention)

// Transform to screen
NSRect windowRect = [self convertRect:viewRect toView:nil];
NSRect screenRect = [[self window] convertRectToScreen:windowRect];
return screenRect;
```

**Warning signs:** Candidate window above cursor, inverted vertical position.

**Sources:** [Apple Coordinate System
docs](https://developer.apple.com/library/archive/documentation/General/Devpedia-CocoaApp-MOSX/CoordinateSystem.html),
Phase 19 RESEARCH.md

### Pitfall 5: Edge-of-Screen Candidate Window Clipping
**What goes wrong:** Cursor near screen edge, candidate window clips offscreen or appears
truncated.

**Why it happens:** Assuming app must clamp coordinates to screen bounds. IME system handles
clamping.

**How to avoid:**
```objc
// Return raw rect (DON'T clamp):
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];

    // DON'T do this:
    // NSRect screenBounds = [[self window] screen].frame;
    // screenRect = NSIntersectionRect(screenRect, screenBounds); // WRONG

    // DO return raw:
    return screenRect; // IME clamps candidate window automatically
}
```

**Why:** IME knows candidate window size (app doesn't). IME repositions candidate to fit screen.

**Warning signs:** Candidate window at wrong position near edges, shifted when shouldn't be.

**Sources:** NSTextInputClient protocol design (separation of concerns)

## Code Examples

### Correct Multi-Monitor firstRectForCharacterRange
```objc
// Source: Based on Apple NSWindow.convertRectToScreen documentation + Phase 19 implementation
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    // Clamp range to document (Pitfall from Phase 19)
    if (range.location == NSNotFound) {
        return NSZeroRect;
    }

    // Get cursor rect from V callback
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

    // Flip Y: VGlyph top-left → macOS bottom-left
    NSRect viewRect = NSMakeRect(x, self.bounds.size.height - y - h, w, h);

    // Transform: view → window → screen (automatic screen detection + Retina handling)
    NSRect windowRect = [self convertRect:viewRect toView:nil];
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];

    return screenRect; // Correct screen, correct scale, no caching
}
```

### Debugging Multi-Monitor Issues
```objc
// Source: Recommended debugging approach
- (NSRect)firstRectForCharacterRange:(NSRange)range
                         actualRange:(NSRangePointer)actualRange {
    float x, y, w, h;
    _callbacks.on_get_bounds(_callbacks.user_data, &x, &y, &w, &h);

    NSRect viewRect = NSMakeRect(x, self.bounds.size.height - y - h, w, h);
    NSRect windowRect = [self convertRect:viewRect toView:nil];
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];

    // Debugging: log screen info
    NSScreen* windowScreen = [[self window] screen];
    NSScreen* primaryScreen = [[NSScreen screens] firstObject];
    NSLog(@"Window on screen: %@ (primary: %@)",
          NSStringFromRect(windowScreen.frame),
          NSStringFromRect(primaryScreen.frame));
    NSLog(@"Cursor rect: view=%@ window=%@ screen=%@",
          NSStringFromRect(viewRect),
          NSStringFromRect(windowRect),
          NSStringFromRect(screenRect));

    return screenRect;
}
```

### Monitor Hot-Plug Handling (Automatic)
```objc
// Source: macOS system behavior (no special code needed)
// System flow:
// 1. User types CJK, IME calls firstRectForCharacterRange → returns screen A coords
// 2. User unplugs monitor A mid-composition
// 3. Window migrates to monitor B (system automatic)
// 4. System calls invalidateCharacterCoordinates
// 5. IME calls firstRectForCharacterRange again → returns screen B coords
// 6. Candidate window repositions to screen B

// Implementation: Just handle invalidateCharacterCoordinates
// (already implemented in ime_overlay_darwin.m resignFirstResponder)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual screen detection | NSWindow.screen property | macOS 10.0 | System tracks spanning |
| Manual Retina scaling | convertRectToScreen | macOS 10.7 (2011) | Automatic backing scale |
| convertBaseToScreen: | convertRectToScreen: | macOS 10.7 | New method supports Retina |
| NSScreen.mainScreen | NSWindow.screen | Always | Main = focus, not location |
| Pre-cache screen bounds | Query per-call | N/A (protocol design) | Supports dynamic changes |

**Deprecated/outdated:**
- convertBaseToScreen: and convertScreenToBase: — Use convertRectToScreen/convertRectFromScreen
- Manual backingScaleFactor multiplication — APIs work in points, not pixels
- [[NSScreen screens] firstObject] for coordinate calcs — Use [[self window] screen]

## Open Questions

### Q1: Window Minimized During Composition
**What we know:** [[self window] screen] may be nil when minimized.

**What's unclear:** Should firstRectForCharacterRange return NSZeroRect or fallback position?

**Recommendation:** Return NSZeroRect. IME will use default position (screen center). Edge case
(typing while minimizing), not worth special handling. Mark LOW confidence.

### Q2: Window on Disconnected Screen Edge Case
**What we know:** Hot-plug triggers invalidateCharacterCoordinates. But what if hot-plug happens
between invalidate and firstRectForCharacterRange call?

**What's unclear:** Race condition handling?

**Recommendation:** Trust NSWindow.screen (updated synchronously on main thread). No race if IME
calls on main thread (protocol requirement). Mark MEDIUM confidence.

### Q3: Coordinate Logging Level
**What we know:** Multi-monitor bugs hard to reproduce without logging.

**What's unclear:** Should coordinate logging be always-on, debug-only, or disabled?

**Recommendation:** Debug-only (compile-time flag or env var). Verbose logs in production
annoying. Mark HIGH confidence.

### Q4: Mixed DPI Setup (4K + 1080p)
**What we know:** macOS uses integer scale factors (1x, 2x). 4K display may be 2x, 1080p is 1x.

**What's unclear:** Does convertRectToScreen handle transition correctly?

**Recommendation:** Yes, convertRectToScreen per-window aware. When dragging window between
screens, scale factor updates automatically. No special handling. Mark HIGH confidence (backed by
Apple docs).

### Q5: Korean First-Keypress Issue Fix Strategy
**What we know:** Reported in Qt QTBUG-136128, rdar://FB17460926, Alacritty #6942. No confirmed
fix via NSTextInputClient.

**What's unclear:** Is there ANY workaround, or is this unfixable at app level?

**Recommendation:** Try pre-warming NSTextInputContext on app launch (create dummy context, call
activate, deactivate). May initialize Korean IME state. If fails, document as known macOS bug
with workaround (user types first char twice or refocuses). Mark LOW confidence (no verified
solution).

## Sources

### Primary (HIGH confidence)
- [Apple High Resolution
APIs](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/APIs/APIs.html) -
Retina scaling and convertRectToScreen
- [NSWindow.screen
property](https://developer.apple.com/documentation/appkit/nswindow/1419232-screen) - Official
screen detection API
- [Apple Coordinate
Systems](https://developer.apple.com/library/archive/documentation/General/Devpedia-CocoaApp-MOSX/CoordinateSystem.html) -
Origin conventions
- Phase 19 RESEARCH.md - VGlyph NSTextInputClient implementation
- Current ime_bridge_macos.m and ime_overlay_darwin.m source code

### Secondary (MEDIUM confidence)
- [R0uter's Blog: Multi-monitor window
position](https://www.logcg.com/en/archives/2771.html) - Multi-display coordinate challenges
- [Think and Build: Multiple
screens](https://www.thinkandbuild.it/deal-with-multiple-screens-programming/) - NSScreen
coordinate system
- [Mozilla Bug 875674](https://bugzilla.mozilla.org/show_bug.cgi?id=875674) - NSTextInputClient
patterns

### Tertiary (LOW confidence - Korean first-keypress issue)
- [Qt Bug QTBUG-136128](https://bugreports.qt.io/browse/QTBUG-136128) - Korean first char lost
after focus (confirmed bug, no fix)
- [rdar://FB17460926](https://openradar.appspot.com/FB17460926) - Apple bug report (Korean IME)
- [Godot PR #85458](https://github.com/godotengine/godot/pull/85458) - Korean IME
insertText+setMarkedText simultaneous call (different issue)
- [Alacritty Issue #6942](https://github.com/alacritty/alacritty/issues/6942) - CJK IME not
working (includes Korean first-keypress)

**Note on Korean issue sources:** Multiple projects confirm the bug exists, but no project has
confirmed fix. Godot fix addressed separate corruption issue. Qt and Apple bug reports remain
open. This suggests system-level bug, not implementation error.

## Metadata

**Confidence breakdown:**
- Multi-display coordinate handling: HIGH - Official Apple APIs, clear documentation
- Retina scaling: HIGH - Apple docs explicit, convertRectToScreen handles automatically
- Screen detection: HIGH - NSWindow.screen is standard approach
- Korean first-keypress fix: LOW - No confirmed solution across multiple projects

**Research date:** 2026-02-04
**Valid until:** 90 days (coordinate APIs stable since macOS 10.7, unlikely to change)

**Coverage:**
- DISP-01: Covered (NSWindow.screen + convertRectToScreen fix)
- DISP-02: Covered (convertRectToScreen handles Retina)
- Korean first-keypress: Research complete, no fix found (may require workaround strategy)

**Next steps for planner:**
- Fix ime_bridge_macos.m firstRectForCharacterRange (wrong screen bug)
- Verify ime_overlay_darwin.m uses convertRectToScreen correctly (already correct)
- Test multi-monitor: drag window between screens mid-composition
- Test Retina: internal + external displays with different scale factors
- Korean first-keypress: Attempt pre-warm workaround, document if fails
