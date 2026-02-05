# Phase 28: Profiling Validation - Research

**Researched:** 2026-02-05
**Domain:** Performance measurement, stress testing, optimization validation
**Confidence:** HIGH

## Summary

Phase 28 measures optimization impact from shelf packing (P26) and async
uploads (P27), validates improvements via stress testing, and makes
data-driven go/no-go decision on shape caching (P29). Domain: performance
profiling, multilingual stress testing, statistical comparison, decision
thresholds.

VGlyph has existing profiling infrastructure (`$if profile ?` blocks,
ProfileMetrics struct, print_summary() output) from Phase 8. Phase 28
extends this by: (1) adding LayoutCache hit rate tracking, (2) exposing
atlas utilization via existing shelf metrics, (3) creating multilingual
stress test example, (4) establishing before/after comparison methodology,
(5) setting P29 decision threshold based on cache hit rate.

Standard approach: extend existing ProfileMetrics with layout cache fields,
create standalone stress_validation.v example with ASCII+Latin+CJK+emoji
content, run with `-d profile` to measure, compare async vs sync using kill
switch, write recommendation to VERIFICATION.md. No statistical tests needed
(one-time validation, not benchmark suite). User reviews threshold,
approves/rejects P29.

**Primary recommendation:** Add layout_cache_hits/misses to ProfileMetrics,
expose via print_summary(). Create stress_validation.v with 2K+ glyphs
spanning scripts. Test with async_uploads=true/false. Write profiling report
to VERIFICATION.md with P29 recommendation (proceed if hit rate < 70%,
skip if >= 70%).

## Standard Stack

Established tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `$if profile ?` | V compiler | Zero-overhead profiling | Existing P8 pattern, compile-time removal |
| `time` module | V stdlib | Nanosecond timing | sys_mono_now() in existing code |
| ProfileMetrics | VGlyph | Metrics aggregation | context.v L56-135, print_summary() |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `v -d profile` | V compiler | Enable profiling build | Compiles profiling blocks |
| `examples/*.v` | VGlyph | Stress tests | Existing pattern (stress_demo.v, emoji_demo.v) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual comparison | Statistical tests (t-test) | Stats overkill for one-time validation |
| New stress binary | Extend stress_demo.v | New binary clearer intent (validation vs demo) |
| File logging | Terminal output | Terminal simpler, validation is one-time |

**No installation:** All V stdlib, no external dependencies.

## Architecture Patterns

Instrumentation integrates into existing files, one new stress test example:

```
src/
  context.v         # ProfileMetrics already exists, print_summary() exists
  api.v             # TextSystem has layout_cache_hits/misses fields
  renderer.v        # Renderer has glyph_cache_hits/misses fields
examples/
  stress_validation.v  # NEW: multilingual stress test for P28
```

### Pattern 1: Extend Existing ProfileMetrics

**What:** Add layout cache tracking to existing struct
**When to use:** Metrics infrastructure already exists (Phase 8)
**Example:**
```v
// Source: context.v L56-135
$if profile ? {
    pub struct ProfileMetrics {
    pub mut:
        // ... existing fields ...
        layout_cache_hits     int  // ALREADY EXISTS (L68)
        layout_cache_misses   int  // ALREADY EXISTS (L69)
    }

    // layout_cache_hit_rate already exists (L94-101)
    pub fn (m ProfileMetrics) layout_cache_hit_rate() f32 {
        total := m.layout_cache_hits + m.layout_cache_misses
        if total == 0 { return 0.0 }
        return f32(m.layout_cache_hits) / f32(total) * 100.0
    }
}
```

### Pattern 2: Multilingual Stress Test Structure

