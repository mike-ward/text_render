---
phase: 20-korean-keyboard
verified: 2026-02-04T17:30:00Z
status: human_needed
score: 4/5 must-haves verified
gaps:
  - truth: "Korean jamo composition displays in real-time (first keypress)"
    status: partial
    reason: "First keypress after focus fails; second+ keypresses work"
    artifacts:
      - path: "ime_overlay_darwin.m"
        issue: "NSTextInputContext activation timing unknown"
    missing:
      - "Root cause for first-keypress failure (documented as unknown)"
human_verification:
  - test: "Korean jamo composition on second+ keypress"
    expected: "gks -> displays underlined syllable building: g -> k -> 간"
    why_human: "Visual behavior, IME interaction"
  - test: "Backspace decomposes syllable"
    expected: "간 -> 가 -> g -> empty (jamo-by-jamo decomposition)"
    why_human: "IME-driven behavior, visual verification"
  - test: "Focus loss auto-commits preedit"
    expected: "Click away while composing -> preedit text becomes permanent"
    why_human: "Focus management + IME interaction"
  - test: "Dead keys work after Korean IME"
    expected: "Switch US keyboard, Option+e e -> e (no state pollution)"
    why_human: "Cross-IME state management"
  - test: "Undo/redo blocked during composition"
    expected: "Cmd+Z while composing -> nothing happens"
    why_human: "Keyboard + IME interaction"
---

# Phase 20: Korean + Keyboard Integration Verification Report

**Phase Goal:** Korean hangul composition works, keyboard edge cases handled
**Verified:** 2026-02-04T17:30:00Z
**Status:** human_needed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Korean jamo composition displays in real-time | PARTIAL | First keypress fails (documented known issue); second+ work |
| 2 | Backspace decomposes syllable correctly | VERIFIED | keyDown forwards to interpretKeyEvents when hasMarkedText (line 191-193) |
| 3 | Dead key composition works after CJK IME | VERIFIED | invalidateCharacterCoordinates called in resignFirstResponder (line 242) |
| 4 | Focus loss auto-commits preedit | VERIFIED | resignFirstResponder calls unmarkText when hasMarkedText (line 237-238) |
| 5 | Undo/redo blocked during active composition | VERIFIED | composition.is_composing() guard at lines 346 and 365 |

**Score:** 4/5 truths verified (criterion #1 is partial due to first-keypress issue)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `ime_overlay_darwin.m` | keyDown + focus handlers | VERIFIED | 342 lines, substantive implementation |
| `ime_bridge_macos.m` | NSTextInputClient swizzling | VERIFIED | 343 lines, interpretKeyEvents integration |
| `examples/editor_demo.v` | Composition-aware keyboard | VERIFIED | 1276 lines, 11 is_composing() guards |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| keyDown: | interpretKeyEvents: | hasMarkedText check | WIRED | Line 191: `if ([self hasMarkedText]) { [self interpretKeyEvents:@[event]]; }` |
| resignFirstResponder | invalidateCharacterCoordinates | NSTextInputContext | WIRED | Line 242: `[[self inputContext] invalidateCharacterCoordinates];` |
| resignFirstResponder | unmarkText | hasMarkedText check | WIRED | Line 237-238: commits preedit on focus loss |
| Cmd+Z handler | is_composing() | guard return | WIRED | Line 346-348: blocks undo during composition |
| Cmd+Shift+Z handler | is_composing() | guard return | WIRED | Line 365-367: blocks redo during composition |
| Option+Backspace | composition.cancel() | is_composing() guard | WIRED | Line 675-679: cancels composition first |
| Cmd+A handler | composition.commit() | is_composing() guard | WIRED | Line 388-410: commits then selects |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| KRIM-01: Korean jamo composition | PARTIAL | First-keypress fails |
| KRIM-02: Backspace decomposition | SATISFIED | keyDown forwards to IME |
| KRIM-03: Focus loss handling | SATISFIED | resignFirstResponder commits |
| KRIM-04: Dead key after CJK | SATISFIED | invalidateCharacterCoordinates |
| KEYB-01: Undo blocking | SATISFIED | is_composing() guards |
| KEYB-02: Option+Backspace | SATISFIED | cancel() before word delete |
| KEYB-03: Cmd+A commit | SATISFIED | commit() then select |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none found) | - | - | - | - |

No stub patterns, TODOs, or placeholder implementations found in phase 20 artifacts.

### Human Verification Required

Human testing needed for IME visual/interactive behavior that cannot be verified statically:

### 1. Korean Jamo Composition (Second+ Keypress)

**Test:** Switch to Korean keyboard, click in field, type 'gks'
**Expected:** Should see syllable building: g -> k -> 간 (underlined preedit)
**Why human:** Visual IME behavior, native input context interaction

### 2. Backspace Syllable Decomposition

**Test:** After composing 간, press Backspace three times
**Expected:** 간 -> 가 -> g -> (empty), jamo-by-jamo decomposition
**Why human:** IME-driven decomposition, visual verification required

### 3. Focus Loss Auto-Commit

**Test:** Type Korean text, click outside field while composing
**Expected:** Preedit text (underlined) becomes permanent committed text
**Why human:** Focus management + IME commit interaction

### 4. Dead Keys After Korean IME

**Test:** Use Korean IME, then switch to US keyboard, type Option+e e
**Expected:** Should produce e with acute accent
**Why human:** Cross-IME state management verification

### 5. Undo/Redo Blocking During Composition

**Test:** While composing Korean text, press Cmd+Z
**Expected:** Nothing happens (undo is blocked)
**Why human:** Keyboard + IME interaction timing

### Known Issue: First-Keypress Failure

The first keypress after focusing the text field does not trigger Korean IME composition. Subsequent keypresses work correctly. This affects criterion #1 partially.

**Root cause:** Unknown. Investigated approaches documented in 20-CONTEXT.md:
- NSTextInputContext.activate timing
- Lazy vs eager context creation  
- handleEvent vs interpretKeyEvents
- Missing doCommandBySelector method
- Swizzling timing relative to sokol view creation

**User impact:** Typing first character twice, or click-away-click-back to refocus.

**Recommendation:** This is a known limitation that requires deeper investigation of macOS NSTextInputContext initialization. Phase can proceed with partial status as Korean IME is functional after first keypress.

---

*Verified: 2026-02-04T17:30:00Z*
*Verifier: Claude (gsd-verifier)*
