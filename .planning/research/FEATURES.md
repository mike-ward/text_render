# Feature Landscape: Text Rendering Performance Optimization

**Domain:** Text rendering performance profiling and optimization
**Researched:** 2026-02-02
**Project:** VGlyph v1.2
**Confidence:** MEDIUM (WebSearch verified with technical sources, some LOW confidence areas
flagged)

## Executive Summary

Performance optimizations for text rendering fall into four categories: instrumentation (measure
first), latency optimizations (frame time), memory optimizations (cache efficiency), and GPU
optimizations (texture management). Research shows most impact comes from atlas management
(multi-page vs reset), cache strategies (metrics caching, glyph deduplication), and GPU stall
elimination (async texture updates).

VGlyph's known bottlenecks align with industry patterns: atlas reset (GPU stalls), hash
collisions (cache misses), FreeType metrics recomputation (FFI overhead), emoji bitmap scaling
(CPU overhead). Industry solutions: multi-page atlases, shelf packing, metrics caching, GPU
scaling.

## Table Stakes

Features users expect from performance work. Missing = incomplete optimization effort.

| Feature | Why Expected | Complexity | Impact | Notes |
|---------|--------------|------------|--------|-------|
| **Profiling instrumentation** | Can't optimize without metrics | Low | Foundation | Tracy/Optick integration ~15ns overhead |
| **Frame time metrics** | 16.67ms budget for 60fps | Low | Critical | CPU/GPU split visibility required |
| **Memory allocation tracking** | Atlas/cache growth visibility | Low | Critical | Peak/current/growth rate |
| **Per-operation timing** | Identify hotspots | Medium | High | Layout/rasterize/upload/draw phases |
| **Cache hit/miss rates** | Validate cache effectiveness | Low | High | Glyph cache, metrics cache, layout cache |
| **Atlas utilization metrics** | Fragmentation detection | Medium | Medium | Used/total pixels, page count |

**Rationale:** Industry standard profiling requires instrumentation first. Without metrics, all
optimization is guesswork. 16.67ms frame budget is non-negotiable for 60fps. Cache visibility
reveals effectiveness.

## Differentiators

Optimizations providing significant measurable impact. Prioritize by ROI.

### High Impact (address known bottlenecks)

| Feature | Value Proposition | Complexity | Expected Gain | VGlyph Bottleneck |
|---------|-------------------|------------|---------------|-------------------|
| **Multi-page atlas** | Avoid reset stalls | High | Eliminate GPU pipeline stalls | Atlas reset (CONCERNS:64-70) |
| **Metrics caching** | Reduce FFI overhead | Low | ~10-20% layout speedup | FreeType metrics (CONCERNS:79-83) |
| **Glyph cache collision handling** | Prevent visual corruption | Medium | Correctness > perf | Hash collisions (CONCERNS:72-77) |
| **Async texture updates** | Eliminate GPU stalls | High | Eliminate glTexSubImage stalls | Atlas updates during frame |
| **GPU bitmap scaling** | Offload emoji scaling | Medium | ~50% emoji rendering speedup | Bicubic per frame (CONCERNS:85-89) |

**Rationale:**
- Multi-page atlas: WebRender reduced from 5 textures to 2-3 with shelf packing, eliminated reset
  stalls. VGlyph atlas reset clears all cached glyphs mid-frame causing GPU stalls.
- Metrics caching: HarfBuzz 4.4.0 showed 20% speedup from caching format 2 lookups. VGlyph calls
  FreeType FFI per glyph run.
- Collision handling: Industry uses secondary validation or collision chains. VGlyph uses u64 hash
  without collision detection (silent corruption).
- Async updates: GPU stalls from glTexSubImage documented. Separate static/dynamic atlases prevent
  stalls.
- GPU scaling: Moves bicubic interpolation to fragment shader. VGlyph scales BGRA every frame on
  CPU.

### Medium Impact (general optimizations)

