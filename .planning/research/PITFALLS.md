# Performance Optimization Pitfalls

**Domain:** Text rendering performance profiling/optimization
**Project:** VGlyph — V language text rendering (Pango/FreeType/OpenGL)
**Context:** Adding performance work to safety-hardened (v1.0, v1.1) rendering system
**Researched:** 2026-02-02

## Critical Pitfalls

Mistakes causing rewrites, major performance regressions, or breaking safety guarantees.

### Pitfall 1: Profiling in Debug Mode

**What goes wrong:** Performance measurements taken in debug builds show 5-10x slower
execution vs release builds due to runtime checks, assertions, and disabled optimizations.
This leads to optimizing the wrong code paths and setting incorrect performance baselines.

**Why it happens:** Debug builds are the default during development. v1.1 added debug-only
validation guards (iterator exhaustion, AttrList leak counter, FT state validation) which
add overhead that doesn't exist in production.

**Consequences:**
- Optimize code paths that aren't bottlenecks in release
- Miss actual bottlenecks masked by debug overhead
- Performance targets based on misleading data
- Wasted optimization effort on non-issues

**Prevention:**
- Always profile in release builds (`v -prod`)
- Baseline measurements MUST be release mode
- Document which measurements are debug vs release
- Flag any profiling data collected in debug mode as INVALID

**Detection:**
- Check compiler flags before starting profiling
- Compare debug vs release baseline (should see 5-10x difference)
- If optimization shows <10% improvement, verify profiling mode

**Phase guidance:** Phase 1 (instrumentation) must validate release mode before any
measurements taken.

---

### Pitfall 2: Optimizing Before Profiling (Premature Optimization)

**What goes wrong:** Implementing "obvious" optimizations based on code inspection rather
than profiling data. In text rendering, intuition about bottlenecks is often wrong —
FreeType/Pango have non-obvious performance characteristics.

**Why it happens:** CONCERNS.md lists suspected bottlenecks (atlas reset, cache collisions,
FreeType metrics, bitmap scaling). Temptation to optimize these directly without validating
they're actual bottlenecks.

**Consequences:**
- Optimize code that's already fast enough
- Break safety guarantees from v1.0/v1.1 hardening
- Add complexity without measurable benefit
- Miss real bottlenecks (e.g., GPU synchronization stalls)

**Prevention:**
- Profile FIRST with lightweight metrics
- Require profiling data showing bottleneck before optimization
- Validate each CONCERNS.md suspected bottleneck with measurements
- 80/20 rule: focus on top 20% of measured time

**Detection:**
- Any optimization PR without profiling data justification = RED FLAG
- Check git history: instrumentation commits MUST precede optimization commits

**Phase guidance:** Phase 2-4 (profiling phases) MUST complete before Phase 5-7
(optimization phases). No exceptions.

---

### Pitfall 3: Breaking Correctness for Performance

**What goes wrong:** Optimization removes safety checks added in v1.0 (error propagation,
overflow validation, null checks) or v1.1 (iterator exhaustion, AttrList leak detection, FT
state validation). Text renders faster but crashes or shows visual corruption.

**Why it happens:** Safety checks have measurable cost. Hot path operations (glyph
rasterization, atlas updates) seem like optimization targets. Pressure to hit performance
targets.

**Consequences:**
- Reintroduce crashes/UB that v1.0/v1.1 fixed
- Visual corruption (wrong glyphs, missing text)
- Security vulnerabilities (buffer overflows)
- Lose all value of previous hardening work

**Prevention:**
- Release-mode safety checks (null checks, overflow validation) are UNTOUCHABLE
- Debug-only checks can be discussed but require explicit documentation
- Verify test suite still passes after optimization
- Run visual regression tests (screenshot comparison)
- Manual testing with stress cases (emoji-heavy, large fonts, vertical text)

