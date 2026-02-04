# Phase 21: Multi-Display & Polish - Context

**Gathered:** 2026-02-04
**Status:** Ready for planning

<domain>
## Phase Boundary

CJK IME coordinate handling across multi-monitor and Retina setups. Candidate window positioning
on correct monitor, proper coordinate transforms for Retina displays, and all three CJK IMEs
completing basic flow end-to-end. **Must fix Korean first-keypress issue.**

</domain>

<decisions>
## Implementation Decisions

### Monitor Detection
- Claude's Discretion: Which monitor "owns" window spanning monitors
- Claude's Discretion: Whether candidate window follows window drag mid-composition
- Claude's Discretion: NSScreen query strategy (at call time vs cached with notifications)
- Claude's Discretion: External monitor hot-plug handling during composition

### Retina Handling
- Claude's Discretion: Scale factor source (NSWindow vs NSScreen backingScaleFactor)
- Claude's Discretion: Fractional scaling handling (macOS uses integer scales)
- Claude's Discretion: When/where scale factor applies to coordinates
- Claude's Discretion: Mixed DPI setup handling

### Fallback Behavior
- Claude's Discretion: Fallback position when coordinate calculation fails
- Claude's Discretion: Logging level for coordinate failures
- Claude's Discretion: Edge-of-screen candidate window clamping
- Claude's Discretion: Window minimization handling during composition

### End-to-End Validation
- Claude's Discretion: Verification approach (manual checklist vs automated)
- Claude's Discretion: Demo mode for IME showcase
- Claude's Discretion: Definition of "complete basic flow" per IME
- **Must fix:** Korean first-keypress issue (not "document as known")

</decisions>

<specifics>
## Specific Ideas

- Korean first-keypress bug is a hard requirement to fix, not a "known issue" to ship with
- All technical decisions delegated to Claude based on macOS conventions and API contracts

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 21-multi-display-polish*
*Context gathered: 2026-02-04*
