# Phase 8: Instrumentation - Research

**Researched:** 2026-02-02
**Domain:** Zero-overhead profiling instrumentation for text rendering
**Confidence:** HIGH

## Summary

Phase 8 implements profiling instrumentation for VGlyph's hot paths: layout computation, glyph
rasterization, atlas texture upload, and render draw calls. The implementation uses V's conditional
compilation (`$if profile ?`) to achieve zero release overhead - instrumentation code is entirely
removed at compile time when `-d profile` flag is not passed.

The architecture follows established patterns from VGlyph's v1.1 debug guards (`$if debug {}`),
extending them to profiling. V's `time.StopWatch` provides nanosecond-resolution timing. Metrics
are collected at component boundaries and aggregated in a single struct accessible via user API.
Cache hit/miss tracking enables optimization validation. Atlas utilization metrics expose memory
efficiency.

**Primary recommendation:** Add `ProfileMetrics` struct to Context with timing, cache, and atlas
fields. Instrument 4 hot paths using `$if profile ?` with defer-based timing. Expose
`get_profile_metrics()` API behind conditional compilation.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `time` module | V stdlib | StopWatch, Duration | High-res timing, zero deps |
| `$if profile ?` | V compiler | Conditional compilation | Compile-time code removal |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `benchmark` module | V stdlib | Batch measurements | Validating per-op timing |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| StopWatch | time.ticks() | StopWatch cleaner API, auto-start |
| $if profile ? | Runtime bool | Runtime has 2-3% overhead vs zero |
| Context.metrics | Separate struct | Centralized is easier to query |

**No installation:** All tools are V stdlib, no external dependencies.

## Architecture Patterns

### Recommended Project Structure

Instrumentation integrates into existing files, no new files required:

```
src/
  context.v        # Add ProfileMetrics struct, get_profile_metrics()
  layout.v         # Add timing to layout_text(), build_layout_from_pango()
  glyph_atlas.v    # Add timing to insert_bitmap(), grow()
  renderer.v       # Add timing to draw_layout(), load_glyph(), commit()
```

### Pattern 1: Defer-Based Timing

**What:** Use defer to capture timing even with early returns
**When to use:** Any function with error returns or multiple exit points
**Example:**
```v
// Source: V language defer semantics
pub fn (mut atlas GlyphAtlas) insert_bitmap(bmp Bitmap, left int, top int) !(CachedGlyph, bool) {
    $if profile ? {
        start := time.sys_mono_now()
        defer { atlas_metrics.insert_time_ns += time.sys_mono_now() - start }
    }
    // ... operation that might return early with ! ...
}
```

### Pattern 2: Scoped Counters

**What:** Accumulate counters in local vars, update metrics in defer
**When to use:** Cache hit/miss tracking in loops
**Example:**
```v
// Source: VGlyph v1.1 patterns
$if profile ? {
    mut hits := 0
    mut misses := 0
    defer {
        metrics.cache_hits += hits
        metrics.cache_misses += misses
    }
}

for glyph in glyphs {
    if key in cache {
        $if profile ? { hits++ }
    } else {
        $if profile ? { misses++ }
        // load glyph
    }
}
```

### Pattern 3: Conditional API Surface

**What:** Entire profiling API behind `$if profile ?`
**When to use:** Public API that should not exist in release
**Example:**
```v
// Source: VGlyph research/ARCHITECTURE.md
$if profile ? {
    pub fn (ctx Context) get_profile_metrics() ProfileMetrics {
        return ctx.profile_metrics
    }

    pub fn (mut ctx Context) reset_profile_metrics() {
        ctx.profile_metrics = ProfileMetrics{}
    }
}
```

### Pattern 4: Metrics Struct Co-location

**What:** Single metrics struct owned by Context
**When to use:** Aggregating metrics across components
**Example:**
```v
// Source: VGlyph research/ARCHITECTURE.md
pub struct Context {
    // ... existing fields ...
    $if profile ? {
        pub mut:
            profile_metrics ProfileMetrics
    }
}
```

