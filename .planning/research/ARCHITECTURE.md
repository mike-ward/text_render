# Performance Profiling Architecture

**Domain:** Text rendering with Pango/FreeType/OpenGL
**Researched:** 2026-02-02
**Confidence:** HIGH (V language conditional compilation verified, profiling patterns established)

## Executive Summary

VGlyph's architecture has four primary hot paths: Layout computation (Pango shaping), Atlas
operations (FreeType rasterization + texture uploads), Render path (OpenGL draw calls), and Cache
management. Profiling integration requires zero release overhead via V's `$if debug {}` pattern,
metrics collection at component boundaries, and optimization order driven by data flow dependencies.

**Zero-overhead approach:** V's conditional compilation (`$if debug {}`, `-d profile`) removes
instrumentation code entirely in release builds at compile time. No runtime checks, no function
call overhead.

## Existing Architecture (v1.1)

### Component Structure

```
Context (Pango/FreeType) → Layout (shaping) → Renderer (OpenGL)
                                    ↓
                               GlyphAtlas (texture management)
```

| Component | Responsibility | Performance Characteristics |
|-----------|---------------|----------------------------|
| Context | Pango/FreeType initialization, font loading | One-time cost (init), per-layout (font resolution) |
| Layout | Text shaping via Pango, glyph extraction, hit-test rects | Expensive (O(n) text length), cached by user code |
| GlyphAtlas | Texture atlas allocation, shelf packing, grow/reset | Amortized O(1) insert, expensive on grow |
| Renderer | Glyph cache lookup, FreeType rasterization, OpenGL draw | Hot path (per frame), cache-sensitive |

### Data Flow

```
1. User calls ctx.layout_text() → Pango shaping → Layout struct
2. User calls renderer.draw_layout() → FOR EACH Item:
   a. get_or_load_glyph() → cache miss? → load_glyph() → FreeType + atlas.insert_bitmap()
   b. ctx.draw_image_with_config() → queued draw call
3. renderer.commit() → atlas.dirty? → update_pixel_data() (GPU upload)
```

**Bottleneck hypothesis** (from code inspection):
- Layout: Pango iteration (O(n)), char_rects computation (O(n²) with pango_layout_index_to_pos)
- Atlas: FreeType rasterization (per-glyph), texture upload (per commit), grow() reallocation
- Render: Cache hash computation, draw call batching (gg handles this)

## Zero-Overhead Instrumentation Strategy

### V Language Conditional Compilation

V provides compile-time conditional code removal via:

```v
$if debug {
    // Code here removed entirely in release builds (no runtime cost)
}

$if profile ? {
    // Code here enabled only with -d profile flag
}
```

**Key insight:** V will type-check code inside conditionals but NOT compile it into final executable
unless flag is passed. This achieves true zero overhead (not "low overhead").