| Feature | Value Proposition | Complexity | Expected Gain | Notes |
|---------|-------------------|------------|---------------|-------|
| **Shelf packing allocator** | Reduce atlas fragmentation | Medium | 30-50% better packing | WebRender "simple shelf" production choice |
| **LRU eviction** | Prevent unbounded growth | Medium | Memory bounds | Cache currently unbounded (CONCERNS:135-139) |
| **Subpixel grid optimization** | Reduce variant explosion | Low | 3x vs unbounded | Warp uses ⅓ pixel bins (0.0, 0.33, 0.66) |
| **Workload separation** | Optimize per-workload | Medium | Batch efficiency | Glyphs vs images different shaders |
| **Shape plan caching** | Reduce HarfBuzz overhead | Medium | ~10% shaping speedup | HarfBuzz provides hb_shape_plan_create_cached |

**Rationale:**
- Shelf packing: Mozilla reduced glyph atlas from "multiple textures" to "one or two" with 128x128
  regions and rectangular slabs.
- LRU: Standard cache eviction. VGlyph cache map unbounded, only cleared on page reset.
- Subpixel: Warp documented 3-bin approach balances quality vs memory. VGlyph uses 4 bins already.
- Workload separation: WebRender separated glyphs/images for shader batching. VGlyph atlas mixes
  workloads.
- Shape plan: HarfBuzz supports plan caching. VGlyph may recreate plans.

### Lower Impact (polish optimizations)

| Feature | Value Proposition | Complexity | Expected Gain | Notes |
|---------|-------------------|------------|---------------|-------|
| **Temporal accumulation** | Spread sampling cost | Medium | Amortize per-frame cost | 8+4+2+1 samples over frames |
| **Curve access acceleration** | Reduce intersection tests | High | Vector texture specific | Not applicable to bitmap atlas |
| **Distance field rendering** | Scalable text quality | High | Quality not performance | Harder on GPU than atlas |
| **Z-order atlas packing** | Efficient allocation | Medium | ~50% for thin glyphs | Morton codes, transposed optimization |

**Rationale:**
- Temporal: Spreads 512 samples across frames. VGlyph uses bitmap atlas (immediate quality).
- Curve acceleration: Vector texture optimization. VGlyph rasterizes to bitmaps.
- Distance fields: Higher quality at cost of GPU. VGlyph prioritizes performance.
- Z-order: Efficient for power-of-two regions. VGlyph likely benefits more from shelf packing.

## Anti-Features

Optimizations that add complexity without proportional benefit for VGlyph.

| Anti-Feature | Why Avoid | What Instead | Notes |
|--------------|-----------|--------------|-------|
| **Vector texture rendering** | Harder on GPU, complex | Bitmap atlas | VGlyph uses FreeType rasterization |
| **Thread pool for rasterization** | V is single-threaded | Profile first | V design constraint |
| **Custom allocator for atlas** | Complexity vs gain | System allocator + validation | VGlyph has overflow checks |
| **SDF (Signed Distance Fields)** | GPU cost > bitmap | Cache multiple sizes | Quality feature not performance |
| **Supersampling 3x** | Enlarges bitmaps, reduces packing | Subpixel bins (existing) | VGlyph has 4-bin subpixel |
| **Pre-rendered atlases** | App size bloat, inflexible | Dynamic atlas | Character set unknown at build |
| **Interpolation between variants** | Complex GPU shader, multi-texture | Snap to nearest bin | VGlyph snaps already |

**Rationale:**
- Vector textures: Research shows "harder on GPU than atlas textures." VGlyph has working bitmap
  pipeline.
- Thread pool: V language single-threaded by design (PROJECT.md). No benefit.
- Custom allocator: Premature optimization. VGlyph has overflow validation, no malloc failures
  observed.
- SDF: Quality optimization, GPU cost higher. Research: "minimize aliasing" not performance.
- Supersampling: Research: "enlarge glyph bitmaps, reducing atlas packing efficiency." VGlyph has
  subpixel bins.
- Pre-rendered: Research shows "application size impact" and "requires all glyphs at build."
  VGlyph runtime text unknown.
- Interpolation: Warp rejected: "reading from multiple atlas textures simultaneously." Complexity
  not worth marginal quality.

## Feature Dependencies

