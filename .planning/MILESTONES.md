# Project Milestones: VGlyph

## v1.5 Codebase Quality Audit (Shipped: 2026-02-04)

**Delivered:** Security-first audit of entire codebase with input validation, error handling,
formatting compliance, documentation sync, and verification pass. Clean bill of health.

**Phases completed:** 22-25 (11 plans total)

**Key accomplishments:**

- Input validation layer with UTF-8 checking, path traversal protection, numeric bounds at all APIs
- Null safety hardening with nil checks at C FFI boundaries, 1GB allocation limits enforced
- Error path audit: all silent failures → error returns, `// Returns error if:` documentation
- Formatting compliance: `v fmt -verify` passes, no lines >99 chars
- Documentation sync: 22 example headers, README verified accurate, algorithm docs added
- Verification pass: 6/6 tests pass, 22/22 examples compile, SECURITY.md added

**Stats:**

- 73 files modified
- 13,984 lines of V/Obj-C (+5,354 additions)
- 4 phases, 11 plans, 31 requirements satisfied
- Same-day execution (2026-02-04)

**Git range:** `e4f7d6c` → `fa32130`

**What's next:** TBD (run `/gsd:new-milestone`)

---

## v1.4 CJK IME (Shipped: 2026-02-04)

**Delivered:** CJK input method support for Japanese, Chinese, and Korean via transparent overlay
NSView architecture, without sokol modifications. Japanese and Chinese fully working, Korean has
known macOS first-keypress bug.

**Phases completed:** 18-21 (9 plans total)

**Key accomplishments:**

- Transparent overlay IME infrastructure (VGlyphIMEOverlayView as sibling above MTKView)
- Japanese IME: Romaji → hiragana → kanji with clause segmentation and underline styles
- Chinese IME: Pinyin → candidates → selection via number/space keys
- Preedit rendering with thick underline for selected clause
- Multi-monitor coordinate handling (convertRectToScreen pattern)
- Keyboard integration: undo/redo blocked during composition, Option+Backspace cancels

**Stats:**

- 41 files modified
- 7,544 lines of V/Obj-C (+6,566 additions)
- 4 phases, 9 plans
- 2 days execution (2026-02-03 → 2026-02-04)

**Git range:** `feat(18-01)` → `docs(21)`

**Known issue:** Korean first-keypress fails (macOS-level bug, reported upstream: Qt QTBUG-136128,
Apple FB17460926, Alacritty #6942)

**What's next:** TBD (run `/gsd:new-milestone`)

---

## v1.3 Text Editing (Shipped: 2026-02-03)

**Delivered:** Text editing with cursor, selection, mutation, undo/redo, dead key IME, and VoiceOver
accessibility for VGlyph's layout engine.

**Phases completed:** 11-17 (15 plans total)

**Key accomplishments:**

- Click-to-position cursor with grapheme cluster support (emoji as single units)
- Selection (click-drag, shift+arrow, double/triple-click word/paragraph)
- Text mutation (insert/delete/backspace with modifiers, clipboard cut/copy/paste)
- Undo/redo with 1s coalescing and 100-entry history limit
- Dead key composition for accented characters (grave, acute, circumflex, tilde, umlaut)
- VoiceOver accessibility announcements for navigation, selection, and editing

**Stats:**

- 61 files modified
- 12,035 lines of V (+12,234 additions)
- 7 phases, 15 plans
- 39 days execution (2025-12-26 → 2026-02-03)

**Git range:** `feat(11-01)` → `docs(17)`

**Tech debt:** CJK IME blocked by sokol architecture (dead keys work, full NSTextInputClient requires
sokol modification)

**What's next:** TBD (run `/gsd:new-milestone`)

---

## v1.2 Performance Optimization (Shipped: 2026-02-02)

**Delivered:** Performance instrumentation, latency optimizations, and memory management for VGlyph's
rendering pipeline.

**Phases completed:** 8-10 (6 plans total)

**Key accomplishments:**

- Zero-overhead profiling with `-d profile` conditional compilation
- Multi-page texture atlas (4 pages max) with LRU page eviction
- MetricsCache for FreeType font metrics (256-entry LRU)
- GPU emoji scaling via destination rect (no CPU bicubic)
- Glyph cache LRU eviction with configurable max entries (4096 default)
- Unified get_profile_metrics() API aggregating all subsystem metrics

**Stats:**

- 5 files modified (context.v, layout.v, renderer.v, glyph_atlas.v, api.v)
- 5,309 lines of V (+726/-220)
- 3 phases, 6 plans
- 1 day execution (2026-02-02)

**Git range:** `feat(08-01)` → `feat(10-01)`

**What's next:** TBD (run `/gsd:new-milestone`)

---

## v1.1 Fragile Area Hardening (Shipped: 2026-02-02)

**Delivered:** Hardened VGlyph's fragile areas with iterator lifecycle safety, AttrList ownership
clarity, FreeType state validation, and vertical coordinate transform documentation.

**Phases completed:** 4-7 (4 plans total)

**Key accomplishments:**

- Iterator lifecycle docs at all creation sites with debug-only exhaustion guards
- AttrList ownership boundaries documented with debug leak counter
- FreeType load→translate→render sequence documented with debug validation
- Vertical coordinate transforms with inline formulas and match dispatch
- Consistent debug pattern ($if debug {}) across all phases with zero release overhead

**Stats:**

- 2 files modified (layout.v, glyph_atlas.v)
- 8,540 lines of V
- 4 phases, 4 plans, 11 tasks
- 1 day execution (2026-02-02)

**Git range:** `feat(04-01)` → `feat(07-01)`

**What's next:** TBD (run `/gsd:new-milestone`)

---

## v1.0 Memory & Safety Hardening (Shipped: 2026-02-01)

**Delivered:** Hardened VGlyph's memory operations with error propagation, allocation validation, and
proper string lifetime management.

**Phases completed:** 1-3 (3 plans total)

**Key accomplishments:**

- Error-returning GlyphAtlas API with dimension/overflow/allocation validation
- check_allocation_size helper enforcing 1GB limit and overflow protection
- grow() error propagation through insert_bitmap
- Pointer cast documentation with debug-build runtime validation
- String lifetime management for inline object IDs (clone on store, free on destroy)

**Stats:**

- 23 files created/modified
- 8,301 lines of V
- 3 phases, 3 plans, 8 tasks
- 37 days from start to ship

**Git range:** `dcabe59` → `d5104a1`

**What's next:** TBD (run `/gsd:new-milestone`)

---