**What:** Example binary with diverse scripts to maximize cache/atlas diversity
**When to use:** Validating optimization impact across real-world text
**Example:**
```v
// Source: VGlyph examples pattern (stress_demo.v L1-137)
module main
import gg
import vglyph

struct StressApp {
mut:
    ctx &gg.Context = unsafe { nil }
    ts  &vglyph.TextSystem = unsafe { nil }
}

fn frame(mut app StressApp) {
    app.ctx.begin()
    app.ctx.draw_rect_filled(0, 0, app.ctx.width, app.ctx.height, gg.white)

    // ASCII (Latin-1)
    app.ts.draw_text(10, 10, 'Quick brown fox...', cfg) or {}

    // Latin Extended
    app.ts.draw_text(10, 40, 'Héllo Wörld Ñoño', cfg) or {}

    // CJK
    app.ts.draw_text(10, 70, 'こんにちは世界 안녕하세요', cfg) or {}

    // Emoji
    app.ts.draw_text(10, 100, '😀 😃 🏋️‍♂️ 🇺🇸', cfg) or {}

    app.ts.commit()
    app.ctx.end()
}
```

### Pattern 3: Before/After Comparison with Kill Switch

**What:** Use async_uploads flag to compare async vs sync
**When to use:** Validating optimization impact
**Example:**
```v
// Source: glyph_atlas.v L73, renderer.v L113
// In stress test documentation:
// Run 1: v -d profile run examples/stress_validation.v
//        (async_uploads=true, default)
// Run 2: Change glyph_atlas.v L73 to async_uploads: false
//        v -d profile run examples/stress_validation.v
// Compare upload_time_ns between runs
```

### Pattern 4: Profiling Report to VERIFICATION.md

**What:** Document measurements and P29 decision rationale
**When to use:** Phase validation that informs next phase
**Example:**
```markdown
## Profiling Results

**Test:** stress_validation.v (2000 glyphs, ASCII+Latin+CJK+emoji)
**Build:** v -d profile run examples/stress_validation.v

### LayoutCache Performance

- Hit rate: 68.4% (1368/2000)
- Recommendation: **PROCEED with Phase 29 (Shape Cache)**
- Rationale: Hit rate < 70% threshold indicates frequent layout
  misses. Shape plan caching will reduce HarfBuzz overhead on
  cache misses.

### Atlas Utilization

- Before shelf packing (row-based): 70.2%
- After shelf packing (BHF): 76.8%
- Improvement: +6.6 percentage points ✓

### Upload Time

- Async (double-buffered): 3.2ms
- Sync (memcpy fallback): 3.8ms
- Improvement: 15.8% faster ✓
```

### Anti-Patterns to Avoid

- **Statistical tests for one-time validation:** Overkill, adds complexity
  without value
- **Permanent benchmark suite:** User decided one-time stress test for v1.6,
  not ongoing CI
- **File logging:** Terminal output sufficient, validation is manual review
- **Per-frame metrics:** Report aggregate only (matches user decision for
  percentage-only output)

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| High-res timing | Custom timestamp logic | time.sys_mono_now() | Phase 8 pattern, monotonic, proven |
| Cache hit rate calc | Manual percentage | ProfileMetrics methods | Already exists (L86-109) |
| Metrics output | Custom formatting | print_summary() | Existing, consistent format |
| Multilingual test | Random unicode | Curated script samples | Emoji/CJK require specific fonts |

**Key insight:** ProfileMetrics infrastructure exists. Phase 28 uses it, adds
layout cache tracking (fields already exist), creates stress test that calls
print_summary().

## Common Pitfalls

### Pitfall 1: Premature Statistical Analysis

**What goes wrong:** Treating validation as scientific benchmark, applying
t-tests, p-values, confidence intervals for one-time measurement
**Why it happens:** Background in performance engineering, instinct to apply
rigorous methods
**How to avoid:** This is validation, not benchmarking. User decided one-time
stress test. Simple before/after comparison sufficient. Save stats for
research papers.
**Warning signs:** Calculating standard deviation, running multiple trials,
statistical significance tests

### Pitfall 2: Warmup Phase Confusion

**What goes wrong:** First frame has 0% cache hit rate (all misses), reported
as poor performance
**Why it happens:** Caches empty at startup, every glyph/layout is initial
miss
**How to avoid:** Render warmup frames (10-20) before measuring, or report
steady-state hit rate (average of frames 50-100)
**Warning signs:** Hit rate < 10%, profiling shows expected behavior but
numbers look bad

### Pitfall 3: Comparing Different Workloads

