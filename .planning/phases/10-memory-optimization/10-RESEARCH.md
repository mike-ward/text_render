# Phase 10: Memory Optimization - Research

**Researched:** 2026-02-02
**Domain:** Cache memory management with LRU eviction
**Confidence:** HIGH

## Summary

Bounded cache with LRU eviction is standard pattern for memory-constrained graphics systems. Glyph cache currently unbounded (map[u64]CachedGlyph) grows without limit, creating memory leak risk. Phase adds configurable max entries with frame-counter-based LRU tracking matching existing atlas page pattern.

Research confirmed two established patterns in codebase: (1) MetricsCache uses access_order array for LRU tracking (simple, proven), (2) AtlasPage uses frame counter for age tracking (zero-overhead reads, single increment per frame). Frame counter pattern better fit for glyph cache hotpath (read-heavy, O(1) lookup vs O(n) filter operation).

User decisions locked: 4096 default, global limit, init-time config, frame counter tracking, holes-in-atlas-OK. Research focused on eviction timing, batch size, minimum enforcement, instrumentation.

**Primary recommendation:** On-insert single eviction with frame counter LRU, 256 minimum, eviction count instrumentation.

## Standard Stack

No external libraries - pure V language implementation using existing patterns.

### Core Patterns (from codebase)
| Pattern | Location | Purpose | When to Use |
|---------|----------|---------|-------------|
| Frame counter LRU | glyph_atlas.v AtlasPage | Track age via u64 frame_counter | Read-heavy caches in frame-based systems |
| Access order array LRU | context.v MetricsCache | Track order via []u64 access_order | Small caches where O(n) filter acceptable |
| Map-based cache | renderer.v | Primary storage via map[u64]T | All hash-based caches |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Frame counter | Access order array | Array requires O(n) filter on every get (unacceptable for glyph cache hotpath) |
| On-insert eviction | Periodic batch | Batch adds complexity, timer management, unpredictable latency spikes |
| Single eviction | Batch eviction (10%) | Batch creates larger pauses, single spreads cost evenly |

## Architecture Patterns

### Cache Structure Extension
```v
pub struct Renderer {
mut:
    cache        map[u64]CachedGlyph
    cache_ages   map[u64]u64           // NEW: key -> last_used_frame
    max_entries  int = 4096             // NEW: capacity limit
    frame_counter u64                   // NEW: global frame counter (or reuse atlas.frame_counter)
}
```

### Pattern 1: Frame Counter LRU Tracking
**What:** Track last access frame per entry, find oldest on eviction
**When to use:** Read-heavy caches where tracking overhead must be minimal
**Example:**
```v
// On cache hit - update age (zero overhead - single assignment)
fn (mut renderer Renderer) get_or_load_glyph(...) !CachedGlyph {
    if key in renderer.cache {
        renderer.cache_ages[key] = renderer.frame_counter  // O(1) age update
        return renderer.cache[key]
    }
    // Cache miss...
}

// On cache insert - evict oldest if at capacity
fn (mut renderer Renderer) insert_glyph(key u64, glyph CachedGlyph) {
    if renderer.cache.len >= renderer.max_entries && key !in renderer.cache {
        // Find LRU entry - O(n) scan but only on eviction
        mut oldest_key := u64(0)
        mut oldest_age := u64(0xFFFFFFFFFFFFFFFF)
        for k, age in renderer.cache_ages {
            if age < oldest_age {
                oldest_age = age
                oldest_key = k
            }
        }
        // Evict
        renderer.cache.delete(oldest_key)
        renderer.cache_ages.delete(oldest_key)
    }
    renderer.cache[key] = glyph
    renderer.cache_ages[key] = renderer.frame_counter
}
```

### Pattern 2: Init-Time Configuration
**What:** Config set before renderer creation, immutable after init
**When to use:** Settings requiring memory pre-allocation or affecting core data structures
**Example:**
```v
pub struct RendererConfig {
pub:
    max_glyph_cache_entries int = 4096  // Default, user can override
    // other config...
}

pub fn new_renderer_with_config(mut ctx gg.Context, cfg RendererConfig) &Renderer {
    max := if cfg.max_glyph_cache_entries < 256 {
        256  // Enforce minimum silently
    } else {
        cfg.max_glyph_cache_entries
    }
    return &Renderer{
        max_entries: max
        // ...
    }
}
```

