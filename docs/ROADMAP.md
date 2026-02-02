# VGlyph Roadmap

This document outlines the feature set evaluation, completed milestones, and proposed future enhancements for the VGlyph text rendering engine.

## 1. Feature Evaluation

### Current Capabilities
*   **Core Layout**: Comprehensive support for complex scripts (Arabic, Hebrew, etc.) via Pango.
*   **Rich Text**: Styling via `RichText` struct and Pango attributes (Color, Font, Underline, Strikethrough).
*   **Typography**: OpenType features, Variable font axes.
*   **Rendering**: High-performance batched rendering with Sokol, cached via LRU mechanism.
*   **Interaction**: Basic hit-testing (point-to-index, index-to-rect).
*   **Vertical Text**: Implemented via custom "manual stacking" of horizontal glyphs (upright CJK).
*   **System Integration**: Robust font fallback and initial accessibility bindings.

### Identified Gaps
*   **Justification**: Text currently supports Left, Center, and Right alignment. Justified alignment (filling the width) is missing.
*   **Editor Logic**: While `editor_demo.v` exists, there is no reusable `Editor` component or logic for cursor navigation (e.g., "move by word", "move by paragraph") and selection management.
*   **Input Handling**: No interaction with OS-level Input Method Editors (IME), crucial for international input.
*   **Complex Vertical Text**: The current manual stacking handles upright characters well but may not support mixed orientation (e.g., rotated Latin text in a vertical column) efficiently.
*   **Path Rendering**: No support for rendering text along arbitrary paths/curves.

## 2. Completed Features (Status Report)

### 2.1 Rendering Quality
- [x] **LCD Subpixel Antialiasing**: Implemented hybrid strategy (LCD for high-DPI, Grayscale+Gamma for low-DPI).
- [x] **Gamma Correction**: Tuned (~1.45) for consistent weight.
- [x] **Subpixel Positioning**: Implemented with 4-bin oversampling.

### 2.2 Rich Text & Layout
- [x] **Attributed String API**: `RichText` struct implemented with `StyleRun`s.
- [x] **Block Styles**: `TextConfig` split into `TextStyle` and `BlockStyle`.
- [x] **Inline Objects**: Support for `InlineObject` via Pango shapes.

### 2.3 Advanced Typography
- [x] **OpenType Features**: Typed API for features (e.g., `liga`, `smcp`) implemented.
- [x] **Variable Fonts**: Support for arbitrary variation axes (`wght`, `wdth`, etc.).

### 2.4 System Integration
- [x] **Robust Font Fallback**: Automatic system fallback supported via Pango/FontConfig.
- [x] **Accessibility**: Initial VoiceOver support (macOS) implemented via `accessibility` module.

## 3. Future Roadmap

### Short Term (v0.9.x)

- [ ] **Justified Alignment**
    - Bind `pango_layout_set_justify`.
    - Update `BlockStyle` and hashing logic.

- [ ] **Editor Primitives**
    - Create a `TextBuffer` or `Cursor` helper struct.
    - Implement navigation logic: `move_next_word`, `move_next_line`, `select_range`.

### Medium Term (v1.0)

- [ ] **Input Method Support (IME)**
    - Integrate with OS text input events.
    - Handle candidate windows and composition strings.

- [ ] **Advanced Vertical Text**
    - Investigate usage of `pango_context_set_base_gravity` combined with `pango_context_set_base_dir` for native vertical layout.
    - Support mixed rotation (sideways Latin, upright CJK).

- [ ] **Serialization**
    - Add JSON/Markdown import/export for `RichText` structures.

### Long Term / Research

- [ ] **Text on Path**
    - Implement logic to map glyph positions onto Bezier curves.

- [ ] **SDF / MSDF Rendering**
    - Research Signed Distance Field rendering for infinite scalability without re-rasterization.
    - Alternative render pipeline alongside current bitmap atlas.

- [ ] **Pagination**
    - Support for breaking text flows across multiple logic containers (pages).