**What goes wrong:** Async run uses different text than sync run, numbers
incomparable
**Why it happens:** Changing test content between runs, random generation
**How to avoid:** Use identical text content for both runs. Stress test
should use fixed strings, not random.
**Warning signs:** Upload time varies wildly between runs (different glyph
counts)

### Pitfall 4: Atlas Utilization Misinterpretation

**What goes wrong:** Reporting 50% utilization as failure when atlas is
intentionally oversized
**Why it happens:** Not understanding atlas lifecycle (grows on demand, never
shrinks)
**How to avoid:** Atlas utilization measured when FULL (after all glyphs
loaded). Low utilization with small content is expected. Use stress test with
2000+ glyphs to fill atlas.
**Warning signs:** Panic about 40% utilization with 100-character test string

### Pitfall 5: Decision Threshold as Hard Rule

**What goes wrong:** Treating 70% threshold as absolute, ignoring context
**Why it happens:** Roadmap suggested 70%, implemented as inflexible rule
**How to avoid:** Threshold is guideline. If hit rate is 69%, consider
workload, complexity, user needs. Write recommendation with rationale, user
decides.
**Warning signs:** Recommendation says "69.8% < 70%, therefore implement
shape cache" without analysis

## Code Examples

Verified patterns from existing VGlyph code and V language docs:

### ProfileMetrics Extension (Already Exists)

```v
// Source: context.v L56-135
$if profile ? {
    pub struct ProfileMetrics {
    pub mut:
        // Frame timing (nanoseconds)
        layout_time_ns    i64
        rasterize_time_ns i64
        upload_time_ns    i64
        draw_time_ns      i64

        // Cache statistics (INST-03)
        glyph_cache_hits      int
        glyph_cache_misses    int
        glyph_cache_evictions int
        layout_cache_hits     int  // PROF-01
        layout_cache_misses   int  // PROF-01

        // Atlas statistics (INST-05)
        atlas_inserts      int
        atlas_grows        int
        atlas_resets       int
        atlas_used_pixels  i64    // PROF-02
        atlas_total_pixels i64    // PROF-02
        atlas_page_count   int
    }

    pub fn (m ProfileMetrics) layout_cache_hit_rate() f32 {
        total := m.layout_cache_hits + m.layout_cache_misses
        if total == 0 { return 0.0 }
        return f32(m.layout_cache_hits) / f32(total) * 100.0
    }

    pub fn (m ProfileMetrics) atlas_utilization() f32 {
        if m.atlas_total_pixels == 0 { return 0.0 }
        return f32(m.atlas_used_pixels) / f32(m.atlas_total_pixels) * 100.0
    }

    pub fn (m ProfileMetrics) print_summary() {
        // ... existing implementation L111-134 ...
    }
}
```

### Stress Validation Example Structure