### Anti-Patterns to Avoid
- **Runtime flag check:** `if ctx.profiling_enabled {` adds branch overhead in release
- **Metrics in hot loop:** Call sys_mono_now() per-function, not per-glyph
- **File I/O in hot path:** Accumulate in memory, print on demand
- **Metrics struct without conditional:** Wastes memory in release builds

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| High-res timing | manual timestamp diff | time.StopWatch | Handles pause/resume, duration conversion |
| Conditional code | runtime bool check | $if profile ? | Compile-time removal, zero overhead |
| Nanosecond time | time.now() | time.sys_mono_now() | Monotonic, not affected by wall clock |
| Duration formatting | manual string concat | Duration.str() | Proper units auto-selected |

**Key insight:** V stdlib timing is sufficient. External profilers (Valgrind, perf) add 10-50x
slowdown and are overkill for targeted instrumentation.

## Common Pitfalls

### Pitfall 1: Profiling in Debug Mode
**What goes wrong:** Debug builds 5-10x slower due to v1.1 validation guards
**Why it happens:** `$if debug {}` guards active, additional runtime checks
**How to avoid:** Always profile with `-d profile` only, not `-g`
**Warning signs:** Frame times 10x higher than expected

### Pitfall 2: Optimizing Before Profiling
**What goes wrong:** "Obvious" optimizations often wrong. Intuition fails with Pango/FreeType
**Why it happens:** Complex hot paths with hidden costs
**How to avoid:** Profile FIRST, require data for every optimization
**Warning signs:** Optimization yields no measurable improvement

### Pitfall 3: Instrumentation in Production
**What goes wrong:** Profiling code left in release builds adds 5%+ overhead
**Why it happens:** Forgetting to use `$if profile ?`, or using runtime check
**How to avoid:** ALL timing code behind `$if profile ?`. Verify release binary size unchanged
**Warning signs:** Release build larger than expected, timing code visible in disassembly

### Pitfall 4: Excessive Granularity
**What goes wrong:** sys_mono_now() overhead (~100-500ns) dominates measured operation
**Why it happens:** Timing individual loop iterations
**How to avoid:** Profile at function granularity, not per-glyph
**Warning signs:** Timing overhead visible in profile

### Pitfall 5: Cache Hit Rate Misinterpretation
**What goes wrong:** Low hit rate assumed bad, but warmup phase is normal
**Why it happens:** First frame loads all glyphs (100% miss rate expected)
**How to avoid:** Track per-frame rates after warmup, not just totals
**Warning signs:** Panic about 50% hit rate in first 10 frames

## Code Examples

Verified patterns from V language and VGlyph existing code:

### StopWatch Usage
```v
// Source: https://modules.vlang.io/time.html
import time

fn expensive_operation() {
    time.sleep(510 * time.millisecond)
}

fn main() {
    sw := time.new_stopwatch()  // Auto-starts
    expensive_operation()
    println('Elapsed: ${sw.elapsed().milliseconds()} ms')
}
```

### Conditional Compilation Pattern
```v
// Source: https://docs.vlang.io/conditional-compilation.html
// Compile with: v -d profile main.v

$if profile ? {
    fn log_timing(name string, duration_ns u64) {
        println('${name}: ${duration_ns / 1000} us')
    }
}

fn some_function() {
    $if profile ? {
        start := time.sys_mono_now()
        defer { log_timing('some_function', time.sys_mono_now() - start) }
    }
    // ... actual work ...
}
```

### ProfileMetrics Struct
```v
// Source: VGlyph research/ARCHITECTURE.md pattern
pub struct ProfileMetrics {
pub mut:
    // Frame timing (in nanoseconds for precision)
    layout_time_ns      i64
    rasterize_time_ns   i64
    upload_time_ns      i64
    draw_time_ns        i64

    // Cache statistics
    cache_hits          int
    cache_misses        int

    // Atlas statistics
    atlas_inserts       int
    atlas_grows         int
    atlas_resets        int
    atlas_used_pixels   i64
    atlas_total_pixels  i64

    // Memory tracking
    peak_atlas_bytes    i64
}

// Derived metrics
$if profile ? {
    pub fn (m ProfileMetrics) cache_hit_rate() f32 {
        total := m.cache_hits + m.cache_misses
        if total == 0 { return 0.0 }
        return f32(m.cache_hits) / f32(total) * 100.0
    }

    pub fn (m ProfileMetrics) atlas_utilization() f32 {
        if m.atlas_total_pixels == 0 { return 0.0 }
        return f32(m.atlas_used_pixels) / f32(m.atlas_total_pixels) * 100.0
    }
}
```