```
Instrumentation (Foundation)
  ├─> Frame time metrics
  ├─> Memory tracking
  ├─> Cache hit/miss rates
  └─> Atlas utilization

Metrics → Optimization Decisions
  ├─> Hotspot identification
  └─> Before/after validation

Atlas optimizations
  ├─> Multi-page atlas → Requires shelf packing
  ├─> Shelf packing → Independent optimization
  └─> Async updates → Requires workload separation

Cache optimizations
  ├─> Metrics caching → Independent
  ├─> Collision handling → Independent
  └─> LRU eviction → Independent

GPU optimizations
  ├─> Bitmap scaling → Independent
  └─> Async updates → Depends on multi-page
```

## Performance Metrics That Matter

### Critical Metrics (16.67ms budget)

| Metric | Target | Why | Measurement |
|--------|--------|-----|-------------|
| **Frame time** | <16.67ms | 60fps requirement | Per-frame profiler scope |
| **Layout time** | <8ms | Half frame budget | Pango shaping + caching |
| **Atlas upload time** | <2ms | GPU stall risk | glTexSubImage duration |
| **Draw call time** | <4ms | Rendering overhead | GPU timeline |
| **Cache hit rate** | >95% | Validate effectiveness | Hits/(hits+misses) |

**Rationale:** Research shows 16.67ms per frame for 60fps. GPU text rendering benchmarked at
0.1ms for full screen (4K) once cached, suggesting cache effectiveness critical.

### Memory Metrics

| Metric | Target | Why | Measurement |
|--------|--------|-----|-------------|
| **Atlas utilization** | >70% | Fragmentation check | Used/total pixels |
| **Cache entry count** | Bounded | Prevent unbounded growth | Map size |
| **Peak allocation** | <1GB | VGlyph limit | Max atlas + cache size |
| **Allocation growth rate** | Stable | Leak detection | Delta per 1000 frames |

**Rationale:** WebRender research emphasized packing efficiency. VGlyph has 1GB max allocation
limit (PROJECT.md), cache unbounded (CONCERNS.md).

### Cache Effectiveness Metrics

| Metric | Target | Why | Measurement |
|--------|--------|-----|-------------|
| **Glyph cache hit rate** | >95% | Atlas effectiveness | Cache hits/lookups |
| **Metrics cache hit rate** | >99% | Font reuse common | Cached/FFI calls |
| **Layout cache hit rate** | >80% | Text reuse | Cached/shaped |
| **Atlas reset frequency** | 0/frame | Avoid stalls | Resets per 1000 frames |

**Rationale:** High hit rates validate caching effectiveness. Atlas reset frequency directly
correlates to GPU stalls (CONCERNS.md bottleneck).

## VGlyph-Specific Recommendations

### Immediate Priorities (Known Bottlenecks)

1. **Atlas reset stalls** (CONCERNS:64-70)
   - Impact: GPU pipeline stalls, visual artifacts
   - Solution: Multi-page atlas with shelf packing
   - Expected gain: Eliminate mid-frame stalls
   - Confidence: HIGH (WebRender evidence)

2. **Hash collisions** (CONCERNS:72-77)
   - Impact: Visual corruption (silent)
   - Solution: Secondary validation (glyph_index, subpixel_bin)
   - Expected gain: Correctness
   - Confidence: HIGH (industry standard)

3. **Metrics recomputation** (CONCERNS:79-83)
   - Impact: Repeated FFI overhead
   - Solution: Cache keyed by (font, language)
   - Expected gain: 10-20% layout speedup
   - Confidence: MEDIUM (HarfBuzz evidence)

4. **Emoji bitmap scaling** (CONCERNS:85-89)
   - Impact: CPU overhead per frame
   - Solution: GPU scaling or cache scaled bitmaps
   - Expected gain: 50% emoji rendering
   - Confidence: MEDIUM (GPU offload principle)

### Instrumentation Requirements

Before optimization, instrument:
- Frame time breakdown (layout/rasterize/upload/draw)
- Cache hit rates (glyph/metrics/layout)
- Atlas utilization and fragmentation
- Memory allocation tracking

**Rationale:** Research emphasizes "measure first." Without metrics, optimization is speculation.

### Post-Optimization Validation

Each optimization must show:
- Before/after frame time comparison
- Cache hit rate improvement (if cache optimization)
- Memory reduction (if memory optimization)
- No visual regression (screenshot comparison)

