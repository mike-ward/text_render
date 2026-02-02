# Performance Profiling & Optimization Stack

**Project:** VGlyph v1.2
**Focus:** Lightweight profiling instrumentation for text rendering bottlenecks
**Researched:** 2026-02-02
**Confidence:** HIGH

## Executive Summary

VGlyph requires minimal stack additions for profiling. V's built-in `-profile` flag and
`benchmark`/`time` modules provide sufficient instrumentation. No external profilers needed.
Focus on manual instrumentation at critical paths identified in CONCERNS.md.

## Recommended Profiling Stack

### Primary: V Built-in Tools (Use These)

| Tool | Purpose | When to Use | Integration |
|------|---------|-------------|-------------|
| `v -profile` | Function-level profiling | Whole-program bottleneck discovery | Compile-time flag |
| `benchmark` module | Micro-benchmarks | Measure specific hot paths | Import in code |
| `time.StopWatch` | Manual instrumentation | Critical path timing | Inline at bottlenecks |

**Rationale:** V provides native profiling without dependencies. Matches project's lightweight ethos.

### V Language Built-in Profiling

**Primary Tool:** `v -profile profile.txt x.v && ./x`

**Output Format:**
```
<calls> <total_ms> <avg_ns> <function_name>
127 0.721ms 5680ns println
127 0.693ms 5456ns _writeln_to_fd
```

**Capabilities:**
- Per-function call counts, total time, average time
- Selective profiling: `-profile-fns func1,func2`
- Skip inline functions: `-profile-no-inline`
- Runtime control: `import v.profile; profile.on(false)` to toggle mid-execution
- Exclude startup: `-d no_profile_startup`

**Limitations:**
- Not thread-safe (acceptable - V/VGlyph are single-threaded)
- Adds overhead (~5-10% typical for instrumented builds)

