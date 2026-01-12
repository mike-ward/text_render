# LCD Subpixel Antialiasing Implementation

## Overview

This plan implements LCD subpixel antialiasing for sharper text on non-Retina
displays by leveraging FreeType's `FT_RENDER_MODE_LCD` and
`FT_PIXEL_MODE_LCD`. The implementation will triple horizontal resolution by
exploiting RGB subpixels.

## Background

Current state: `glyph_atlas.v` loads `FT_PIXEL_MODE_GRAY` (8-bit alpha) and
expands it to white + alpha in an RGBA8 atlas. This works well but doesn't
take advantage of subpixel rendering available on LCD displays.

FreeType LCD rendering produces bitmaps that are 3x wider than standard
grayscale, with each "pixel" containing RGB coverage values for individual
subpixels. Proper display requires either:
1. Storing RGB data and using standard alpha blending (simpler, good results)
2. Custom shader with per-channel blending (optimal, more complex)

## User Review Required

> [!IMPORTANT]
> **Shader Complexity Decision**
> 
> This plan proposes a **two-phase approach**:
> - **Phase 1** (this plan): Add FT_PIXEL_MODE_LCD support to atlas, store RGB
>   data, use standard gg rendering. This provides most of the benefit with
>   minimal complexity.
> - **Phase 2** (future): Add custom sokol shader for per-channel blending if
>   needed for optimal quality.
> 
> Phase 1 should provide significant improvement over current grayscale
> rendering. We can evaluate whether Phase 2 is necessary after testing.

> [!WARNING]
> **Display Compatibility**
> 
> LCD subpixel rendering assumes horizontal RGB subpixel layout. It will look
> incorrect on:
> - Vertical subpixel layouts (rare)
> - BGR layouts (some displays)
> - OLED/non-LCD displays
> - Rotated displays
> 
> The implementation includes automatic fallback to grayscale on high-DPI
> displays (where subpixel rendering provides minimal benefit).

## Proposed Changes

### Phase 1: Core LCD Support (This Plan)

---

#### [MODIFY] [glyph_atlas.v](file:///Users/mike/Documents/github/vglyph/glyph_atlas.v)

**Changes to `load_glyph` function (lines 59-89):**
- Add logic to detect high-DPI displays (scale_factor >= 2.0)
- On low-DPI displays, use `FT_LOAD_TARGET_LCD` instead of
  `FT_LOAD_TARGET_LIGHT`
- Pass render mode hint to `ft_bitmap_to_bitmap`

**Changes to `ft_bitmap_to_bitmap` function (lines 102-203):**
- Add new case for `FT_PIXEL_MODE_LCD` (constant already defined as 5)
- For LCD mode:
  - Width from bitmap is already 3x (subpixel resolution)
  - Each "pixel" in FreeType bitmap contains 3 bytes (R, G, B coverage)
  - Convert to RGBA8 by reading RGB from source, setting A=255
  - Handle pitch correctly (use `bitmap.pitch` not `bitmap.width * 3`)

**Atlas storage:**
- No changes needed - RGBA8 format already supports RGB data
- LCD glyphs will have RGB coverage values instead of white+alpha
- Grayscale glyphs continue to use white+alpha as before

---

#### [MODIFY] [renderer.v](file:///Users/mike/Documents/github/vglyph/renderer.v)

**Changes to `Renderer` struct (lines 14-20):**
- Add `lcd_mode bool` field to track whether LCD rendering is enabled

**Changes to `new_renderer` function (lines 22-30):**
- Detect if LCD mode should be enabled based on scale_factor
- Set `lcd_mode: scale_factor < 2.0` (disable on Retina displays)

**Changes to `load_glyph` function (line 102):**
- Pass `renderer.lcd_mode` to glyph loading logic

**No shader changes in Phase 1:**
- Standard gg rendering will blend RGB values
- This provides improved sharpness even without per-channel blending
- Results should be significantly better than grayscale

---

#### [MODIFY] [c_bindings.v](file:///Users/mike/Documents/github/vglyph/c_bindings.v)

**Add LCD filter support (after line 165):**
- Add FreeType LCD filter constants:
  - `ft_render_mode_lcd = 3`
  - `ft_render_mode_lcd_v = 4`
  - `ft_lcd_filter_default = 0`
  - `ft_lcd_filter_light = 1`
  - `ft_lcd_filter_none = 2`
- Add function binding: `fn C.FT_Library_SetLcdFilter(&C.FT_LibraryRec, i32)
  int`

---

#### [MODIFY] [context.v](file:///Users/mike/Documents/github/vglyph/context.v)

**Initialize LCD filter in FreeType library:**
- In `new_context` function, after FT_Init_FreeType
- Call `C.FT_Library_SetLcdFilter(ft_lib, ft_lcd_filter_default)`
- This enables FreeType's built-in color fringe reduction

---

### Phase 2: Custom Shader (Future, Not in This Plan)

If Phase 1 results are insufficient, we can add:
- Custom sokol shader using `v shader` tool
- Per-channel alpha blending
- Gamma correction
- This would require significant additional work with sokol integration

## Verification Plan

### Automated Tests

No existing automated tests cover rendering output. Visual verification is
required.

### Manual Verification

**Test 1: Visual Quality on Non-Retina Display**

Requirements:
- Non-Retina display (scale_factor = 1.0)
- LCD monitor with RGB subpixel layout

Steps:
1. Build and run the crisp_demo example:
   ```bash
   v run examples/crisp_demo.v
   ```
2. Compare text sharpness before/after changes
3. Look for:
   - Sharper edges on diagonal strokes
   - Improved clarity on small text (12-16pt)
   - Minimal color fringing (should be subtle)
4. Take screenshots for before/after comparison

Expected result: Text should appear noticeably sharper, especially on vertical
and diagonal strokes. Color fringing should be minimal due to FreeType's LCD
filter.

**Test 2: Retina Display Fallback**

Requirements:
- Retina/HiDPI display (scale_factor >= 2.0)

Steps:
1. Run same example on Retina display
2. Verify text renders correctly (should use grayscale mode)
3. No visual artifacts or color issues

Expected result: Text should render identically to current implementation
(grayscale antialiasing).

**Test 3: Multi-Language Support**

Steps:
1. Run the demo example with multilingual text:
   ```bash
   v run examples/demo.v
   ```
2. Verify Arabic, Hebrew, emoji, and CJK text render correctly
3. Check that color bitmap glyphs (emoji) are unaffected

Expected result: All text types render correctly. Emoji should be unchanged
(they use FT_PIXEL_MODE_BGRA, not LCD mode).

**Test 4: Performance**

Steps:
1. Run stress test:
   ```bash
   v run examples/stress_demo.v
   ```
2. Monitor frame rate and atlas size
3. Compare with current implementation

Expected result: Similar performance. LCD bitmaps are 3x wider but this should
not significantly impact atlas usage for typical text.

### User Acceptance

After implementation, user should:
1. Test on their target non-Retina display
2. Verify sharpness improvement meets expectations
3. Decide if Phase 2 (custom shader) is necessary
