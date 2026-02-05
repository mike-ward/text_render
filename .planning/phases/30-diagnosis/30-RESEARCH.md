# Phase 30: Diagnosis - Research

**Researched:** 2026-02-05
**Domain:** GPU rendering diagnostics, texture atlas debugging, performance regression analysis
**Confidence:** HIGH

## Summary

Phase 30 requires identifying root causes of three intermittent v1.6 regressions in
stress_demo: scroll flickering, rendering delays, blank scroll regions. Primary suspects are
Phase 26 (shelf packing), Phase 27 (async uploads), and Phase 28 (profiling validation).

Key findings: v1.6 introduced double-buffered texture uploads (staging_front/staging_back) with
async commit logic. Modern GPU debugging requires frame capture tools (Xcode Metal Debugger),
instrumentation for CPU-GPU synchronization tracking, and stress testing with variable loads.
Common root causes: buffer swap timing issues, race conditions between CPU writes and GPU reads,
stale texture data from incomplete synchronization.

**Primary recommendation:** Use systematic binary search approach with kill switches
(async_uploads flag), add frame-level instrumentation to capture buffer state, employ Xcode GPU
frame capture to visualize texture contents at symptom occurrence, create reproducible stress
test scenarios with scroll automation.

## Standard Stack

### Core Tools
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Xcode Metal Debugger | Xcode 15+ | GPU frame capture, texture inspection | Apple's official Metal debugging tool, shows per-frame GPU state |
| V Profile Mode | -d profile | Timing instrumentation, cache metrics | Built-in VGlyph profiling with ProfileMetrics |
| stress_demo | existing | Regression reproduction | Already exhibits symptoms, 6000 glyphs with scroll |
| stress_validation | existing | Controlled profiling | Three-pass measurement (warmup/async/sync) |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| RenderDoc | 1.x | Cross-platform GPU frame debugger | If Metal Debugger insufficient, supports Vulkan/OpenGL/D3D |
| git bisect | built-in | Binary search commit history | Narrow to specific commit that introduced regression |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Xcode GPU Capture | RenderDoc | RenderDoc doesn't support Metal on macOS, Xcode is native |
| Manual observation | Automated test harness | Automation catches intermittent issues, but requires upfront setup |
| Full revert | Targeted rollback | Full revert loses all v1.6 gains, targeted preserves wins |

**Installation:**
```bash
# Xcode Metal Debugger: included with Xcode
# Profile mode: v -d profile run examples/stress_demo.v
# No external tools required for initial diagnosis
```

## Architecture Patterns

### Pattern 1: Binary Search with Kill Switches
**What:** Use async_uploads flag and git bisect to narrow suspect code
**When to use:** First phase of diagnosis before instrumentation
**Example:**
```v oksyntax
// Test sync vs async path
app.ts.set_async_uploads(false) // Disable async to isolate

// If symptoms disappear with sync:
//   Root cause is in async buffer swap/upload logic (Phase 27)
// If symptoms persist with sync:
//   Root cause is in shelf packing or other Phase 26/28 changes
```

### Pattern 2: Frame Capture at Symptom
**What:** Use Xcode GPU capture when symptom occurs to snapshot GPU state
**When to use:** After isolating suspect subsystem, before code changes
**Steps:**
1. Run stress_demo under Xcode
2. Enable GPU Frame Capture (Xcode > Debug > Graphics > Capture GPU Frame)
3. Trigger symptom (rapid scroll, resize)
4. Capture frame showing artifact
5. Inspect texture contents, draw calls, buffer uploads

### Pattern 3: Instrumentation for State Tracking
**What:** Add temporary logging to capture buffer state across frames
**When to use:** When frame capture shows inconsistent texture state
**Example:**
```v oksyntax
// In renderer.v commit()
$if diag ? {
	for i, page in renderer.atlas.pages {
		if page.dirty {
			eprintln('Frame ${renderer.atlas.frame_counter}: Page ${i} swap, ' +
				'front[0..4]=${page.staging_front[..4]}, ' + 'back[0..4]=${page.staging_back[..4]}')
		}
	}
}
```