### Pattern 3: On-Insert Eviction
**What:** Check capacity and evict immediately when inserting new entry
**When to use:** Predictable per-operation cost, no background threads
**Example:**
```v
// Eviction happens synchronously in insert path
renderer.cache[key] = cached_glyph  // Triggers capacity check first
```

### Anti-Patterns to Avoid
- **Periodic batch eviction:** Requires timer management, causes latency spikes, adds complexity without benefit
- **Access order array in hotpath:** O(n) filter on every get() unacceptable for cache with thousands of entries
- **Unbounded option:** Defeats phase purpose (memory bounds), always enforce limit
- **Per-font limits:** Complicates tracking, user can't reason about total memory, global simpler

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| LRU tracking | Custom linked list | Frame counter (exists) | Linked list adds pointer overhead, complexity; frame counter zero-cost reads |
| Thread-safe eviction | Locks/mutexes | Single-threaded (V/sokol model) | VGlyph single-threaded, no concurrency needed |
| Eviction policies | LFU, ARC, 2Q | LRU via frame counter | User decided LRU, frame counter matches existing atlas pattern |

**Key insight:** Codebase already has two LRU patterns (MetricsCache array-based, AtlasPage frame-based). Frame-based proven for read-heavy graphics cache, reuse pattern.

## Common Pitfalls

### Pitfall 1: Access Order Array in Hotpath
**What goes wrong:** Using filter() on access_order array every cache hit causes O(n) cost in critical rendering path
**Why it happens:** MetricsCache uses this pattern, looks simple to copy
**How to avoid:** MetricsCache capacity=256, acceptable overhead. Glyph cache 4096+ entries, filter every hit unacceptable. Use frame counter (O(1) read).
**Warning signs:** Frame rate drops when cache fills, profiling shows filter() cost in get_or_load_glyph

### Pitfall 2: Forgetting to Update Age on Hit
**What goes wrong:** Cache entries evicted even when frequently used (LRU tracking broken)
**Why it happens:** Easy to forget age update in get() path, only testing insert path
**How to avoid:** Update cache_ages[key] = frame_counter on every cache hit
**Warning signs:** High cache miss rate despite repeated text, same glyphs evicted and reloaded

### Pitfall 3: Not Enforcing Minimum Capacity
**What goes wrong:** User sets max_entries=0 or =10, cache thrashes with constant eviction
**Why it happens:** No validation on config input
**How to avoid:** Silently clamp to minimum (256) in constructor, document in API
**Warning signs:** Excessive evictions in instrumentation, poor cache hit rate

### Pitfall 4: Off-by-One in Capacity Check
**What goes wrong:** Cache grows to max_entries+1 or evicts prematurely at max_entries-1
**Why it happens:** Checking cache.len >= max vs cache.len > max, including vs excluding new key
**How to avoid:** Check `if cache.len >= max_entries && key !in cache` (evict only if new key)
**Warning signs:** Cache size oscillates around limit, instrumentation shows unexpected count

### Pitfall 5: Evicting Atlas-Resident Glyphs Without Tracking
**What goes wrong:** Glyph evicted from cache but bitmap remains in atlas consuming memory (hole)
**Why it happens:** Expecting eviction to free atlas space immediately
**How to avoid:** Accept holes-in-atlas as design (user decision), atlas page eviction reclaims space later
**Warning signs:** Atlas utilization stays high despite low cache count (actually correct behavior)

## Code Examples

### Frame Counter Increment (Existing Pattern)
```v
// Source: renderer.v line 114
pub fn (mut renderer Renderer) draw_layout(layout Layout, x f32, y f32) {
    // Increment frame counter for page age tracking
    renderer.atlas.frame_counter++
    // ... rendering ...
}
```

### Atlas Page Age Update on Use (Existing Pattern)
```v
// Source: renderer.v line 173-175
// Update page age on use
if cg.page >= 0 && cg.page < renderer.atlas.pages.len {
    renderer.atlas.pages[cg.page].age = renderer.atlas.frame_counter
}
```

### MetricsCache LRU with Access Order (Existing Pattern - NOT for glyph cache)
```v
// Source: context.v line 24-38
fn (mut cache MetricsCache) get(key u64) ?FontMetricsEntry {
    if key in cache.entries {
        // Move to end (most recent)
        cache.access_order = cache.access_order.filter(it != key)  // O(n) - OK for 256 entries
        cache.access_order << key
        return cache.entries[key]
    }
    return none
}
```

