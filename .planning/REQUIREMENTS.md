# Requirements: VGlyph v1.8

**Defined:** 2026-02-05
**Core Value:** Reliable text rendering without crashes or undefined
behavior

## v1.8 Requirements

Requirements for overlay API activation. Each maps to roadmap phases.

### IME Overlay

- [ ] **IME-01**: Obj-C helper discovers MTKView from NSWindow via
  view hierarchy walk
- [ ] **IME-02**: editor_demo creates overlay via
  `vglyph_create_ime_overlay()` using discovered MTKView
- [ ] **IME-03**: editor_demo registers per-overlay callbacks instead
  of global callbacks
- [ ] **IME-04**: Global callback API retained as fallback
- [ ] **IME-05**: Update SECURITY.md, README, and relevant docs to
  reflect overlay API activation
- [ ] **IME-06**: Cross-platform guards — Linux/Windows compile and
  run without macOS overlay code

## Future Requirements

None for this milestone.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-field demo | Proves capability but not needed for v1.8 |
| Remove global callback API | Kept as fallback per user decision |
| Korean first-keypress fix | macOS-level bug, upstream |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| IME-01 | Phase 33 | Pending |
| IME-02 | Phase 33 | Pending |
| IME-03 | Phase 33 | Pending |
| IME-04 | Phase 33 | Pending |
| IME-05 | Phase 34 | Pending |
| IME-06 | Phase 33 | Pending |

**Coverage:**
- v1.8 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-02-05*
*Last updated: 2026-02-05 after roadmap creation*