### Pattern 4: Reproducible Stress Scenarios
**What:** Create deterministic test that reliably triggers symptom
**When to use:** Essential for verifying fix after root cause identified
**Example:**
```v oksyntax
// Automated scroll stress in stress_demo
fn stress_scroll(mut app AppStress) {
	// Rapid scroll pattern: 0 -> max -> 0 over N frames
	if app.frame_count % 100 == 0 {
		app.scroll_y = if app.scroll_y == 0 { app.max_scroll } else { 0 }
	}
}
```

### Anti-Patterns to Avoid
- **Random code changes without diagnosis:** Wastes time, may introduce new bugs
- **Testing only in release mode:** Intermittent bugs may vanish with optimizations
- **Single frame observation:** Need multi-frame sequences to detect timing issues
- **Ignoring LRU eviction:** Atlas reset can cause blank regions if cache invalidation incomplete

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GPU frame capture | Custom screenshot tool | Xcode Metal Debugger | Official tool captures full GPU state (textures, buffers, shaders, draw calls) |
| Stress testing | Manual scroll testing | Automated scroll loop | Catches intermittent issues humans miss |
| Performance measurement | println timestamps | ProfileMetrics API | Structured, zero-cost when not profiling |
| Commit bisection | Manual checkout loop | git bisect | Logarithmic search vs linear, built-in automation |

**Key insight:** GPU debugging requires specialized tools that inspect GPU-side state. CPU-side
logging alone misses synchronization issues between CPU uploads and GPU reads.

## Common Pitfalls

### Pitfall 1: Race Condition Between Swap and Upload
**What goes wrong:** CPU swaps buffers (staging_front <-> staging_back) while GPU still reading
from old staging_front
**Why it happens:** No explicit synchronization between swap_staging_buffers() and GPU command
completion
**How to avoid:** Verify Metal's implicit synchronization guarantees, check if semaphore needed
**Warning signs:** Flickering is intermittent (timing-dependent), appears during rapid scroll
(high frame rate), disappears when async disabled

### Pitfall 2: Stale Data After Atlas Reset
**What goes wrong:** reset_page() zeros staging buffers, but glyphs referencing old page
positions render blank
**Why it happens:** Cache invalidation only deletes keys for reset page, but if frame has pending
draws using those coords, they read zeroed texture
**How to avoid:** Ensure commit() called AFTER cache invalidation, verify all pending draws
flushed before reset
**Warning signs:** Blank regions appear suddenly after sustained scrolling (LRU eviction
triggered), fixed by redrawing frame

### Pitfall 3: Partial Buffer Swap
**What goes wrong:** swap_staging_buffers() exchanges pointers but dirty flag not synchronized
**Why it happens:** dirty=true set on staging_back write, but not checked after swap
**How to avoid:** Verify dirty flag behavior across swap, ensure upload triggered for swapped front
**Warning signs:** Some glyphs render, others blank (partial upload), timing-dependent

### Pitfall 4: GPU Upload Heap Synchronization
**What goes wrong:** MTLTexture.replaceRegion returns before GPU has consumed data, next frame's
CPU write corrupts in-flight upload
**Why it happens:** Metal API is async, CPU-side return ≠ GPU-side completion
**How to avoid:** Review Metal documentation on managed vs shared storage modes, verify
synchronize(resource:) not needed
**Warning signs:** Garbage pixels in texture, not consistent black (suggests partial write),
worse at high frame rates