### Atlas Utilization Tracking
```v
// Source: VGlyph glyph_atlas.v current code inspection
// cursor_y * width gives used area, height * width gives total

$if profile ? {
    pub fn (atlas &GlyphAtlas) utilization() f32 {
        total := i64(atlas.width) * i64(atlas.height)
        if total == 0 { return 0.0 }
        // cursor_y is next row start, row_height is current row max
        used := i64(atlas.cursor_y + atlas.row_height) * i64(atlas.width)
        return f32(used) / f32(total) * 100.0
    }
}
```

### Frame Time Breakdown Output
```v
// Source: VGlyph research patterns
$if profile ? {
    pub fn (m ProfileMetrics) print_frame_breakdown() {
        total := m.layout_time_ns + m.rasterize_time_ns + m.upload_time_ns + m.draw_time_ns
        if total == 0 { return }

        println('Frame Time Breakdown:')
        println('  Layout:    ${m.layout_time_ns / 1000} us (${f32(m.layout_time_ns) / f32(total) * 100:.1}%)')
        println('  Rasterize: ${m.rasterize_time_ns / 1000} us (${f32(m.rasterize_time_ns) / f32(total) * 100:.1}%)')
        println('  Upload:    ${m.upload_time_ns / 1000} us (${f32(m.upload_time_ns) / f32(total) * 100:.1}%)')
        println('  Draw:      ${m.draw_time_ns / 1000} us (${f32(m.draw_time_ns) / f32(total) * 100:.1}%)')
        println('Cache Hit Rate: ${m.cache_hit_rate():.1}%')
        println('Atlas Utilization: ${m.atlas_utilization():.1}%')
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Runtime profiling flags | Compile-time conditional | V language design | Zero release overhead |
| External profilers only | Built-in instrumentation | Modern practice | Lower overhead, always available |
| Microsecond timing | Nanosecond monotonic | time.sys_mono_now() | Higher precision |

**Deprecated/outdated:**
- Using `time.ticks()` directly: Use StopWatch for cleaner API
- Runtime feature flags for profiling: Use `$if profile ?` for zero overhead

## Open Questions

Things that couldn't be fully resolved:

1. **Metrics struct location**
   - What we know: Context owns metrics for layout, Renderer owns cache/atlas
   - What's unclear: Single struct in Context or split between Context and Renderer?
   - Recommendation: Single struct in Context, Renderer updates via passed reference

2. **Per-page atlas metrics**
   - What we know: INST-05 requires per-page utilization
   - What's unclear: Current VGlyph has single-page atlas; multi-page comes in Phase 9
   - Recommendation: Track single-page metrics now, extend to array when multi-page added

3. **Growth rate calculation**
   - What we know: INST-04 requires "growth rate per frame"
   - What's unclear: Rolling average? Peak delta? Absolute delta?
   - Recommendation: Track peak_bytes and bytes_this_frame, let user calculate rate

## Sources

### Primary (HIGH confidence)
- [V Conditional Compilation](https://docs.vlang.io/conditional-compilation.html) - $if profile ?,
  -d flags, compile-time removal verified
- [V time module](https://modules.vlang.io/time.html) - StopWatch, Duration, sys_mono_now()
- VGlyph research/ARCHITECTURE.md - profiling patterns, zero-overhead approach

### Secondary (MEDIUM confidence)
- [V benchmark module](https://modules.vlang.io/benchmark.html) - batch timing patterns
- VGlyph v1.1 $if debug {} patterns - proven conditional compilation in codebase

### Tertiary (LOW confidence)
- Rust metrics/hotpath-rs precedents - zero-cost when disabled (different language)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - V stdlib verified, no external deps needed
- Architecture: HIGH - Extends proven $if debug {} pattern from v1.1
- Pitfalls: HIGH - Cross-referenced with research/PITFALLS.md, v1.1 lessons

**Research date:** 2026-02-02
**Valid until:** 60 days (stable V language patterns)