```v
// Source: stress_demo.v pattern, atlas_debug.v multilingual text
// NEW FILE: examples/stress_validation.v
module main

import gg
import vglyph

struct ValidationApp {
mut:
    ctx    &gg.Context = unsafe { nil }
    ts     &vglyph.TextSystem = unsafe { nil }
    frame_count int
}

fn frame(mut app ValidationApp) {
    app.ctx.begin()
    app.ctx.draw_rect_filled(0, 0, app.ctx.width, app.ctx.height, gg.white)

    cfg := vglyph.TextConfig{
        style: vglyph.TextStyle{
            font_name: 'Sans 20'
            color: gg.black
        }
    }

    mut y := f32(10)
    row_h := f32(30)

    // ASCII - basic Latin (100 glyphs)
    for i in 0 .. 10 {
        text := 'The quick brown fox jumps over the lazy dog ${i}'
        app.ts.draw_text(10, y, text, cfg) or {}
        y += row_h
    }

    // Latin Extended - accented characters (50 glyphs)
    accented := ['Héllo Wörld', 'Ñoño Café', 'Zürich Åhus', 'Łódź Århus', 'Øresund']
    for txt in accented {
        app.ts.draw_text(10, y, txt, cfg) or {}
        y += row_h
    }

    // CJK - Japanese/Korean/Chinese (200 glyphs)
    app.ts.draw_text(10, y, 'Japanese: こんにちは世界 ありがとうございます', cfg) or {}
    y += row_h
    app.ts.draw_text(10, y, 'Korean: 안녕하세요 세계 감사합니다', cfg) or {}
    y += row_h
    app.ts.draw_text(10, y, 'Chinese: 你好世界 谢谢 再见', cfg) or {}
    y += row_h

    // Emoji - color glyphs (50 glyphs)
    app.ts.draw_text(10, y, 'Emoji: 😀 😃 😄 😁 😆 😅 😂 🤣', cfg) or {}
    y += row_h
    app.ts.draw_text(10, y, 'Flags: 🇺🇸 🇬🇧 🇯🇵 🇰🇷 🇫🇷 🇩🇪', cfg) or {}
    y += row_h

    app.ts.commit()

    // Print profile after warmup (frame 100)
    $if profile ? {
        if app.frame_count == 100 {
            metrics := app.ts.get_profile_metrics()
            metrics.print_summary()
        }
    }

    app.frame_count++
    app.ctx.end()
}

fn init(mut app ValidationApp) {
    app.ts = vglyph.new_text_system(mut app.ctx) or { panic(err) }
}

fn main() {
    mut app := &ValidationApp{}
    app.ctx = gg.new_context(
        width: 800
        height: 600
        window_title: 'Profiling Validation (Phase 28)'
        create_window: true
        bg_color: gg.white
        ui_mode: true
        user_data: app
        frame_fn: frame
        init_fn: init
    )
    app.ctx.run()
}
```

### Running Profiling Validation

```bash
# Build and run with profiling enabled
v -d profile run examples/stress_validation.v

# Expected output (after frame 100):
# === VGlyph Profile Metrics ===
# Frame Time Breakdown:
#   Layout:    1200 us
#   Rasterize: 800 us
#   Upload:    3200 us
#   Draw:      400 us
#   Total:     5600 us
# Glyph Cache: 85.2% (1704/2000), 0 evictions
# Layout Cache: 68.4% (1368/2000)
# Atlas: 2 pages, 76.8% utilized (1572864/2048000 px)
# Memory: 8192 KB current, 8192 KB peak
```

### Before/After Async Upload Comparison

```bash
# Async (default)
v -d profile run examples/stress_validation.v
# Note upload_time_ns from output

# Sync (kill switch)
# Edit glyph_atlas.v L73: async_uploads: false
v -d profile run examples/stress_validation.v
# Compare upload_time_ns

# Restore async_uploads: true before committing
```

### Decision Threshold Logic