### Find Oldest Page (Frame Counter Pattern)
```v
// Source: glyph_atlas.v line 533-543
fn (atlas &GlyphAtlas) find_oldest_page() int {
    mut oldest_idx := 0
    mut oldest_age := atlas.pages[0].age
    for i, page in atlas.pages {
        if page.age < oldest_age {
            oldest_age = page.age
            oldest_idx = i
        }
    }
    return oldest_idx
}
```

### Recommended Glyph Cache Eviction (Frame Counter Pattern)
```v
// Apply to renderer.v get_or_load_glyph()
fn (mut renderer Renderer) evict_oldest_glyph() {
    mut oldest_key := u64(0)
    mut oldest_age := u64(0xFFFFFFFFFFFFFFFF)
    for key, age in renderer.cache_ages {
        if age < oldest_age {
            oldest_age = age
            oldest_key = key
        }
    }
    renderer.cache.delete(oldest_key)
    renderer.cache_ages.delete(oldest_key)
    $if profile ? {
        renderer.glyph_cache_evictions++  // NEW: track eviction count
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Unbounded glyph cache | Bounded with LRU eviction | Phase 10 | Predictable memory usage, prevents unbounded growth |
| No eviction | Frame counter LRU | Phase 10 | Matches existing atlas page pattern (Phase 9) |
| N/A | Multi-page atlas with page LRU | Phase 9 (commit 81a02ef) | Enabled independent glyph vs atlas eviction |

**Recent patterns:**
- MetricsCache LRU (Phase 9, commit 30275cf): Array-based tracking for 256-entry cache
- Atlas page LRU (Phase 9, commit 81a02ef): Frame counter tracking for multi-page atlas
- Cache collision detection (Phase 9, commit 7283798): Secondary key validation in debug builds

**Standard minimum capacity:**
- Skia glyph cache: 256KB minimum, 2MB default (per-process)
- Firefox glyph cache: 5-10MB per content process
- FreeType cache: Configurable, incremental flush on OOM
- VGlyph choice: 256 glyphs minimum (small but functional), 4096 default (practical for typical usage)

## Open Questions

None - all critical decisions resolved via CONTEXT.md user discussion.

**Implementation details left to planner:**
1. **Eviction timing:** Recommend on-insert (predictable cost, simple)
2. **Batch size:** Recommend single eviction (spreads cost evenly)
3. **Minimum value:** Recommend 256 (matches industry minimum, prevents thrashing)
4. **Instrumentation field:** Add glyph_cache_evictions to ProfileMetrics

## Sources

### Primary (HIGH confidence)
- VGlyph codebase glyph_atlas.v (frame counter LRU pattern in AtlasPage)
- VGlyph codebase context.v (access order LRU pattern in MetricsCache)
- VGlyph codebase renderer.v (current unbounded glyph cache implementation)
- User decisions from CONTEXT.md (locked choices for Phase 10)

### Secondary (MEDIUM confidence)
- [FreeType Cache Subsystem API](http://freetype.org/freetype2/docs/reference/ft2-cache_subsystem.html) - Industry standard glyph cache with bounded memory
- [Mozilla Skia Glyph Cache Discussion](https://bugzilla.mozilla.org/show_bug.cgi?id=1258781) - Real-world cache sizing (2MB default, 256KB min)
- [LRU Counter Implementation - The Beard Sage](http://thebeardsage.com/lru-counter-implementation/) - Counter-based LRU tracking pattern
- [ICLR 2026 KV Cache Research](https://arxiv.org/pdf/2601.18999) - Recent 2026 research on cache eviction performance

### Tertiary (LOW confidence)
- [Cache Replacement Policies - Wikipedia](https://en.wikipedia.org/wiki/Cache_replacement_policies) - General LRU background
- [Redis Cache Eviction Strategies](https://redis.io/blog/cache-eviction-strategies/) - LRU approximation patterns
- [GeeksforGeeks LRU Cache](https://www.geeksforgeeks.org/system-design/lru-cache-implementation/) - Educational reference

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Patterns exist in codebase (frame counter, map-based cache)
- Architecture: HIGH - Frame counter pattern proven in atlas pages, MetricsCache validates approach
- Pitfalls: HIGH - Common cache implementation mistakes well-documented, codebase provides context
- Eviction timing: MEDIUM - On-insert vs periodic not explicitly researched in papers, but on-insert simpler/standard
- Minimum value: MEDIUM - Industry uses bytes (256KB-2MB), translating to glyph count requires estimation

**Research date:** 2026-02-02
**Valid until:** 2026-03-02 (30 days - stable domain, established patterns)
