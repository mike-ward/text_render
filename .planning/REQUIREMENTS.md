# Requirements: VGlyph v1.4 CJK IME

**Defined:** 2026-02-03
**Core Value:** Full CJK input method support without sokol modifications

## v1.4 Requirements

Requirements for CJK IME milestone. Each maps to roadmap phases.

### Overlay Infrastructure

- [ ] **OVLY-01**: VGlyphIMEOverlayView class implementing NSTextInputClient protocol
- [ ] **OVLY-02**: Overlay positioned above MTKView as sibling (not child)
- [ ] **OVLY-03**: Overlay activates as first responder when text field focused
- [ ] **OVLY-04**: Overlay deactivates and returns first responder to MTKView on blur
- [ ] **OVLY-05**: Non-Darwin stub implementation (no-op functions)

### NSTextInputClient Protocol

- [ ] **PROT-01**: setMarkedText:selectedRange:replacementRange: forwards to CompositionState
- [ ] **PROT-02**: insertText:replacementRange: commits text and inserts at cursor
- [ ] **PROT-03**: markedRange returns current composition byte range
- [ ] **PROT-04**: selectedRange returns cursor position within composition
- [ ] **PROT-05**: hasMarkedText returns true when composition active
- [ ] **PROT-06**: unmarkText cancels composition (auto-commit on focus loss)
- [ ] **PROT-07**: firstRectForCharacterRange:actualRange: returns screen coordinates
- [ ] **PROT-08**: validAttributesForMarkedText returns supported underline styles

### Japanese IME

- [ ] **JPIM-01**: Hiragana preedit displayed with underline during romaji→hiragana conversion
- [ ] **JPIM-02**: Clause segmentation visible (multiple underlined segments)
- [ ] **JPIM-03**: Space key triggers kanji conversion (shows candidate window)
- [ ] **JPIM-04**: Enter key commits selected candidate
- [ ] **JPIM-05**: Escape key cancels composition
- [ ] **JPIM-06**: Arrow keys navigate between clauses
- [ ] **JPIM-07**: Selected clause indicated by thick underline

### Chinese IME

- [ ] **CHIM-01**: Pinyin preedit displayed with underline during typing
- [ ] **CHIM-02**: Candidate window appears near cursor (via firstRectForCharacterRange)
- [ ] **CHIM-03**: Number keys (1-9) select candidate directly
- [ ] **CHIM-04**: Space key selects first candidate
- [ ] **CHIM-05**: Enter key commits typed pinyin as-is (if no candidate selected)

### Korean IME

- [ ] **KRIM-01**: Jamo composition displayed (ㄱ + ㅏ = 가) in real-time
- [ ] **KRIM-02**: Backspace decomposes syllable (간 → 가 → ㄱ → empty)
- [ ] **KRIM-03**: Space/punctuation commits current syllable
- [ ] **KRIM-04**: Single syllable preedit underlined during composition

### Keyboard Integration

- [ ] **KEYB-01**: Backspace forwarded to IME when hasMarkedText is true
- [ ] **KEYB-02**: Dead key composition works after using CJK IME
- [ ] **KEYB-03**: Focus loss auto-commits preedit (not lost)
- [ ] **KEYB-04**: Undo/redo blocked when hasMarkedText is true

### Multi-Display Support

- [ ] **DISP-01**: Candidate window appears on correct monitor
- [ ] **DISP-02**: Coordinate transforms work with Retina displays (backing scale factor)

## Future Requirements

Deferred to post-v1.4. Tracked but not in current roadmap.

### Advanced IME

- **ADVN-01**: Reconversion (select committed text, convert again)
- **ADVN-02**: Hanja conversion (Korean → Chinese characters)
- **ADVN-03**: Vertical text candidate window positioning
- **ADVN-04**: Custom keyboard layouts

### Cross-Platform

- **XPLT-01**: Linux IME support (IBus/Fcitx)
- **XPLT-02**: Windows IME support (TSF)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Custom IME implementation | Use system IME, don't reinvent |
| Dictionary management | System IME handles |
| Prediction/autocomplete | System IME feature |
| IME switching UI | System handles (Cmd+Space) |
| Handwriting recognition | Separate system feature |
| Voice input | Separate dictation system |
| Sokol modifications | Project constraint |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| OVLY-01 | Phase 18 | Pending |
| OVLY-02 | Phase 18 | Pending |
| OVLY-03 | Phase 18 | Pending |
| OVLY-04 | Phase 18 | Pending |
| OVLY-05 | Phase 18 | Pending |
| PROT-01 | Phase 19 | Pending |
| PROT-02 | Phase 19 | Pending |
| PROT-03 | Phase 19 | Pending |
| PROT-04 | Phase 19 | Pending |
| PROT-05 | Phase 19 | Pending |
| PROT-06 | Phase 19 | Pending |
| PROT-07 | Phase 19 | Pending |
| PROT-08 | Phase 19 | Pending |
| JPIM-01 | Phase 19 | Pending |
| JPIM-02 | Phase 19 | Pending |
| JPIM-03 | Phase 19 | Pending |
| JPIM-04 | Phase 19 | Pending |
| JPIM-05 | Phase 19 | Pending |
| JPIM-06 | Phase 19 | Pending |
| JPIM-07 | Phase 19 | Pending |
| CHIM-01 | Phase 19 | Pending |
| CHIM-02 | Phase 19 | Pending |
| CHIM-03 | Phase 19 | Pending |
| CHIM-04 | Phase 19 | Pending |
| CHIM-05 | Phase 19 | Pending |
| KRIM-01 | Phase 20 | Pending |
| KRIM-02 | Phase 20 | Pending |
| KRIM-03 | Phase 20 | Pending |
| KRIM-04 | Phase 20 | Pending |
| KEYB-01 | Phase 20 | Pending |
| KEYB-02 | Phase 20 | Pending |
| KEYB-03 | Phase 20 | Pending |
| KEYB-04 | Phase 20 | Pending |
| DISP-01 | Phase 21 | Pending |
| DISP-02 | Phase 21 | Pending |

**Coverage:**
- v1.4 requirements: 34 total
- Mapped to phases: 34
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-03*
*Last updated: 2026-02-03 after initial definition*