Sources:
- [V Conditional Compilation](https://docs.vlang.io/conditional-compilation.html)
- [V Performance Tuning](https://docs.vlang.io/performance-tuning.html)

### Instrumentation Pattern

```v
// Define metrics struct (always compiled, zero-cost if unused)
pub struct ProfileMetrics {
pub mut:
    layout_time_us       i64
    rasterize_time_us    i64
    atlas_upload_time_us i64
    draw_calls           int
    cache_hits           int
    cache_misses         int
}

// Collection macro (removed in release)
$if profile ? {
    mut start := time.ticks()
    // ... operation ...
    metrics.layout_time_us += time.ticks() - start
}
```

**Build modes:**
- Release: `v -prod main.v` → all `$if profile ?` code removed
- Profile: `v -d profile main.v` → instrumentation enabled
- Debug: `v -g main.v` → debug symbols, validation guards

### Overhead Characteristics

| Approach | Release Overhead | Profile Overhead | Precedent |
|----------|-----------------|------------------|-----------|
| V `$if profile ?` | 0% (code removed) | ~5% (time.ticks() calls) | Rust metrics crate, hotpath-rs |
| Runtime flag check | ~2-3% (branch per call) | ~5-8% | Industry standard |
| Function pointers | ~1-2% (indirect call) | ~5-8% | C profiling hooks |

**Recommendation:** V conditional compilation with `-d profile` flag.

## Integration Points

### 1. Layout Computation (layout.v)

**Current hot path:** `ctx.layout_text()` → Pango shaping → `build_layout_from_pango()`

**Instrumentation locations:**

```v
pub fn (mut ctx Context) layout_text(text string, cfg TextConfig) !Layout {
    $if profile ? {
        start := time.ticks()
        defer { ctx.metrics.layout_time_us += time.ticks() - start }
    }

    // Existing code...
    layout := setup_pango_layout(mut ctx, text, cfg)!

    $if profile ? {
        ctx.metrics.pango_setup_us += time.since(start)
    }

    return build_layout_from_pango(layout, text, ctx.scale_factor, cfg)
}
```

**Metrics to collect:**
- `pango_setup_time_us` — PangoLayout creation + configuration
- `pango_iterate_time_us` — Iterator traversal (process_run loop)
- `hit_test_rects_time_us` — compute_hit_test_rects (O(n²) suspect)
- `layout_count` — Layouts created (for cache hit rate estimation)

**Why here:** Layout is expensive (Pango shaping, HarfBuzz complex scripts), called once per text
change, rarely in hot loop but can cause frame drops if called on input events.

### 2. Atlas Operations (glyph_atlas.v)

**Current hot paths:**
- `insert_bitmap()` — Shelf packing + memcpy
- `grow()` — Realloc + copy old data
- FreeType rasterization (in renderer.v but conceptually atlas concern)

**Instrumentation locations:**

```v
pub fn (mut atlas GlyphAtlas) insert_bitmap(bmp Bitmap, left int, top int) !(CachedGlyph, bool) {
    $if profile ? {
        atlas.metrics.insert_calls++
        start := time.ticks()
        defer { atlas.metrics.insert_time_us += time.ticks() - start }
    }

    // Existing packing logic...

    $if profile ? {
        if reset_occurred {
            atlas.metrics.reset_count++
        }
    }

    copy_bitmap_to_atlas(mut atlas, bmp, atlas.cursor_x, atlas.cursor_y)
    // ...
}

pub fn (mut atlas GlyphAtlas) grow(new_height int) ! {
    $if profile ? {
        start := time.ticks()
        atlas.metrics.grow_count++
        defer { atlas.metrics.grow_time_us += time.ticks() - start }
    }

    // Existing grow logic...
}
```

**Metrics to collect:**
- `insert_time_us` — Time spent in insert_bitmap (shelf packing + memcpy)
- `grow_time_us` — Time spent in grow (realloc + copy)
- `reset_count` — Atlas full, reset occurred (invalidates all UVs)
- `grow_count` — Atlas height doubled
- `atlas_utilization` — cursor_y / height (percentage full)

**Why here:** Atlas operations are amortized O(1) but have spiky cost on grow. Resets cause cache
invalidation cascade. Texture uploads (in commit) are expensive on some GPUs.

### 3. Renderer Operations (renderer.v)

**Current hot paths:**
- `draw_layout()` — Cache lookups, draw call queueing
- `get_or_load_glyph()` — Cache miss → load_glyph() → FreeType + atlas
- `commit()` — GPU texture upload

**Instrumentation locations:**

```v
pub fn (mut renderer Renderer) draw_layout(layout Layout, x f32, y f32) {
    $if profile ? {
        start := time.ticks()
        frame_cache_hits := 0
        frame_cache_misses := 0
        defer {
            renderer.metrics.draw_time_us += time.ticks() - start
            renderer.metrics.cache_hits += frame_cache_hits
            renderer.metrics.cache_misses += frame_cache_misses
        }
    }

    for item in layout.items {
        for i := item.glyph_start; i < item.glyph_start + item.glyph_count; i++ {
            cg := renderer.get_or_load_glyph(item, glyph, bin) or { CachedGlyph{} }

            $if profile ? {
                if key in renderer.cache { frame_cache_hits++ } else { frame_cache_misses++ }
            }
        }
    }
}

fn (mut renderer Renderer) load_glyph(cfg LoadGlyphConfig) !CachedGlyph {
    $if profile ? {
        start := time.ticks()
        defer { renderer.metrics.rasterize_time_us += time.ticks() - start }
    }

    // FreeType calls...
}

pub fn (mut renderer Renderer) commit() {
    $if profile ? {
        start := time.ticks()
        defer { renderer.metrics.commit_time_us += time.ticks() - start }
    }

    if renderer.atlas.dirty {
        $if profile ? {
            upload_start := time.ticks()
        }

        renderer.atlas.image.update_pixel_data(renderer.atlas.image.data)

        $if profile ? {
            renderer.metrics.upload_time_us += time.ticks() - upload_start
            renderer.metrics.upload_count++
        }
    }
}
```

**Metrics to collect:**
- `draw_time_us` — Total time in draw_layout (includes cache lookups)
- `rasterize_time_us` — FreeType bitmap conversion (per cache miss)
- `commit_time_us` — Time in commit (includes upload if dirty)
- `upload_time_us` — GPU texture upload only
- `upload_count` — Number of uploads per frame
- `cache_hit_rate` — hits / (hits + misses)
- `draw_calls` — Items drawn (proxy for OpenGL calls)

**Why here:** Render path is per-frame hot loop. Cache misses trigger expensive FreeType
rasterization. Texture uploads are "terribly expensive on some configurations" (per WebRender
research).

### 4. Context Operations (context.v)

**Current operations:**
- `new_context()` — One-time init (not hot path)
- `font_height()` — Pango metrics lookup (per-font, cacheable)
- `layout_text()` — Delegates to layout.v

**Instrumentation locations:**

```v
pub fn (mut ctx Context) font_height(cfg TextConfig) f32 {
    $if profile ? {
        start := time.ticks()
        defer { ctx.metrics.font_query_time_us += time.ticks() - start }
    }

    // Existing Pango font loading...
}
```

**Metrics to collect:**
- `font_query_time_us` — Time spent in font_height/font_metrics
- `font_query_count` — Number of font metric queries (should be cacheable)

**Why here:** Font metrics queries can be expensive if not cached. Profiling reveals if
user-facing API caching is needed.

## Metrics Collection Architecture

### Metrics Struct Hierarchy

```v
// Global metrics container (owned by Context or Renderer)
pub struct VGlyphMetrics {
pub mut:
    // Layout metrics
    layout_time_us       i64
    pango_setup_us       i64
    pango_iterate_us     i64
    hit_test_rects_us    i64
    layout_count         int

    // Atlas metrics
    insert_time_us       i64
    grow_time_us         i64
    grow_count           int
    reset_count          int
    atlas_utilization    f32

    // Render metrics
    draw_time_us         i64
    rasterize_time_us    i64
    commit_time_us       i64
    upload_time_us       i64
    upload_count         int
    cache_hits           int
    cache_misses         int
    draw_calls           int

    // Context metrics
    font_query_time_us   i64
    font_query_count     int
}

// Per-frame snapshot (for profiler output)
pub struct FrameMetrics {
pub:
    frame_number         u64
    frame_time_us        i64
    layout_time_us       i64
    draw_time_us         i64
    cache_hit_rate       f32
    atlas_utilization    f32
}
```

### Collection Pattern

```v
// In Context
pub struct Context {
    // ... existing fields ...
    $if profile ? {
        pub mut:
            metrics VGlyphMetrics
    }
}

// User-facing API (only available with -d profile)
$if profile ? {
    pub fn (ctx Context) get_metrics() VGlyphMetrics {
        return ctx.metrics
    }

    pub fn (mut ctx Context) reset_metrics() {
        ctx.metrics = VGlyphMetrics{}
    }
}
```

**Key design:** Metrics struct always compiled (zero cost if unused), but collection code removed
in release builds.

## Optimization Order (Data-Driven)

### Phase 1: Measure (Profile Build)

**Goal:** Establish baseline, identify bottlenecks

**Tasks:**
1. Add instrumentation to all four hot paths
2. Build with `-d profile` flag
3. Run representative workload (e.g., examples/stress_demo.v)
4. Collect metrics, compute percentages

**Deliverable:** Metrics showing time distribution across components

### Phase 2: Analyze

**Goal:** Interpret metrics, prioritize optimizations

**Decision tree:**

```
IF layout_time_us > 40% of total:
  → Investigate Pango caching (PangoLayout reuse?)
  → Profile hit_test_rects (O(n²) suspect)

IF rasterize_time_us > 30% of total:
  → Check cache_hit_rate (should be >95% after warmup)
  → Investigate FreeType load flags (target mode, render mode)

IF upload_time_us > 20% of total:
  → Reduce upload frequency (defer until flush?)
  → Investigate partial texture updates (GL_TEXTURE_SUB_IMAGE_2D)

IF draw_time_us - rasterize_time_us > 30%:
  → Profile cache hash computation (u64 key calculation)
  → Investigate draw call batching (gg internals)
```

**Precedent:** Mozilla WebRender optimized atlas allocation (8×16, 16×32 slab sizes), reduced
region sizes (512→128), improved packing efficiency by ~30%.

### Phase 3: Optimize (Targeted)

**Goal:** Apply data-driven optimizations

**Optimization candidates** (ranked by likelihood):

| Optimization | Target | Expected Gain | Risk |
|--------------|--------|---------------|------|
| Layout cache reuse | layout.v | 20-40% (if text repeats) | Low (user API) |
| Hit-test on-demand | layout.v | 10-20% (if unused) | Low (cfg flag) |
| FreeType target flags | renderer.v | 5-15% (load mode) | Low (existing) |
| Atlas slab sizes | glyph_atlas.v | 10-20% (packing) | Medium (algo change) |
| Partial texture upload | renderer.v | 15-30% (GPU bound) | Medium (OpenGL API) |
| Cache key precompute | renderer.v | 5-10% (hot loop) | Low (cached in Item) |

**Non-optimization:** Don't optimize draw call batching — gg.Context handles this internally.

### Phase 4: Validate

**Goal:** Confirm optimizations effective, no regressions

**Tasks:**
1. Re-run profile with optimizations
2. Compare metrics (before/after)
3. Check visual correctness (screenshot diff)
4. Measure release build impact (should be 0%)

**Deliverable:** Performance report with before/after metrics

## Architecture Patterns for Profiling

### Pattern 1: Metrics Struct Co-location

**Problem:** Metrics scattered across files, hard to aggregate

**Solution:** Single metrics struct owned by Context, passed by reference

```v
pub struct Context {
    // ... existing ...
    $if profile ? {
        pub mut:
            metrics VGlyphMetrics
    }
}

pub fn (mut ctx Context) layout_text(...) !Layout {
    $if profile ? {
        profile_layout(mut ctx.metrics, || {
            // ... actual work ...
        })
    }
}
```

**Benefit:** Centralized metrics, easy to query/reset

### Pattern 2: Defer-based Timing

**Problem:** Manual start/end time tracking error-prone (early return misses end)

**Solution:** Defer ensures timing capture even on error paths

```v
$if profile ? {
    start := time.ticks()
    defer { metrics.layout_time_us += time.ticks() - start }
}
// ... operation that might return early ...
```

**Benefit:** Accurate timing even with `!` error returns

### Pattern 3: Scoped Counters

**Problem:** Cache hit/miss tracking requires logic in multiple places

**Solution:** Accumulate in local vars, update metrics in defer

```v
$if profile ? {
    mut frame_hits := 0
    mut frame_misses := 0
    defer {
        metrics.cache_hits += frame_hits
        metrics.cache_misses += frame_misses
    }
}

// In loop:
if key in cache { frame_hits++ } else { frame_misses++ }
```

**Benefit:** Minimal hot-path overhead (local vars), atomic metrics update

### Pattern 4: Conditional API Surface

**Problem:** Metrics API pollutes public interface when profiling disabled

**Solution:** Entire API behind `$if profile ?`

```v
$if profile ? {
    pub fn (ctx Context) get_metrics() VGlyphMetrics { ... }
    pub fn (mut ctx Context) reset_metrics() { ... }
    pub fn (ctx Context) print_metrics() { ... }
}
```

**Benefit:** Clean API in release, no dead code warnings

## Anti-Patterns to Avoid

### Anti-Pattern 1: Runtime Flag Checks

**Bad:**
```v
pub struct Context {
    profile_enabled bool
}

if ctx.profile_enabled {
    start := time.ticks()
}
```

**Why bad:** Branch in hot path, ~2-3% overhead in release builds

**Instead:** Use `$if profile ?` for compile-time removal

### Anti-Pattern 2: Excessive Granularity

**Bad:**
```v
$if profile ? {
    start := time.ticks()
}
// Single line of work
$if profile ? {
    metrics.tiny_op_us += time.ticks() - start
}
```

**Why bad:** time.ticks() overhead (~100-500ns) dominates actual work

**Instead:** Profile at function granularity, not per-line

### Anti-Pattern 3: Blocking I/O in Hot Path

**Bad:**
```v
$if profile ? {
    mut f := os.create('profile.log')!
    f.writeln('draw_time: ${time_us}')
    f.close()
}
```

**Why bad:** File I/O in draw loop kills frame rate

**Instead:** Accumulate metrics in memory, flush on shutdown or explicit call

### Anti-Pattern 4: Metrics in Struct Fields (Non-Conditional)

**Bad:**
```v
pub struct GlyphAtlas {
    // ... existing ...
    metrics AtlasMetrics // Always present
}
```

**Why bad:** Memory overhead in release builds (struct size increase)

**Instead:** Metrics only in Context, behind `$if profile ?`

## Build Integration

### Compilation Commands

```bash
# Release build (production, zero profiling overhead)
v -prod -o vglyph_release main.v

# Profile build (instrumentation enabled)
v -d profile -o vglyph_profile main.v

# Debug build (validation guards, debug symbols)
v -g -o vglyph_debug main.v

# Profile + Debug (full instrumentation + validation)
v -g -d profile -o vglyph_profile_debug main.v
```

### CI/CD Integration

```yaml
# .github/workflows/perf.yml
- name: Build Profile Binary
  run: v -d profile -o vglyph_profile examples/stress_demo.v

- name: Run Profiling
  run: ./vglyph_profile > metrics.txt

- name: Parse Metrics
  run: python scripts/parse_metrics.py metrics.txt

- name: Compare Baseline
  run: python scripts/compare_perf.py metrics.txt baseline.txt
```

**Goal:** Catch performance regressions in CI

## Precedents and Sources

### Zero-Overhead Profiling

- V language conditional compilation removes code at compile time with `-d` flags
  ([V Docs](https://docs.vlang.io/conditional-compilation.html))
- Rust `metrics` crate: "incredibly low overhead when no global recorder installed - just atomic
  load and comparison" ([docs.rs](https://docs.rs/metrics))
- `hotpath-rs`: "zero-cost when disabled through feature flags, no compile time or runtime overhead"
  ([GitHub](https://github.com/pawurb/hotpath-rs))

### Text Rendering Optimization

- Mozilla WebRender atlas optimization: specialized slab sizes (8×16, 16×32), reduced region sizes
  (512→128) for ~30% packing improvement
  ([Mozilla Blog](https://mozillaggfx.wordpress.com/2021/02/04/improving-texture-atlas-allocation-in-webrender/))
- Warp terminal glyph atlas: lazy rasterization, LRU eviction reduces GPU memory
  ([Warp Blog](https://www.warp.dev/blog/adventures-text-rendering-kerning-glyph-atlases))
- LLVM BOLT for Pango: post-link optimization net ~6% improvement
  ([Phoronix](https://www.phoronix.com/forums/forum/phoronix/latest-phoronix-articles/1451706-llvm-bolt-optimizations-net-~6-improvement-for-gnome-s-pango))

### OpenGL Performance

- "Texture uploads terribly expensive on some configurations" (WebRender research)
- Minimize state changes (texture binds, shader switches, blend mode) for batching
  ([LearnOpenGL](https://learnopengl.com/In-Practice/Text-Rendering))
- Frame time > FPS as metric (non-linear time domain)
  ([OpenGL Wiki](https://www.khronos.org/opengl/wiki/performance))

### Draw Call Optimization

- For 60 FPS (16.67ms budget): rendering <5ms main thread, <16ms render thread
  ([ARM Developer](https://developer.arm.com/documentation/101897/latest/Optimizing-application-logic/Draw-call-batching-best-practices))
- Texture atlasing + material sharing = more batches
  ([Unity Docs](https://docs.unity3d.com/Manual/DrawCallBatching.html))

## Confidence Assessment

| Area | Confidence | Rationale |
|------|-----------|-----------|
| V conditional compilation | HIGH | Official V docs, verified `-d` flag behavior |
| Profiling patterns | HIGH | Rust precedents (metrics, hotpath-rs), industry standard |
| Hot path identification | HIGH | Code inspection + data flow analysis |
| Optimization order | MEDIUM | Requires real profiling data to confirm bottlenecks |
| Expected gains | MEDIUM | Based on precedents (WebRender, Pango BOLT) |

## Open Questions

1. **Layout cache reuse:** Does user code already cache Layout objects? If not, API-level caching
   in Context could yield 20-40% gains.
2. **Hit-test necessity:** Are char_rects used in all scenarios? On-demand flag (cfg.no_hit_testing
   already exists) could skip O(n²) work.
3. **gg.Context batching:** How does gg batch draw_image_with_config calls? Is batching automatic
   or does it require flush control?
4. **Atlas utilization target:** What's acceptable atlas utilization before grow? 80%? 90%? Affects
   grow frequency.

## Roadmap Implications

### Suggested Phase Structure

**Phase 1: Instrumentation (1 week)**
- Add metrics struct to Context
- Instrument layout.v, glyph_atlas.v, renderer.v
- Build with `-d profile`, run stress test
- Deliverable: Baseline metrics report

**Phase 2: Analysis (2-3 days)**
- Identify bottleneck (layout/atlas/render)
- Prioritize optimizations by expected ROI
- Deliverable: Optimization plan ranked by impact

**Phase 3: Optimization (1-2 weeks, iterative)**
- Implement top 2-3 optimizations
- Re-profile after each change
- Validate visual correctness
- Deliverable: Performance improvement report

**Phase 4: Validation (2-3 days)**
- Release build size check (should be unchanged)
- Benchmark suite (before/after)
- CI integration for regression detection
- Deliverable: CI performance tests

**Total estimated time:** 3-4 weeks for full cycle

### Research Flags

- **Phase 2 (Analysis):** May need deeper Pango profiling if layout is bottleneck. Pango internals
  not well-documented for optimization.
- **Phase 3 (Optimization):** Atlas algorithm changes (slab sizes, packing) require careful testing
  (visual regression risk).
- **Phase 4 (Validation):** OpenGL partial texture upload API may vary by platform (macOS/Linux).

## Summary

VGlyph's performance profiling should integrate via V's `$if profile ?` conditional compilation for
true zero release overhead. Instrumentation points: Layout (Pango shaping), Atlas (rasterization +
uploads), Renderer (cache + draw calls). Metrics collected at component boundaries, aggregated in
Context.metrics. Optimization order data-driven: measure → analyze → optimize → validate. Expected
bottlenecks: Layout (if not cached), Atlas uploads (GPU-bound), Cache misses (FreeType expensive).

**Key architectural decision:** Metrics struct always compiled (zero cost), collection code removed
in release. V's defer pattern ensures accurate timing even with early returns. No runtime overhead
in production builds.