## MVP Optimization Recommendation

For v1.2 milestone, prioritize instrumentation + high-impact optimizations:

**Phase 1: Instrumentation (foundation)**
1. Tracy/Optick integration for profiling
2. Frame time breakdown metrics
3. Cache hit/miss tracking
4. Memory allocation tracking

**Phase 2: Address Critical Bottlenecks**
1. Glyph cache collision handling (correctness)
2. Metrics caching (FFI reduction)
3. Multi-page atlas (GPU stall elimination)
4. GPU emoji scaling (CPU offload)

**Phase 3: Memory Optimizations**
1. LRU eviction for unbounded cache
2. Shelf packing allocator
3. Workload separation (glyphs vs images)

**Defer to post-v1.2:**
- Temporal accumulation (quality > performance)
- Distance fields (quality feature)
- Shape plan caching (measure first)
- Z-order packing (shelf packing likely better)

**Rationale:** Instrument first (measure), address known bottlenecks (CONCERNS.md), defer
speculative optimizations until proven necessary.

## Confidence Assessment

| Topic | Confidence | Reason |
|-------|------------|--------|
| Atlas management | HIGH | WebRender/Warp detailed implementations |
| Cache strategies | MEDIUM | HarfBuzz data, industry patterns |
| GPU optimizations | MEDIUM | General GPU principles, less text-specific data |
| Metrics targets | LOW | Limited 2026 text rendering benchmarks |
| VGlyph applicability | HIGH | CONCERNS.md directly maps to research |

**Gaps:**
- Limited 2026-specific text rendering benchmarks (mostly 3D rendering data)
- FreeType/Pango performance profiling data sparse (WebSearch only)
- V language profiling integration unknown (need V-specific research)

**Verification needed:**
- Tracy/Optick compatibility with V language FFI
- FreeType metrics caching implementation details
- Multi-page atlas texture limits (OpenGL version specific)

## Sources

**Atlas Management:**
- [Warp Adventures in Text Rendering](https://www.warp.dev/blog/adventures-text-rendering-kerning-glyph-atlases)
- [WebRender Texture Atlas Allocation](https://mozillagfx.wordpress.com/2021/02/04/improving-texture-atlas-allocation-in-webrender)
- [GPU Text Rendering Techniques](https://www.monotype.com/resources/expertise/gpu-text-rendering-techniques)
- [Monotype Labs GPU Text Rendering](https://medium.com/@monotype.labs/gpu-text-rendering-techniques-563533646891)

**Performance Profiling:**
- [Rendering Crispy Text On The GPU](https://osor.io/text)
- [Android GPU Rendering Inspection](https://developer.android.com/topic/performance/rendering/inspect-gpu-rendering)
- [Tracy Profiler](https://github.com/aclysma/profiling)

**Cache Optimization:**
- [HarfBuzz 12.3 Performance Improvements](https://www.phoronix.com/news/HarfBuzz-12.3-Released)
- [HarfBuzz Plans and Caching](https://harfbuzz.github.io/shaping-plans-and-caching.html)
- [LFU vs LRU Cache Eviction](https://redis.io/blog/lfu-vs-lru-how-to-choose-the-right-cache-eviction-policy/)

**Texture Packing:**
- [Texture Atlas Packing Algorithm](https://lisyarus.github.io/blog/posts/texture-packing.html)
- [Texture Atlas Optimization in 3D](https://garagefarm.net/blog/texture-atlas-optimizing-textures-in-3d-rendering)

**Emoji/Color Glyphs:**
- [Color Emoji FreeType Rendering](https://gist.github.com/jokertarot/7583938)
- [Alacritty Color Emoji PR](https://github.com/alacritty/alacritty/pull/3011)

**GPU Stalls:**
- [NVIDIA GPU Pipeline Optimization](https://developer.nvidia.com/gpugems/gpugems/part-v-performance-and-practicalities/chapter-28-graphics-pipeline-performance)
- [ARM Mali Dynamic Resource Updates](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/mali-performance-6-efficiently-updating-dynamic-resources)

---

*Research complete. Features categorized for v1.2 roadmap creation.*