**Detection:**
- Any optimization removing `if ptr == nil` or overflow check = REQUIRES JUSTIFICATION
- Test failures after optimization = ROLLBACK IMMEDIATELY
- Visual artifacts in examples = ROLLBACK IMMEDIATELY

**Phase guidance:** Every optimization phase includes verification step. No merge without
passing tests + visual validation.

---

### Pitfall 4: Profiling Overhead Slows Production Code

**What goes wrong:** Instrumentation added for profiling (timestamps, counters, event
logging) remains in production builds. Text rendering becomes slower than baseline due to
measurement overhead.

**Why it happens:** Instrumentation code added without conditional compilation. Forgetting
to use debug-only guards. "Always-on" metrics sound appealing but have 1-5% CPU overhead.

**Consequences:**
- Ship slower code than before optimization work
- User-visible performance regression
- Defeat entire purpose of optimization milestone
- Production metrics collection impacts user experience

**Prevention:**
- ALL profiling instrumentation MUST be behind debug/feature flags
- Measure baseline → add instrumentation → measure again (should be identical)
- Use V's conditional compilation (`$if debug { ... }`)
- Profiling code isolated in separate modules, not mixed with hot paths
- Continuous profiling (always-on) NOT appropriate for graphics rendering

**Detection:**
- Compare release build performance before/after instrumentation
- Instrumentation adds >0.1% overhead = REFACTOR OR REMOVE
- Search codebase for timing/counter code not behind conditional

**Phase guidance:** Phase 1 (instrumentation) MUST validate zero overhead in release builds.
Continuous integration should test release performance after every commit.

---

### Pitfall 5: GPU-CPU Pipeline Stalls from Synchronous Profiling

**What goes wrong:** Profiling GPU operations (texture uploads, draw calls) with CPU
timers requires synchronization (glFinish, glGetError). This stalls the pipeline, making
measured performance 10-100x slower than actual async performance.

**Why it happens:** CPU timing is straightforward; GPU profiling is hard. Calling glFinish()
to ensure operation completes before stopping timer seems necessary.

**Consequences:**
- Profiling data shows "slow" GPU operations that are actually fast
- Optimize GPU paths unnecessarily
- Miss actual CPU bottlenecks (layout computation, shaping)
- Synchronous profiling changes what you're measuring (observer effect)

**Prevention:**
- Use GPU query objects (glBeginQuery/glEndQuery) for GPU timing
- Never call glFinish() in profiling code
- Separate CPU time (before glDrawArrays) from GPU time (actual rendering)
- Understand async GPU execution model
- Profile frame time end-to-end, then isolate bottlenecks

**Detection:**
- Any profiling code with glFinish() = WRONG
- GPU operations showing >10ms = likely synchronization artifact
- Frame time doesn't match sum of component times = pipeline stalls

**Phase guidance:** Phase 4 (render path profiling) requires GPU query objects, not CPU
timers. Research GPU profiling methodology before implementation.

---

### Pitfall 6: Microbenchmarks Don't Reflect Real Workloads

**What goes wrong:** Optimize isolated operations (single glyph rasterization, single atlas
lookup) that perform well in microbenchmarks but don't improve real-world frame time.

**Why it happens:** Microbenchmarks have small working sets that fit in cache. Real
workloads have cache misses, memory pressure, GPU context switches. Microbenchmark shows 50%
improvement but user sees 2% improvement.

**Consequences:**
- Optimization effort wasted on non-representative workloads
- Real bottlenecks (cache misses, GPU stalls) ignored
- Complexity increased without user-visible benefit
- Performance targets based on unrealistic scenarios

**Prevention:**
- Primary metric: FRAME TIME for realistic text rendering
- Use example applications (demo.v, stress_demo.v) as benchmarks
- Stress tests with realistic data (mixed scripts, emoji, variable fonts)
- Measure full pipeline: layout → rasterize → atlas → render
- Microbenchmarks only for understanding specific operations

