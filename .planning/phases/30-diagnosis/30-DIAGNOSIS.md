# Phase 30: Diagnosis Report

## Summary
All three v1.6 regression symptoms trace to Phase 27 async double-buffer data loss.
The async commit path swaps staging buffers without preserving accumulated glyph data,
causing glyphs to alternate visible/invisible each frame.

## DIAG-01: Scroll Flickering

**Root Cause:** Double-buffer swap without accumulation. After swap, staging_back
(next CPU write target) contains stale data from 2 frames ago, not the current
frame's glyphs. Each buffer only has every-other-frame's data.

**Evidence:**
- Code path: `renderer.v:131-150` async commit does `page.swap_staging_buffers()`
  then `page.image.update_pixel_data(page.staging_front.data)`.
- Frame N: CPU writes glyphs to staging_back. Swap (front=new, back=stale). Upload
  front to GPU.
- Frame N+1: CPU writes NEW glyphs to staging_back (which is old_front from Frame
  N-1, does NOT contain Frame N glyphs). Swap. Upload front (= old_back from Frame
  N+1, has Frame N+1 glyphs but NOT Frame N glyphs).
- Result: Glyphs from Frame N disappear in Frame N+1 upload (GPU sees alternate
  buffer), reappear in Frame N+2.

**Trigger:** Any frame with new glyph rasterization.

**Offending Phase:** Phase 27 (async texture updates)

**Code Path:** `renderer.v:131` commit() async path → `glyph_atlas.v:763`
swap_staging_buffers()

## DIAG-02: Rendering Delays

**Root Cause:** Two-frame stabilization delay. New glyphs must exist in BOTH buffers
for stable rendering, but current implementation only writes to one buffer per frame.

**Evidence:**
- Same double-buffer data loss as DIAG-01. New glyph rasterized in Frame N goes to
  staging_back. After swap, staging_back for Frame N+1 does NOT contain Frame N's
  glyph (it's the alternate buffer).
- Frame N: Glyph visible (uploaded from front). Frame N+1: Glyph invisible (uploaded
  from alternate front without that glyph). Frame N+2: Glyph visible again (if
  re-rasterized or if happens to be in correct buffer).
- Perceived as "rendering delay" because uncached glyph takes 2+ frames to stabilize.

**Trigger:** First render of uncached glyph.

**Offending Phase:** Phase 27

## DIAG-03: Blank Scroll Regions

**Root Cause:** Rapid scroll to new area requires rasterizing many glyphs in short
time. Each new glyph only appears in one buffer (every-other-frame pattern). With
high scroll velocity, many glyphs simultaneously in "invisible frame" state, creating
visible blank regions.

**Evidence:**
- Same double-buffer data loss mechanism. Scrolling to new content triggers burst of
  glyph rasterization (cache misses for off-screen glyphs now visible).
- Each new glyph enters the alternation pattern. With rapid scroll, many glyphs in
  their "invisible frame" at same time.
- User perception: Large blank regions during scroll (multiple glyphs missing
  simultaneously) rather than isolated flicker (single glyph).

**Trigger:** Scroll to area requiring new glyph rasterization (cache misses).

**Offending Phase:** Phase 27

## Fix Recommendation

After swap in `glyph_atlas.v:swap_staging_buffers()`, copy staging_front to
staging_back:

```v oksyntax
fn (mut page AtlasPage) swap_staging_buffers() {
	tmp := page.staging_front
	page.staging_front = page.staging_back
	page.staging_back = tmp
	// FIX: Preserve accumulated data for next frame
	unsafe {
		vmemcpy(page.staging_back.data, page.staging_front.data, page.staging_front.len)
	}
}
```

Cost: One memcpy per dirty page per frame (~16-64MB per page at 4096x4096). Preserves
CPU/GPU overlap while fixing accumulation. Sync path (direct staging_back → image.data
copy) does not have this bug and does not need modification.

## Empirical Evidence

Plan 01 kill switch results (5-sec automated scroll test):

**Async mode (`v -d diag`):**
- Buffer swaps occur (front/back exchange with different data)
- Uploads infrequent (frames 442, 4922 in window)
- No identical buffer warnings
- No atlas resets in test window

**Sync mode (`v -d diag -d diag_sync`):**
- No buffer swaps (direct staging_back → image.data copy)
- Uploads frequent (every few hundred frames)
- Clean diagnostic output

Observation: Test window too short to trigger atlas resets (LRU eviction). Both modes
ran without errors. Longer runs or higher glyph density needed to expose blank region
symptoms via atlas reset cascade. However, static code analysis confirms double-buffer
data loss pattern regardless of empirical results.