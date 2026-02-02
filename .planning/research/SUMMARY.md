# Project Research Summary

**Project:** VGlyph v1.2 — Performance Profiling & Optimization
**Domain:** Text rendering performance (Pango/FreeType/OpenGL)
**Researched:** 2026-02-02
**Confidence:** HIGH

## Executive Summary

VGlyph v1.2 focuses on lightweight performance profiling for text rendering bottlenecks identified in
CONCERNS.md: atlas reset stalls, glyph cache hash collisions, FreeType metrics recomputation, and
emoji bitmap scaling. Research shows V's built-in profiling (`-profile` flag, `benchmark`/`time`
modules) provides sufficient instrumentation without external dependencies, matching the project's
minimal-stack philosophy.

Recommended approach: Instrument first using V's zero-overhead conditional compilation (`$if profile
?`), measure to validate suspected bottlenecks, optimize only proven hot paths, validate correctness
preserved. Industry precedents (WebRender atlas optimization, Warp glyph caching) confirm atlas
management and cache strategies as highest ROI optimization targets. Critical risk: breaking v1.0/v1.1
safety guarantees (memory validation, FreeType state sequences) while chasing performance gains.

Key architecture decision: V's compile-time conditional removal (`-d profile`) achieves true zero
overhead in release builds. Metrics collected at component boundaries (Layout, Atlas, Renderer),
aggregated in Context. Four hot paths identified: Layout computation (Pango), Atlas operations
(FreeType + texture), Render path (OpenGL), Cache management. Optimization order data-driven: profile
→ analyze → optimize → validate. Expected bottlenecks validated by research: atlas reset causes GPU
stalls (WebRender evidence), hash collisions cause correctness issues (industry standard secondary
validation), metrics recomputation adds FFI overhead (HarfBuzz 20% speedup from caching).

## Key Findings

### Recommended Stack

V provides native profiling sufficient for VGlyph's needs. No external profilers required.

**Core tools:**
- `v -profile`: Function-level profiling for bottleneck discovery
- `benchmark` module: Manual instrumentation for targeted measurements
- `time.StopWatch`: High-resolution inline timing at critical paths
- Conditional compilation: `$if profile ?` for zero release overhead

**What NOT to add:**
- External profilers (Valgrind, perf, VTune) — overkill, adds 10-50x slowdown
- Heavy frameworks (Tracy, custom telemetry) — premature, V's text output sufficient
- GPU profilers (RenderDoc, Nsight) — only if CPU optimization exhausted (current bottlenecks
  CPU-side)

**Integration:** Conditional compilation (`-d profile`) removes instrumentation code entirely in
release builds. No runtime checks, no function call overhead. Metrics struct always compiled but
collection removed unless flag passed.

### Expected Features

Performance work categorized into instrumentation (foundation), high-impact optimizations (known
bottlenecks), medium-impact (general improvements), and anti-features (avoid complexity).

**Must have (table stakes):**
- Profiling instrumentation — can't optimize without metrics
- Frame time metrics — 16.67ms budget for 60fps
- Memory tracking — atlas/cache growth visibility
- Cache hit/miss rates — validate effectiveness
- Per-operation timing — identify hotspots

**High impact (address known bottlenecks):**
- Multi-page atlas — avoid reset stalls (CONCERNS:64-70)
- Metrics caching — reduce FFI overhead (CONCERNS:79-83), expected 10-20% speedup
- Glyph cache collision handling — correctness first (CONCERNS:72-77)
- GPU bitmap scaling — offload emoji (CONCERNS:85-89), expected 50% speedup

**Medium impact (general optimizations):**
- Shelf packing allocator — 30-50% better atlas packing
- LRU eviction — bound unbounded cache (CONCERNS:135-139)
- Subpixel grid optimization — reduce variant explosion
- Shape plan caching — ~10% shaping speedup

**Defer (anti-features for VGlyph):**
- Vector texture rendering — harder on GPU, VGlyph uses bitmap atlas
- Thread pool — V single-threaded by design
- Custom allocators — premature, system allocator works
- SDF rendering — quality feature not performance
- Pre-rendered atlases — inflexible, app size bloat

### Architecture Approach

Four primary hot paths with distinct optimization strategies.

**Major components:**
1. **Layout (layout.v)** — Pango shaping, expensive O(n), cached by user code. Instrument:
   pango_setup, iterate, hit_test_rects (O(n²) suspect). Optimization: validate cache hit rate
   before optimizing, skip hit-test if unused.

2. **Atlas (glyph_atlas.v)** — Texture management, shelf packing, amortized O(1) but spiky on
   grow/reset. Instrument: insert_time, grow_time, reset_count, utilization. Optimization: multi-page
   to avoid reset, shelf packing for fragmentation.

3. **Renderer (renderer.v)** — Per-frame hot loop, cache lookups, FreeType rasterization. Instrument:
   draw_time, rasterize_time, commit_time, upload_time, cache_hit_rate. Optimization: collision
   detection, partial texture uploads.

4. **Context (context.v)** — Font metrics queries, potentially cacheable. Instrument: font_query_time,
   query_count. Optimization: cache if frequent.

**Zero-overhead pattern:** Metrics struct behind `$if profile ?`, defer-based timing for accuracy
even with early returns, scoped counters for hot loops. Release build removes all instrumentation at
compile time.

### Critical Pitfalls

Top 5 mistakes causing rewrites or breaking safety:

1. **Profiling in debug mode** — Debug builds 5-10x slower due to v1.1 validation guards. Always
   profile in release (`v -prod`). Detection: compare debug vs release baseline. Prevention: validate
   release mode before measurements.

2. **Optimizing before profiling** — "Obvious" optimizations often wrong. Intuition about bottlenecks
   unreliable with FreeType/Pango. Prevention: profile FIRST, require data justification for every
   optimization. Phase ordering: instrumentation → profiling → optimization.

3. **Breaking correctness for performance** — Removing v1.0 safety checks (overflow validation, null
   checks) or v1.1 sequences (FreeType load→translate→render). Prevention: release-mode safety checks
   UNTOUCHABLE. Tests + visual validation mandatory after optimization.

4. **Profiling overhead in production** — Instrumentation left in release builds slows code. Prevention:
   ALL profiling behind `$if profile ?`. Validate zero overhead before proceeding. Search for timing
   code not behind conditional.

5. **GPU-CPU pipeline stalls** — Using glFinish() for profiling synchronizes pipeline, making
   measurements 10-100x slower than actual async performance. Prevention: use GPU query objects, never
   glFinish() in profiling code. Separate CPU time from GPU time.

## Implications for Roadmap

Based on research, v1.2 should follow profile → optimize → validate cycle with 4 phases.

### Phase 1: Instrumentation
**Rationale:** Must measure before optimizing. Establish baseline, validate suspected bottlenecks.
Zero-overhead foundation required.

**Delivers:** V conditional profiling framework, metrics collection in all hot paths, baseline
performance report.

**Features:** Frame time metrics, cache hit/miss tracking, memory allocation tracking, per-operation
timing (layout/rasterize/upload/draw).

**Stack:** V `benchmark` module, `time.StopWatch`, conditional compilation (`$if profile ?`).

**Avoids:** Pitfall #4 (profiling overhead in production) — validate zero overhead before proceeding.
Pitfall #1 (debug mode profiling) — confirm release mode measurements.

### Phase 2: Profiling Analysis
**Rationale:** Data-driven optimization planning. Identify actual bottlenecks vs suspected. Prioritize
by ROI.

**Delivers:** Bottleneck identification, optimization plan ranked by expected impact, validation that
CONCERNS.md suspicions are real.

**Addresses:** All 4 suspected bottlenecks (atlas reset, hash collisions, metrics recomputation, emoji
scaling). Confirms or refutes each with measurements.

**Avoids:** Pitfall #2 (premature optimization) — requires profiling data showing bottleneck.
Pitfall #6 (microbenchmarks) — profile realistic workloads (stress_demo.v).

### Phase 3: Critical Bottleneck Fixes
**Rationale:** Address highest-impact issues first. Correctness issues (hash collisions) before
performance. Known stalls (atlas reset, metrics FFI) have strong research evidence.

**Delivers:** Glyph cache collision detection (correctness), metrics caching (10-20% expected), atlas
reset elimination or deferral (GPU stall removal).

**Uses:** FreeType metrics cache (map[string]FTMetrics), secondary key validation for hash collisions,
multi-page atlas or deferred reset strategy.

**Implements:** Renderer collision detection (CONCERNS:72-77), Context metrics cache (CONCERNS:79-83),
Atlas reset deferral (CONCERNS:64-70).

**Avoids:** Pitfall #3 (breaking correctness) — collision detection is correctness fix, not
optimization. Pitfall #9 (FreeType internals) — validate FreeType doesn't already cache before
duplicating.

### Phase 4: Memory Optimization
**Rationale:** Unbounded cache growth needs bounds (CONCERNS:135-139). Shelf packing improves
utilization without complexity explosion. GPU emoji scaling offloads CPU.

**Delivers:** LRU eviction for layout/glyph caches, shelf packing allocator, GPU bitmap scaling
(fragment shader).

**Addresses:** Memory bounds (LRU), atlas fragmentation (shelf packing), CPU emoji overhead (GPU
offload).

**Avoids:** Pitfall #8 (cache invalidation breaking rendering) — frame-boundary eviction only.
Pitfall #10 (TTL in frame-driven rendering) — use frame count not timestamps. Pitfall #11 (removing
subpixel) — subpixel positioning is VALIDATED REQUIREMENT.

### Phase Ordering Rationale

- **Why instrumentation first:** Can't optimize without data. Zero-overhead validation prevents
  shipping slower code.
- **Why analysis before optimization:** Avoids premature optimization pitfall. Data-driven decisions.
- **Why critical fixes before general:** Hash collisions are correctness issues. Atlas reset has
  strongest research evidence (WebRender). Metrics caching is low-risk high-ROI.
- **Why memory last:** Requires stable baseline. LRU eviction changes cache guarantees (risky).
  Shelf packing is algorithmic change (needs careful validation).

### Research Flags

**Phases needing deeper research:**
- **Phase 3 (Critical):** Multi-page atlas implementation details. WebRender uses 128x128 regions
  with shelf packing but VGlyph constraints differ. May need OpenGL texture limits research.
- **Phase 4 (Memory):** Shelf packing algorithm selection (simple shelf vs skyline vs guillotine).
  WebRender chose "simple shelf" but tradeoffs unclear.

**Standard patterns (skip research):**
- **Phase 1 (Instrumentation):** V conditional compilation well-documented. Profiling patterns
  established.
- **Phase 2 (Analysis):** Data analysis, no implementation. Standard profiling methodology.
- **Phase 3 (Metrics cache, collision):** Hash map caching and secondary key validation are standard
  patterns.
- **Phase 4 (LRU):** Well-documented data structure. V map + doubly-linked list pattern established.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | V documentation verified, APIs confirmed, conditional compilation tested |
| Features | MEDIUM | Industry precedents strong (WebRender, Warp), VGlyph applicability high, but some expected gains estimated |
| Architecture | HIGH | Code inspection + data flow analysis, hot path identification clear, zero-overhead pattern verified |
| Pitfalls | HIGH | Cross-referenced with v1.0/v1.1 work, GPU profiling pitfalls well-documented, safety preservation critical |

**Overall confidence:** HIGH

### Gaps to Address

**During Phase 2 (Analysis):**
- Actual cache hit rates unknown until instrumented. If >95%, layout optimization deprioritized.
- GPU vs CPU bottleneck balance unclear. If GPU-bound, atlas upload optimization prioritized.

**During Phase 3 (Critical):**
- FreeType internal caching behavior for metrics unclear. Validate doesn't already cache before
  duplicating effort.
- Multi-page atlas OpenGL texture count limits vary by platform (need GL_MAX_TEXTURE_IMAGE_UNITS
  check).

**During Phase 4 (Memory):**
- Optimal LRU cache sizes unknown. Need empirical testing to set layout cache (currently 10,000) and
  glyph cache bounds.
- Shelf packing algorithm choice (simple shelf vs alternatives) needs benchmarking with VGlyph's glyph
  size distribution.

**Validation throughout:**
- GPU driver variance (NVIDIA vs AMD vs Intel). Pitfall #15 warns optimization may work on dev machine
  but regress on other GPUs.
- Visual regression testing strategy undefined. Need screenshot comparison for post-optimization
  validation.

## Sources

### Primary (HIGH confidence)

**V Language Profiling:**
- [V Documentation - Tools](https://docs.vlang.io/tools.html) — -profile flag, module APIs
- [V Documentation - Performance Tuning](https://docs.vlang.io/performance-tuning.html) — compiler
  flags, attributes
- [V Documentation - Conditional Compilation](https://docs.vlang.io/conditional-compilation.html) —
  `$if debug {}` pattern verified
- [V benchmark module](https://modules.vlang.io/benchmark.html) — API reference
- [V time module](https://modules.vlang.io/time.html) — StopWatch API

**Text Rendering Optimization:**
- [WebRender Texture Atlas Allocation](https://mozillagfx.wordpress.com/2021/02/04/improving-texture-atlas-allocation-in-webrender/)
  — shelf packing, slab sizes, 30% improvement
- [Warp Adventures in Text Rendering](https://www.warp.dev/blog/adventures-text-rendering-kerning-glyph-atlases)
  — glyph atlas, LRU eviction, lazy rasterization
- [LearnOpenGL - Text Rendering](https://learnopengl.com/In-Practice/Text-Rendering) — texture atlas
  batching, state change minimization

**GPU Performance:**
- [NVIDIA GPU Pipeline Optimization](https://developer.nvidia.com/gpugems/gpugems/part-v-performance-and-practicalities/chapter-28-graphics-pipeline-performance)
  — pipeline stalls, synchronization
- [ARM Mali Dynamic Resource Updates](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/mali-performance-6-efficiently-updating-dynamic-resources)
  — texture upload performance

### Secondary (MEDIUM confidence)

**Cache Optimization:**
- [HarfBuzz 12.3 Performance](https://www.phoronix.com/news/HarfBuzz-12.3-Released) — 20% speedup
  from caching
- [LRU Cache Implementation](https://www.educative.io/blog/implement-least-recently-used-cache) —
  data structure patterns
- [Open Addressing Collision Resolution](https://www.geeksforgeeks.org/dsa/open-addressing-collision-handling-technique-in-hashing/)
  — hash collision strategies

**Profiling Techniques:**
- [Instrumentation-Based Profiling](https://www.computerenhance.com/p/instrumentation-based-profiling)
  — methodology
- [Roll your own memory profiling](https://gaultier.github.io/blog/roll_your_own_memory_profiling.html)
  — manual tracking patterns
- [Flutter App Performance Profiling 2026](https://startup-house.com/blog/flutter-app-performance) —
  debug vs release pitfall

**Profiling Overhead:**
- [Rust metrics crate](https://docs.rs/metrics) — "incredibly low overhead when no recorder installed"
- [hotpath-rs](https://github.com/pawurb/hotpath-rs) — "zero-cost when disabled through feature flags"

### Tertiary (LOW confidence)

**Performance Benchmarks:**
- [GPU vs CPU Bitmap Performance](https://journalofcloudcomputing.springeropen.com/articles/10.1186/s13677-020-00191-w)
  — 11.5x average speedup (2020 data, needs validation)
- [FreeType Performance](https://groups.google.com/g/Golang-Nuts/c/oqRV5P-HQIo/m/gkmbNp1pBwAJ)
  — community discussion, not official

**Pango Optimization:**
- [Pango LLVM BOLT](https://www.phoronix.com/forums/forum/phoronix/latest-phoronix-articles/1451706-llvm-bolt-optimizations-net-~6-improvement-for-gnome-s-pango)
  — ~6% improvement (post-link optimization, not applicable to V)

---
*Research completed: 2026-02-02*
*Ready for roadmap: yes*