**Detection:**
- Microbenchmark improvement >10% but frame time improvement <2% = CACHE EFFECT
- Compare hot loop (1000 glyphs) vs single operation time
- Profile with working set > L3 cache size (typically >8MB)

**Phase guidance:** Phase 2-4 profile realistic workloads first. Microbenchmarks allowed in
Phase 5-7 for understanding specific operations, but require real-world validation.

---

## Moderate Pitfalls

Mistakes causing delays, technical debt, or misleading conclusions.

### Pitfall 7: Invalidating Safety Work by Changing Memory Layout

**What goes wrong:** Optimization changes data structures (pack structs, reorder fields,
change allocation patterns) that interact with v1.0 memory safety fixes. Overflow checks no
longer protect the right fields. Null checks miss new code paths.

**Why it happens:** Performance optimization often involves memory layout changes (cache
line alignment, reducing padding). Easy to miss interactions with existing safety checks.

**Consequences:**
- Safety checks become ineffective
- New crash paths introduced
- Buffer overflows in optimized allocations
- Hard to debug (safety checks exist but don't trigger)

**Prevention:**
- Inventory all v1.0 safety checks before changing memory layout
- Update overflow calculations when changing struct sizes
- Re-validate null checks after allocation path changes
- Test error paths (OOM, allocation failure) after optimization

**Detection:**
- Run memory sanitizer (if available for V)
- Stress test with allocation failures
- Verify atlas size calculations match new layout

**Phase guidance:** Phase 5-7 optimization plans must include "safety check review" step.

---

### Pitfall 8: Cache Invalidation Breaking Incremental Rendering

**What goes wrong:** Optimize atlas/cache eviction strategy but break assumptions about
glyph availability. Layout assumes glyph is cached but new LRU eviction removed it. Causes
re-rasterization mid-frame or visual artifacts.

**Why it happens:** CONCERNS.md mentions "Atlas Reset Clears All Cached Glyphs" as
bottleneck. Implementing multi-page atlas or LRU eviction changes cache guarantees.

**Consequences:**
- Visual glitches (glyphs disappear/reappear)
- Performance worse than before (cache thrashing)
- Frame stutter when eviction triggers
- Difficult to reproduce (depends on usage patterns)

**Prevention:**
- Document cache invalidation boundaries (frame-level, layout-level)
- Pin glyphs needed for current frame
- Never evict during draw calls
- Test with worst-case eviction patterns
- Validate assumptions about glyph lifetime

**Detection:**
- Visual artifacts in long-running sessions
- Performance degrades over time (cache thrashing)
- Frame time spikes at irregular intervals

**Phase guidance:** Phase 6 (memory optimization) must preserve frame-boundary cache
guarantees. Eviction only at safe points.

---

### Pitfall 9: Optimizing Pango/FreeType Calls Without Understanding Internals

**What goes wrong:** Attempt to optimize FreeType/Pango call patterns (reduce calls, batch
operations, cache metrics) without understanding library internals. Break mandatory operation
sequences or internal caching.

**Why it happens:** CONCERNS.md mentions "FreeType Metrics Recomputed Per Run" as
bottleneck. Temptation to cache metrics at VGlyph level without knowing if FreeType already
caches.

**Consequences:**
- Break v1.1 FT state sequence (load→translate→render)
- Bypass FreeType's internal caches (worse performance)
- Incorrect metrics due to misunderstood Pango unit conversions
- Visual corruption from cached stale data

**Prevention:**
- Read FreeType/Pango documentation before optimizing calls
- Validate library doesn't already optimize what you're caching
- Respect v1.1 FT state sequence documentation
- Incremental optimization: measure before/after each change

**Detection:**
- Visual differences after optimization (wrong positions, sizes)
- Performance worse after "optimization" (fighting library cache)
- Inconsistent results (cached data out of sync)

**Phase guidance:** Phase 3 (atlas profiling) and Phase 2 (layout profiling) require
FreeType/Pango documentation research before optimization proposals.

---

### Pitfall 10: TTL/Timeout-Based Eviction in Frame-Driven Rendering

**What goes wrong:** Implement time-based cache eviction (TTL, LRU with timestamps) for
layout cache or glyph atlas. Works poorly for frame-driven rendering where "age" should be
frame count, not wall-clock time.

**Why it happens:** Traditional caching uses time-based eviction. Intuitive to apply same
pattern to rendering cache. Doesn't match frame-driven access patterns.

**Consequences:**
- Static text evicted during pause/resize/background
- Performance hit when returning from pause
- Inconsistent behavior (depends on frame rate)
- Memory pressure during low-frame-rate scenarios

**Prevention:**
- Use frame count for "age", not timestamps
- Layout cache: LRU based on draw count
- Atlas cache: LRU based on glyph usage per frame
- Preserve frequently-used glyphs regardless of time

**Detection:**
- Performance regression after window minimize/restore
- Different behavior at 30fps vs 60fps
- Cache effectiveness varies with frame rate

**Phase guidance:** Phase 6 (memory optimization) LRU implementation should use frame-based
aging.

---

### Pitfall 11: Ignoring Subpixel Positioning in Cache Keys

**What goes wrong:** Optimize glyph cache by removing subpixel bin from hash key (thinking
visual difference is negligible). Breaks smooth text animations and subpixel positioning
quality.

**Why it happens:** Existing cache key is `hash(font, size, glyph_id, subpixel_bin)`.
Subpixel bins (4 positions) multiply cache size by 4x. Tempting to remove for memory
savings.

**Consequences:**
- Lose subpixel positioning feature (v1.0 requirement)
- Text animation looks choppy
- Quality regression users will notice
- Break existing API guarantees

**Prevention:**
- Don't remove features for performance
- If cache size is problem, increase atlas size instead
- Profile whether subpixel cache is actual bottleneck
- Visual comparison: with/without subpixel bins

**Detection:**
- Animation looks jaggy after optimization
- Text position snaps to pixel boundaries
- Visual quality clearly worse

**Phase guidance:** Subpixel positioning is VALIDATED REQUIREMENT. Cannot be removed.

---

## Minor Pitfalls

Mistakes causing annoyance, misleading metrics, or false conclusions.

### Pitfall 12: Measuring Cold Start Instead of Steady State

**What goes wrong:** Profile first frame performance (cold cache) and treat as
representative. Optimize cold-start paths that only run once. Miss steady-state bottlenecks
that affect ongoing rendering.

**Why it happens:** Easy to profile startup. First impressions matter. But most rendering
time is steady-state (cached layouts, warm atlas).

**Consequences:**
- Optimize infrequent paths
- Ignore hot paths that dominate frame time
- Misleading before/after comparisons

**Prevention:**
- Profile frame 100-1000, not frame 1-10
- Measure steady-state after cache warm-up
- Separate cold-start metrics from steady-state metrics
- Optimize steady-state first, cold-start second

**Detection:**
- Frame 1 much slower than frame 100 (expected)
- Optimization helps frame 1 but not frame 100 (wrong target)

**Phase guidance:** All profiling phases measure steady-state (after cache warm-up).

---

### Pitfall 13: Forgetting Layout Cache Exists

**What goes wrong:** Optimize layout computation (Pango shaping, metrics) but VGlyph
already has 10,000-entry layout cache. Optimization doesn't improve frame time because
layouts are cached.

**Why it happens:** Forget that TextSystem caches layouts. See Pango calls in profiler and
assume they're bottleneck.

**Consequences:**
- Wasted optimization effort
- Miss actual bottlenecks (cache lookup overhead, hash collisions)

**Prevention:**
- Check cache hit rate before optimizing
- Understand what's cached: layouts (yes), glyphs (yes), metrics (no)
- Profile cache misses separately from cache hits

**Detection:**
- Optimization improves cold start but not steady-state
- Cache hit rate is >95% = layout computation not bottleneck

**Phase guidance:** Phase 2 (layout profiling) must measure cache hit rates first.

---

### Pitfall 14: Comparing Different Workloads

**What goes wrong:** Measure baseline with simple text ("Hello World"), measure after
optimization with complex text (emoji, RTL, vertical). Conclude huge performance difference
due to workload change, not optimization.

**Why it happens:** Want to show optimization works on "realistic" text. Change test case
between measurements.

**Consequences:**
- Invalid before/after comparison
- False performance claims
- Can't isolate optimization impact

**Prevention:**
- Lock test workload before starting optimization
- Same text, same fonts, same window size for all measurements
- Document test case in profiling plan
- Use examples/ directory for reproducible workloads

**Detection:**
- Baseline and optimized runs use different test cases
- Can't reproduce performance improvement

**Phase guidance:** Phase 2-4 must define test workloads before profiling starts. No
changes during optimization.

---

### Pitfall 15: Not Accounting for GPU Driver Variance

**What goes wrong:** Optimize GPU rendering path and see 30% improvement on NVIDIA
development machine. Users on AMD/Intel see no improvement or regression.

**Why it happens:** GPU driver behavior varies by vendor. Optimization for one driver may
hurt others. Buffer update patterns, texture formats, batch sizes have different
characteristics.

**Consequences:**
- Optimization works on dev machine but not user machines
- Platform-specific performance regressions
- Bug reports from users with different GPUs

**Prevention:**
- Test on multiple GPU vendors (NVIDIA, AMD, Intel)
- Use standard OpenGL patterns (avoid driver-specific hacks)
- Document GPU test matrix (vendor, driver version)
- Conservative optimization (avoid micro-optimizations)

**Detection:**
- Performance improvement only on specific GPU
- User reports worse performance after "optimization"

**Phase guidance:** Phase 4 (render path) optimization validation requires multi-GPU
testing.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Instrumentation | Profiling overhead in release builds | Validate zero overhead before proceeding |
| Layout profiling | Optimizing already-cached operations | Measure cache hit rate first |
| Atlas profiling | GPU-CPU sync stalls from glFinish | Use GPU query objects |
| Render profiling | Microbenchmarks vs real workloads | Profile full frame with realistic text |
| Latency optimization | Breaking v1.0/v1.1 safety checks | Safety check review mandatory |
| Memory optimization | Cache invalidation breaking rendering | Frame-boundary eviction only |
| Bottleneck addressing | Premature optimization without data | Require profiling data for every change |

---

## Integration with Existing Safety Work

VGlyph v1.0 hardened memory operations, v1.1 hardened fragile areas. Performance work must
not regress this.

**v1.0 Safety Checks to Preserve:**
- Error-returning API (`!GlyphAtlas`)
- Dimension overflow validation before allocation
- 1GB max allocation limit
- grow() error propagation
- Null checks after vcalloc

**v1.1 Debug Guards (Can Optimize):**
- Iterator exhaustion tracking (debug-only)
- AttrList leak counter (debug-only)
- FreeType state validation (debug-only)

These are already zero-overhead in release. No optimization needed or allowed.

**v1.1 Mandatory Sequences (UNTOUCHABLE):**
- FreeType load→translate→render sequence
- AttrList copy→unref pairing
- Iterator defer-based cleanup

These prevent crashes/UB. Cannot be "optimized away" under any circumstances.

---

## Confidence Assessment

| Category | Confidence | Source |
|----------|------------|--------|
| GPU profiling pitfalls | HIGH | OpenGL documentation, Khronos forums, NVIDIA developer docs |
| Debug vs release profiling | HIGH | Flutter 2026 article, general profiling best practices |
| Text rendering cache issues | MEDIUM | VGlyph CONCERNS.md, general rendering experience |
| FreeType optimization pitfalls | MEDIUM | FreeType FAQ, forum discussions (not all 2026) |
| Pango optimization pitfalls | LOW | Limited recent documentation, extrapolating from general patterns |

**Low confidence areas needing deeper research:**
- Pango internal caching behavior (metrics, layout results)
- FreeType 2.13+ performance characteristics
- V language-specific profiling tools and patterns

---

## Sources

### Text Rendering Performance
- [text-rendering: optimizeLegibility is Decadent and Depraved](https://www.bocoup.com/blog/text-rendering)
- [LearnOpenGL - Text Rendering](https://learnopengl.com/In-Practice/Text-Rendering)
- [UI Performance: Improving Text Rendering](https://medium.com/lalafo-engineering/ui-performance-improving-text-rendering-4715ca1dd2bd)

### OpenGL Performance Anti-Patterns
- [OpenGL text rendering performance optimization](https://github.com/Samson-Mano/opengl_textrendering)
- [OpenGL text rendering performance questions](https://community.khronos.org/t/what-are-my-options-to-improve-text-rendering-performance/70927)
- [Fast text rendering in OpenGL](https://www.sjbaker.org/steve/omniv/opengl_text.html)

### Profiling Pitfalls
- [Flutter App Performance: Profiling in 2026](https://startup-house.com/blog/flutter-app-performance)
- [How Impeller Is Transforming Flutter UI Rendering in 2026](https://dev.to/eira-wexford/how-impeller-is-transforming-flutter-ui-rendering-in-2026-3dpd)

### GPU Pipeline Stalls
- [Graphics Pipeline Performance](https://developer.nvidia.com/gpugems/gpugems/part-v-performance-and-practicalities/chapter-28-graphics-pipeline-performance)
- [OpenGL Synchronization Wiki](https://www.khronos.org/opengl/wiki/Synchronization)
- [Vulkan Pipeline Barriers](https://docs.vulkan.org/samples/latest/samples/performance/pipeline_barriers/README.html)

### Continuous Profiling Overhead
- [Continuous Profiling in Go with pprof and Pyroscope](https://oneuptime.com/blog/post/2026-01-07-go-continuous-profiling/view)
- [Profiling in Production with eBPF](https://medium.com/@yashbatra11111/profiling-in-production-without-killing-performance-ebpf-continuous-profiling-5a92a8610769)
- [Profiling Performance Overhead](https://docs.sentry.io/product/explore/profiling/performance-overhead/)

### Microbenchmark Pitfalls
- [Beware microbenchmarks bearing gifts](https://abseil.io/fast/39)
- [The Early Microbenchmark Catches the Bug](https://dl.acm.org/doi/10.1145/3603166.3632128)

### Cache Invalidation
- [The Cache Invalidation Nightmare](https://triotech.com/the-cache-invalidation-nightmare-what-youre-likely-doing-wrong/)
- [Cache Invalidation: The Silent Performance Killer](https://dev.to/ferdinandodhiambo/cache-invalidation-the-silent-performance-killer-1fl8)
- [Top 10 Common Caching Mistakes](https://moldstud.com/articles/p-top-10-common-caching-mistakes-to-avoid-for-enhanced-performance)

### FreeType/Pango Performance
- [FreeType FAQ](https://freetype.org/freetype2/docs/ft2faq.html)
- [FreeType Performance Issue Discussion](https://forum.segger.com/index.php/Thread/9214-Performance-issue-with-FreeType-2-12-1/)
- [Pango Dependencies and Performance](https://gitlab.gnome.org/GNOME/pango/-/issues/368)

### Font Glyph Caching
- [Font Stash: Dynamic Font Glyph Cache](https://github.com/akrinke/Font-Stash)
- [Warp: Kerning and Glyph Atlases](https://www.warp.dev/blog/adventures-text-rendering-kerning-glyph-atlases)
- [Font flickering due to glyph cache](https://github.com/defold/defold/issues/9720)
