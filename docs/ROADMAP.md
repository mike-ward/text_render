# vglyph Feature Recommendations

This document outlines practical recommendations to bring `vglyph`'s rendering quality and feature
set in line with industry-standard text engines like CoreText (macOS), DirectWrite (Windows), and
modern web browsers.

## 1. Rendering Quality

The most immediate "feel" of a text engine comes from its rendering pipeline. `vglyph` currently
uses standard grayscale antialiasing.

### 1.1 LCD Subpixel Antialiasing
**Priority:** High
**Impact:** Sharper text on non-Retina displays.

Standard engines use subpixel rendering (exploiting the R, G, B subpixels of LCD screens) to triple
horizontal resolution.
- **Current State:** `glyph_atlas.v` loads `FT_PIXEL_MODE_GRAY` (8-bit alpha) and expands it to
  white + alpha.
- **Recommendation:** Implement a pipeline for `FT_RENDER_MODE_LCD`.
    - **Atlas:** Needs to store 3 channels (R, G, B) instead of just Alpha.
    - **Shader:** Needs a custom shader in `renderer.v` to blend individual color channels correctly
      against the background.

### 1.2 Tunable Gamma Correction / Stem Darkening
**Priority:** High
**Impact:** Matches system font weight perception.

macOS and Windows render fonts with different "weights" due to gamma correction. Standard engines
allow tuning this or default to a platform-specific value.
- **Current State:** No explicit gamma correction; linear alpha blending.
- **Recommendation:** Add a `gamma` float to `Renderer` or `TextConfig`.
    - Allows users to thicken fonts (e.g., gamma 1.8-2.2) to match macOS style.
    - Necessary because FreeType's raw rasterization is often perceived as too thin on high-DPI
      screens without stem darkening.

### 1.3 Subpixel Positioning
**Priority:** Medium
**Impact:** Smoother animations and more precise kerning.

Professional engines position glyphs at fractional pixel coordinates (e.g., x=10.25).
- **Current State:** `Renderer` rounds positions or relies on `gg`'s texture sampling.
- **Recommendation:** Ensure the entire pipeline (Layout -> Renderer) preserves `f32` precision.
    - Use "oversampled" bitmap positioning or specialized shaders to handle fractional offsets
      without blurring.

## 2. Rich Text & Layout

Standard engines support "Attributed Strings"—single text buffers with multiple styles.

### 2.1 Attributed String API
**Priority:** High
**Impact:** Essential for code editors, rich text documents, and complex UI.

- **Current State:** `draw_text(string, TextConfig)`. formatting applies to the entire string. Pango
  markup is supported via string parsing, but this is brittle for programmatic use.
- **Recommendation:** Introduce a `RichText` struct.
    ```v
    struct RichText {
        text string
        runs []StyleRun // { start, end, config }
    }
    ```
    - Refactor `Context.layout_text` to accept this structure.
    - Allows programmatic toggling of bold/color ranges without string operations.

### 2.2 Paragraph Styles
**Priority:** Medium
**Impact:** Required for document editors.

- **Current State:** `TextConfig` mixes character style (Font, Color) with paragraph style
  (Align, Wrap).
- **Recommendation:** Split `TextConfig` into `TextStyle` (Font, Color, Size) and `ParagraphStyle`
  (Alignment, Wrap, LineHeight, Indent, SpacingBefore/After).

### 2.3 Inline Objects
**Priority:** Low
**Impact:** Chat apps (inline images), documents.

- **Current State:** Only text glyphs.
- **Recommendation:** Support `RunDelegate` or `Attachment` in the layout, reserving space
  (width/height) for custom rendering (images, UI controls) within the text flow.

## 3. Advanced Typography

### 3.1 OpenType Features API
**Priority:** Medium
**Impact:** Professional typography (Coding ligatures, Small Caps).

- **Current State:** `TextConfig` has a `font_name` string.
- **Recommendation:** Add a typed API for toggling features.
    ```v
    features: { 'liga': 1, 'smcp': 0 } // Typesafe feature control
    ```

### 3.2 Variable Fonts
**Priority:** Medium (Future)
**Impact:** Modern UI design flexibility.

- **Current State:** Implicit support via Pango strings possibly, but no explicit control.
- **Recommendation:** Expose Variable Font axes (`wght`, `wdth`, `slnt`, `opsz`) in the API to
  allow smooth animation of font weight/width.

## 4. System Integration

### 4.1 Robust Font Fallback
**Priority:** High
**Impact:** Multilingual support.

- **Current State:** Relies on Pango's internal list.
- **Recommendation:** Ensure `vglyph` can query the system (CoreText/DirectWrite) for the correct
  fallback font when a glyph is missing, rather than rendering "tofu" (boxes).

### 4.2 Accessibility Tree
**Priority:** Low (but Critical for commercial apps)
**Impact:** Screen reader support.

- **Recommendation:** Expose the logic structure (Lines, Paragraphs) to the OS accessibility API.
  (This is a large undertaking but standard for native-feeling apps).