### Pitfall 5: Viewport Culling with Stale Atlas
**What goes wrong:** stress_demo culls off-screen glyphs, but when scrolling back, atlas pages
were reset, glyphs now blank
**Why it happens:** LRU assumes glyphs stay in atlas until explicitly evicted, but rapid scroll
causes thrashing
**How to avoid:** Track atlas resets, force redraw when reset_occurred flag true
**Warning signs:** Blank regions at previously-rendered scroll positions, resolved by scrolling
away and back

## Code Examples

Verified patterns from VGlyph codebase and Metal documentation:

### Diagnosis: Isolate Async vs Sync Path
```v oksyntax
// In stress_demo.v main()
fn main() {
	mut app := &AppStress{}
	// Test with async disabled to isolate Phase 27 changes
	$if diag_sync ? {
		app.ts.set_async_uploads(false) // Forces sync fallback in renderer.v:113
	}
	app.ctx.run()
}

// Run: v -d diag_sync run examples/stress_demo.v
// If symptoms vanish: root cause in async path (renderer.v:128-134)
// If symptoms persist: root cause elsewhere (Phase 26 shelf packing)
```

### Diagnosis: Capture Swap State
```v oksyntax
// In glyph_atlas.v swap_staging_buffers()
fn (mut page AtlasPage) swap_staging_buffers() {
	$if diag ? {
		// Capture pre-swap state
		front_sample := page.staging_front[..4]
		back_sample := page.staging_back[..4]
		eprintln('PRE-SWAP: front=${front_sample} back=${back_sample}')
	}
	tmp := page.staging_front
	page.staging_front = page.staging_back
	page.staging_back = tmp
	$if diag ? {
		// Verify post-swap
		eprintln('POST-SWAP: front=${page.staging_front[..4]} back=${page.staging_back[..4]}')
	}
}
```

### Diagnosis: Track Atlas Reset Cascade
```v oksyntax
// In renderer.v draw_layout()
pub fn (mut renderer Renderer) draw_layout(layout Layout, x f32, y f32) {
	// ... existing code ...

	cached, reset, reset_page := renderer.atlas.insert_bitmap(bitmap, left, top)!

	if reset {
		$if diag ? {
			eprintln('ATLAS RESET: page=${reset_page} frame=${renderer.atlas.frame_counter}')
			eprintln('  Cache size before: ${renderer.cache.len}')
		}

		// Invalidate cache for reset page
		for key, c in renderer.cache {
			if c.page == reset_page {
				renderer.cache.delete(key)
			}
		}

		$if diag ? {
			eprintln('  Cache size after: ${renderer.cache.len}')
		}
	}
}
```