**Source:** [V Documentation - Tools](https://docs.vlang.io/tools.html)

### Manual Instrumentation: benchmark Module

**API:**
```v
import benchmark

mut bm := benchmark.start()
// code to measure
bm.measure('operation_name')  // prints immediately
bm.record_measure('op2')      // records for later
println(bm.total_duration())  // ms
```

**Use for:**
- Targeted measurements of suspect functions
- Before/after optimization comparisons
- Regression tests (assert timing thresholds)

**Source:** [V benchmark module](https://modules.vlang.io/benchmark.html)

### High-Resolution Timing: time.StopWatch

**API:**
```v
import time

sw := time.new_stopwatch()
// code
elapsed_ns := sw.elapsed().nanoseconds()
elapsed_ms := sw.elapsed().milliseconds()
```

**Use for:**
- Inline timing at critical bottlenecks
- Sub-millisecond precision measurements
- Collecting timing stats in data structures

**Source:** [V time module](https://modules.vlang.io/time.html)

## Instrumentation Strategy for VGlyph Bottlenecks

Based on CONCERNS.md, instrument these areas:

### 1. Atlas Reset (Critical)

**Bottleneck:** All glyphs invalidated mid-frame on atlas full

**Measurement approach:**
```v
// In glyph_atlas.v
mut reset_count := 0
mut reset_timing := []i64{}

fn (mut ga GlyphAtlas) reset() {
    sw := time.new_stopwatch()
    // existing reset logic
    reset_timing << sw.elapsed().microseconds()
    reset_count++
}
```

**Metrics to track:**
- Reset frequency per frame
- Time spent in reset()
- Number of glyphs invalidated per reset

### 2. Glyph Cache Hash Collisions (High)

**Bottleneck:** No collision detection - wrong glyph returned silently

**Measurement approach:**
```v
// In renderer.v
struct CacheStats {
mut:
    lookups    u64
    hits       u64
    misses     u64
    collisions u64  // NEW: track when hash matches but glyph differs
}

fn (mut r Renderer) get_cached_glyph(key GlyphKey) ?CachedGlyph {
    stats.lookups++
    hash := key.hash()
    if cached := r.cache[hash] {
        if cached.glyph_index == key.glyph_index && cached.subpixel_bin == key.subpixel_bin {
            stats.hits++
            return cached
        } else {
            stats.collisions++  // Hash collision detected
        }
    }
    stats.misses++
    return none
}
```

**Metrics to track:**
- Collision rate (collisions / lookups)
- Cache hit rate
- Histogram of hash distribution

**Fix strategy:** If collision rate > 0.1%, add secondary key validation or switch to
open addressing with linear probing.

**Source:** [Open Addressing Collision Resolution](https://www.geeksforgeeks.org/dsa/open-addressing-collision-handling-technique-in-hashing/)

### 3. FreeType Metrics Recomputation (Moderate)

**Bottleneck:** Underline/strikethrough metrics fetched per run

**Measurement approach:**
```v
// In layout.v
struct MetricsCache {
mut:
    cache map[string]FTMetrics  // key: font_name
    hits  u64
    misses u64
}

fn (mut mc MetricsCache) get_metrics(font_name string) FTMetrics {
    if cached := mc.cache[font_name] {
        mc.hits++
        return cached
    }
    mc.misses++
    sw := time.new_stopwatch()
    metrics := fetch_from_freetype(font_name)
    fetch_time := sw.elapsed().microseconds()
    mc.cache[font_name] = metrics
    return metrics
}
```

**Metrics to track:**
- Cache hit rate
- FreeType FFI call latency
- Total time saved by caching

### 4. Bitmap Scaling (High for Emoji)

**Bottleneck:** Bicubic scaling every frame for color emoji

**Measurement approach:**
```v
// In glyph_atlas.v or bitmap_scaling.v
struct ScalingStats {
mut:
    cpu_scales    u64
    cpu_time_us   i64
    cache_hits    u64
    avg_scale_us  f64
}

fn scale_bitmap_bicubic(src Bitmap, scale f64) Bitmap {
    sw := time.new_stopwatch()
    result := // existing bicubic logic
    stats.cpu_scales++
    stats.cpu_time_us += sw.elapsed().microseconds()
    stats.avg_scale_us = f64(stats.cpu_time_us) / f64(stats.cpu_scales)
    return result
}
```

**Metrics to track:**
- Number of scales per frame
- Average scaling time (target: <100us per emoji)
- Cache effectiveness if scaled bitmap cache added

**Optimization path:**
- Option A: Cache scaled bitmaps (memory cost vs CPU savings)
- Option B: GPU scaling via fragment shader (complexity vs performance)

**Source:** [GPU vs CPU Bitmap Performance](https://journalofcloudcomputing.springeropen.com/articles/10.1186/s13677-020-00191-w) - GPUs show 11.5x average speedup for bitmap operations

## Memory Profiling

V's `-autofree` and GC provide automatic memory management. For VGlyph, manual tracking suffices.

### Atlas Memory Tracking

**Add to GlyphAtlas:**
```v
struct GlyphAtlas {
    // existing fields
mut:
    peak_memory_bytes u64
    current_entries   int
    total_resets      u64
}

fn (ga &GlyphAtlas) memory_report() string {
    bytes := ga.width * ga.height * 4  // RGBA
    return 'Atlas: ${bytes / 1024}KB, entries: ${ga.current_entries}, resets: ${ga.total_resets}'
}
```

### Layout Cache Memory

**Track in TextSystem:**
```v
struct TextSystem {
    // existing fields
mut:
    cache_peak_entries int
    cache_evictions    u64
}
```

**No external heap profilers needed.** V's minimal overhead + manual tracking is sufficient.

## What NOT to Add

### External Profilers (Avoid)

| Tool | Why Not |
|------|---------|
| Valgrind/Massif | V's GC/autofree handles memory; adds 10-50x slowdown |
| perf/Intel VTune | Overkill for library-level profiling; C backend obfuscates V code |
| gperftools | C-focused; V's native tools more ergonomic |

**Exception:** Only consider external GPU profilers (RenderDoc, Nsight) if GPU bottleneck
suspected in atlas upload. Current bottlenecks are CPU-side.

### Heavy Instrumentation Frameworks (Avoid)

| Framework | Why Not |
|-----------|---------|
| Tracy Profiler | Requires integration, visualization overhead; V's text output sufficient |
| Custom telemetry | Premature - profile first, only add if data shows need |

**Principle:** Start lightweight. V's built-in tools cover 95% of needs. Add complexity only
after profiling proves necessity.

## Optimization Compiler Flags

Use after profiling identifies bottlenecks:

### Production Builds

```bash
v -prod vglyph/
```

**What it does:** Enables C compiler optimizations (-O2/-O3 equivalent)

### Aggressive Optimization

```bash
v -prod -cflags "-march=native" vglyph/
```

**What it does:** CPU-specific instructions (SIMD, etc.)
**Risk:** Not portable across CPUs
**Use when:** Performance critical, distribution controlled

### Performance Attributes

**Apply to hot functions after profiling:**

```v
@[inline]
fn hot_function() {
    // frequently called, small function
}

@[direct_array_access]
fn process_buffer(mut buf []byte) {
    // removes bounds checks - VERIFY MANUALLY
    for i in 0 .. buf.len {
        buf[i] = // safe operation
    }
}
```

**Source:** [V Performance Tuning](https://docs.vlang.io/performance-tuning.html)

## Optimization Workflow

### Phase 1: Discover (Use `-profile`)

```bash
v -profile profile.txt examples/stress_demo.v
./stress_demo
sort -n -k3 profile.txt | tail -20  # Top 20 slowest functions by avg time
```

**Identifies:** Which functions consume most time

### Phase 2: Measure (Manual Instrumentation)

Add `benchmark.measure()` or `time.StopWatch` to suspect functions.

**Example:**
```v
import benchmark

fn render_text_layout(...) {
    mut bm := benchmark.start()

    pango_layout_glyphs()
    bm.measure('pango_layout')

    load_glyphs_to_atlas()
    bm.measure('atlas_load')

    upload_to_gpu()
    bm.measure('gpu_upload')
}
```

**Identifies:** Specific bottleneck within function

### Phase 3: Optimize (Targeted Fix)

Apply optimization (cache, algorithm change, etc.) to measured bottleneck.

### Phase 4: Validate (Regression Test)

```v
fn test_render_performance() {
    sw := time.new_stopwatch()
    render_text_layout(test_config)
    elapsed := sw.elapsed().milliseconds()
    assert elapsed < 16, 'Render must complete in <16ms for 60fps'
}
```

**Prevents:** Performance regressions

## LRU Cache Enhancement (For Atlas/Layout Caches)

VGlyph already has layout cache. If atlas needs multi-page with eviction:

### Implementation Strategy

**Data structures:**
```v
struct LRUCache {
mut:
    map       map[u64]&Node  // hash to doubly-linked list node
    head      &Node          // most recently used
    tail      &Node          // least recently used
    capacity  int
    size      int
}

struct Node {
mut:
    key   u64
    value CachedGlyph
    prev  &Node
    next  &Node
}
```

**Operations:** O(1) for get/put/evict using hash map + doubly-linked list

**Source:** [LRU Cache Implementation](https://www.educative.io/blog/implement-least-recently-used-cache)

**Note:** V's `map` already provides efficient hash table. Focus on eviction policy, not hash
implementation.

## GPU Profiling (If Needed)

Current bottlenecks are CPU-side (FreeType, Pango, caching). GPU profiling only if:

1. `-profile` shows GPU calls (commit(), atlas upload) dominating
2. Frame rate drops with GPU-bound symptoms (many draw calls)

**Tools to consider ONLY if GPU-bottlenecked:**

| Tool | Platform | Use Case |
|------|----------|----------|
| RenderDoc | Cross-platform | Inspect OpenGL state, texture uploads |
| NVIDIA Nsight | NVIDIA GPUs | Frame profiling, texture bandwidth analysis |
| apitrace | Cross-platform | Record/replay OpenGL calls |

**Source:** [libGDX Profiling - GPU](https://libgdx.com/wiki/graphics/profiling)

**Current recommendation:** Skip GPU profiling. CPU optimization (caching, collision handling)
will yield bigger wins based on CONCERNS.md.

## Integration Points with Existing Stack

VGlyph's current stack remains unchanged. Profiling additions are purely instrumentation:

### No New Dependencies

| Current | Profiling Addition | Integration |
|---------|-------------------|-------------|
| Pango | `benchmark.measure()` before/after Pango calls | Inline timing |
| FreeType | Metrics cache with hit/miss counters | Wraps existing calls |
| OpenGL/Sokol | `time.StopWatch` around commit() | Non-invasive |

### Conditional Compilation

Use V's conditional compilation to enable/disable profiling:

```v
$if profile ? {
    mut bm := benchmark.start()
    // measured code
    bm.measure('operation')
}
```

**Build without profiling:**
```bash
v vglyph/  # profiling code compiled out
```

**Build with profiling:**
```bash
v -d profile vglyph/  # profiling code active
```

**Benefit:** Zero overhead in production builds

## Validation Strategy

### Before Optimization

Run `-profile` to establish baseline:
```bash
v -profile baseline.txt examples/stress_demo.v
./stress_demo
```

### After Optimization

Run `-profile` to measure improvement:
```bash
v -profile optimized.txt examples/stress_demo.v
./stress_demo
diff <(sort -n -k2 baseline.txt) <(sort -n -k2 optimized.txt)
```

**Success criteria:**
- Target function shows reduced total time (column 2)
- No regression in other functions
- Overall frame time improved

### Continuous Monitoring

Add performance test to CI:
```v
// _performance_test.v
fn test_stress_demo_performance() {
    sw := time.new_stopwatch()

    // Simulate stress_demo workload
    ts := new_text_system(...)
    for _ in 0 .. 1000 {
        ts.draw_text(...)
    }
    ts.commit()

    elapsed := sw.elapsed().milliseconds()

    // Baseline from v1.1: ~500ms for 1000 draws
    assert elapsed < 600, 'Performance regression: ${elapsed}ms > 600ms'
}
```

## Recommended Approach Summary

**DO:**
1. Use `v -profile` for initial bottleneck discovery
2. Add `benchmark` module for targeted measurements
3. Use `time.StopWatch` for inline critical path timing
4. Track collision rate in glyph cache hash map
5. Measure atlas reset frequency and impact
6. Add conditional profiling with `-d profile` flag

**DON'T:**
1. Add external profilers (Valgrind, perf, etc.) - overkill
2. Instrument everything - focus on CONCERNS.md bottlenecks
3. Profile GPU unless CPU optimization exhausted
4. Add profiling overhead to production builds
5. Optimize before measuring

**Priority order:**
1. Fix glyph cache collisions (correctness + performance)
2. Cache FreeType metrics (easy win, low risk)
3. Defer atlas resets to frame boundaries (complexity vs gain)
4. Optimize bitmap scaling (measure first - might not be actual bottleneck)

## Sources

**V Language Profiling:**
- [V Documentation - Tools](https://docs.vlang.io/tools.html)
- [V Documentation - Performance Tuning](https://docs.vlang.io/performance-tuning.html)
- [V benchmark module](https://modules.vlang.io/benchmark.html)
- [V time module](https://modules.vlang.io/time.html)
- [V StopWatch source](https://github.com/vlang/v/blob/master/vlib/time/stopwatch.v)

**Profiling Techniques:**
- [Instrumentation-Based Profiling](https://www.computerenhance.com/p/instrumentation-based-profiling)
- [Lightweight Instrumentation for RTOS](https://sigbed.org/2024/05/27/lightweight-instrumentation-for-accurate-performance-monitoring-in-rtoses/)
- [Roll your own memory profiling](https://gaultier.github.io/blog/roll_your_own_memory_profiling.html)

**Performance Optimization:**
- [FreeType Performance](https://groups.google.com/g/Golang-Nuts/c/oqRV5P-HQIo/m/gkmbNp1pBwAJ)
- [GPU vs CPU Bitmap Performance](https://journalofcloudcomputing.springeropen.com/articles/10.1186/s13677-020-00191-w)
- [Texture Atlasing Performance](https://foro3d.com/en/2026/january/texture-atlasing-optimizes-performance-in-video-games.html)

**Data Structures:**
- [Open Addressing Collision Resolution](https://www.geeksforgeeks.org/dsa/open-addressing-collision-handling-technique-in-hashing/)
- [LRU Cache Implementation](https://www.educative.io/blog/implement-least-recently-used-cache)
- [LRU Cache with Hash Map](https://algomaster.io/learn/lld/design-lru-cache)

---

**Confidence Assessment:**

| Area | Level | Reason |
|------|-------|--------|
| V profiling tools | HIGH | Official documentation, confirmed APIs |
| Instrumentation strategy | HIGH | Direct mapping to CONCERNS.md bottlenecks |
| Optimization approaches | HIGH | Cross-referenced with domain research |
| Tool recommendations | HIGH | Based on project constraints (lightweight, no deps) |

**Ready for roadmap creation.** Stack additions are minimal and low-risk.