```v
// Pseudo-code for VERIFICATION.md generation
fn analyze_profiling_results(metrics ProfileMetrics) string {
    mut report := '## Profiling Results\n\n'

    // Layout cache hit rate analysis
    hit_rate := metrics.layout_cache_hit_rate()
    report += '### LayoutCache Performance\n\n'
    report += '- Hit rate: ${hit_rate:.1f}%\n'

    if hit_rate < 70.0 {
        report += '- Recommendation: **PROCEED with Phase 29 (Shape Cache)**\n'
        report += '- Rationale: Hit rate below 70% threshold indicates frequent '
        report += 'layout cache misses. Shape plan caching will reduce HarfBuzz '
        report += 'overhead on misses, improving layout_time_ns.\n'
    } else {
        report += '- Recommendation: **SKIP Phase 29 (Shape Cache)**\n'
        report += '- Rationale: Hit rate >= 70% means layout cache is effective. '
        report += 'Shape plan cache would add complexity for minimal benefit.\n'
    }

    // Atlas utilization analysis
    util := metrics.atlas_utilization()
    report += '\n### Atlas Utilization\n\n'
    report += '- Utilization: ${util:.1f}%\n'
    if util >= 75.0 {
        report += '- Status: ✓ Shelf packing meets 75% target\n'
    } else {
        report += '- Status: ⚠ Below 75% target, investigate\n'
    }

    return report
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual profiling | Conditional compilation | Phase 8 (2026-02-02) | Zero release overhead |
| Fixed benchmarks | One-time validation | Phase 28 decision | Simpler, fits v1.6 scope |
| Statistical rigor | Threshold-based decision | Modern practice (2025-2026) | Faster iteration |

**Deprecated/outdated:**
- Permanent benchmark suites for every optimization (modern: profile-driven,
  validate once)
- Statistical significance testing for one-time measurements (overkill)
- Complex variance tracking (modern: baseline + threshold, not p-values)

**Modern trends (2025-2026):**
- Performance baseline testing with standard deviation thresholds (more
  accurate than fixed percentages)
- p95-p99 tail latency focus (not just averages) for distributed systems
- Error budgets over binary pass/fail for SLO compliance

VGlyph context: Single-threaded, deterministic workload, one-time validation.
Modern distributed-system practices don't apply. Simple threshold sufficient.

## Open Questions

1. **Stress test glyph count**
   - What we know: More glyphs = better atlas/cache coverage
   - What's unclear: Optimal count for validation (1K? 2K? 5K?)
   - Recommendation: 2000 glyphs (100 ASCII + 50 Latin + 200 CJK + 50 emoji +
     1600 repeated content). Fills typical 1024x1024 atlas, exercises cache
     diversity.

2. **Warmup frame count**
   - What we know: First frames have 0% hit rate (cold cache)
   - What's unclear: How many warmup frames before steady state?
   - Recommendation: 10-20 warmup frames, report at frame 100. User can run
     longer if needed.

3. **P29 threshold flexibility**
   - What we know: Roadmap suggests 70% threshold
   - What's unclear: Hard rule or guideline?
   - Recommendation: Guideline. Report includes rationale paragraph. If 68%,
     consider complexity vs benefit. User decides.

4. **Multiple font sizes impact**
   - What we know: Different sizes = different cache keys
   - What's unclear: Should stress test use multiple sizes?
   - Recommendation: Single size (20pt) for baseline. User can test varied
     sizes if needed, but not required for go/no-go.

## Sources

### Primary (HIGH confidence)
- VGlyph context.v L56-135 - ProfileMetrics struct, print_summary()
  implementation
- VGlyph api.v L24-27 - layout_cache_hits/misses fields already exist
- VGlyph examples/stress_demo.v - stress test pattern (6000 glyphs, viewport
  culling)
- VGlyph examples/atlas_debug.v L67-79 - multilingual text pattern
  (emoji+JP+KR)
- [V Testing Documentation](https://docs.vlang.io/testing.html) - `v -d
  profile` flag, test patterns
- VGlyph .planning/phases/08-instrumentation/08-RESEARCH.md - profiling
  patterns, pitfalls
- VGlyph .planning/research/PITFALLS.md L464 - cache hit rate interpretation,
  warmup phase

### Secondary (MEDIUM confidence)
- [Performance Baseline Testing 2026](https://oneuptime.com/blog/post/2026-01-30-performance-baseline-testing/view)
  - Standard deviation thresholds vs fixed percentages
- [Software Stress Testing 2026](https://blog.qasource.com/everything-you-need-to-know-about-stress-testing-your-software)
  - Stress testing methodology, breaking point analysis
- [Load vs Stress Testing 2026](https://www.loadview-testing.com/learn/load-testing-vs-stress-testing/)
  - Modern trends: p95-p99 tail latency, error budgets

### Tertiary (LOW confidence)
- [Redis Cache Hit Ratio Strategy](https://redis.io/blog/why-your-cache-hit-ratio-strategy-needs-an-update/)
  - High hit ratio doesn't guarantee performance (broader view needed)
- [vLLM Cache Hit Threshold RFC](https://github.com/vllm-project/vllm/issues/24256)
  - Cache hit-based admission control pattern

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - ProfileMetrics exists, V stdlib proven
- Architecture: HIGH - Extends Phase 8 patterns, stress test follows
  stress_demo.v
- Pitfalls: HIGH - Based on VGlyph PITFALLS.md, Phase 8 experience
- Decision threshold: MEDIUM - User guideline (70%), flexibility needed

**Research date:** 2026-02-05
**Valid until:** 30 days (stable profiling patterns, threshold is project
decision)