### Reproduction: Automated Stress Scroll
```v oksyntax
// In stress_demo.v, add stress mode
struct AppStress {
mut:
	ctx         &gg.Context        = unsafe { nil }
	ts          &vglyph.TextSystem = unsafe { nil }
	scroll_y    f32
	max_scroll  f32
	stress_mode bool // NEW: enable automated stress testing
}

fn frame(mut app AppStress) {
	// ... existing rendering code ...

	// Automated rapid scroll for reproduction
	$if stress ? {
		if app.frame_count % 10 == 0 { // Toggle every 10 frames
			app.scroll_y = if app.scroll_y < app.max_scroll / 2 {
				app.max_scroll // Jump to bottom
			} else {
				0 // Jump to top
			}
		}
	}
}

// Run: v -d stress run examples/stress_demo.v
// Produces rapid scroll thrashing to trigger LRU eviction
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single staging buffer | Double-buffered staging | Phase 27 (2026-02-05) | Enabled CPU/GPU overlap, but introduced swap timing as failure mode |
| Row packing | Shelf best-height-fit | Phase 26 (2026-02-05) | Improved utilization 70% → 75%, changed allocation patterns |
| Manual testing | stress_validation profiling | Phase 28 (2026-02-05) | Three-pass measurement, identified 92.3% LayoutCache hit rate |
| Sync texture uploads | Async with kill switch | Phase 27 (2026-02-05) | Performance gain, but adds complexity to diagnosis |

**Deprecated/outdated:**
- Single buffer texture uploads: Replaced by double-buffered staging (renderer.v:128-134)
- Fixed 1024x1024 atlas: Now grows to 4096 with multi-page support (glyph_atlas.v:68)

## Open Questions

1. **Metal's implicit synchronization guarantees**
   - What we know: MTLTexture.replaceRegion is async, returns before GPU consumes data
   - What's unclear: Does Metal automatically synchronize between frames, or do we need explicit
     semaphore?
   - Recommendation: Test with Metal Frame Debugger, add semaphore if flickering
     timing-correlated with frame boundaries

2. **Swap happens while GPU reading?**
   - What we know: swap_staging_buffers() is CPU-only pointer exchange (glyph_atlas.v:759-763)
   - What's unclear: Is GPU still reading staging_front when swap occurs?
   - Recommendation: Add instrumentation to log swap timing relative to commit, GPU upload, draw

3. **Cache invalidation timing**
   - What we know: reset_page() triggers cache.delete() for affected page (renderer.v:328-332)
   - What's unclear: Are there pending draw calls queued before invalidation that now reference
     stale coords?
   - Recommendation: Force commit() before any atlas reset to flush pending draws

4. **LRU eviction threshold**
   - What we know: 4 pages max, oldest page reset when all full (glyph_atlas.v:599-606)
   - What's unclear: Does stress_demo's 6000 glyphs + rapid scroll exceed 4-page capacity?
   - Recommendation: Log atlas_resets during stress test, correlate with blank region timestamps

## Sources

### Primary (HIGH confidence)
- VGlyph codebase: glyph_atlas.v, renderer.v, stress_demo.v (Phase 26-28 implementation)
- Phase 27 Verification: .planning/phases/27-async-texture-updates/27-VERIFICATION.md
- v1.6 Milestone Summary: .planning/milestones/v1.6-ROADMAP.md
- ProfileMetrics API: context.v:56-135, api.v:521-572

### Secondary (MEDIUM confidence)
- [Xcode Metal Debugger](https://developer.apple.com/documentation/xcode/metal-debugger) - Official Apple GPU debugging
- [Capturing Metal workload](https://developer.apple.com/documentation/xcode/capturing-a-metal-workload-in-xcode) - Frame capture workflow
- [Sokol Metal backend](https://floooh.github.io/2020/02/20/sokol-gfx-backend-tour-metal.html) - Tick-tock sync model
- [Metal synchronization](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/synchronize(resource:)) - Resource sync API
- [GPU upload heap synchronization](https://developer.apple.com/forums/thread/110024) - Metal async guarantees

### Tertiary (LOW confidence)
- [GPU texture flickering patterns](https://copyprogramming.com/howto/opengl-and-flickering) - General debugging strategies
- [Double buffer synchronization](https://vkguide.dev/docs/chapter-4/double_buffering/) - Vulkan patterns (similar to Metal)
- [Race condition debugging](https://undo.io/resources/debugging-race-conditions-cpp/) - General concurrency issues
- [GPU stress testing methodology](https://overclock3d.net/news/misc/why-occt-has-changed-gpu-stress-testing-and-why-furmarks-no-longer-good-enough/) - Variable load testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Tools are built-in (Xcode, V profile mode, existing demos)
- Architecture: HIGH - Patterns verified in codebase, aligned with Metal best practices
- Pitfalls: MEDIUM - Based on code analysis + GPU debugging literature, not empirically verified
  on this codebase

**Research date:** 2026-02-05
**Valid until:** 30 days (stable domain, unlikely Metal APIs change)

**Key unknowns requiring empirical testing:**
- Exact timing of swap relative to GPU upload completion
- Whether Metal's implicit synchronization sufficient or explicit semaphore needed
- Correlation between atlas_resets and blank regions in stress_demo
- Whether flickering frequency matches frame rate (suggests GPU timing issue)