# Phase 9: Latency Optimizations - Research

**Researched:** 2026-02-02
**Domain:** Performance optimization for text rendering hot paths
**Confidence:** HIGH

## Summary

Research investigated four optimization domains: multi-page texture atlas management, FreeType metrics caching, hash collision handling, and GPU-based emoji scaling. Standard approaches identified with high confidence from official documentation and established patterns.

Multi-page atlas strategy uses separate textures (not texture arrays) for V/Sokol compatibility. OpenGL texture arrays require GL_TEXTURE_2D_ARRAY samplers unsupported in current renderer. Mozilla WebRender demonstrates multi-atlas approach reduces draw calls while avoiding memory spikes.

Metrics cache requires LRU eviction using doubly-linked list + hashmap for O(1) operations. FreeType distinguishes font-level metrics (ascent, descent, linegap) from per-glyph metrics (advance, bearing). Cache font-level metrics by (face_ptr, size) tuple.

Hash collision handling uses secondary key validation with debug assertions. Common pattern stores full key alongside cache entry for comparison. Linear probing or evict-on-collision viable for low collision rates.

GPU emoji scaling replaces CPU bicubic (current: 16 samples per pixel) with upload at native resolution and GL_LINEAR filtering in shader. Quality sufficient for emoji at target sizes.

**Primary recommendation:** Implement multi-page atlas with separate textures, font-level metrics LRU cache, secondary key validation in debug, and GPU scaling for BGRA bitmaps.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| OpenGL | 3.3+ | Multi-texture management | Already used, separate textures supported |
| FreeType | 2.x | Font metrics API | Already integrated, provides face/glyph metrics |
| V builtin | - | map[u64] for cache | Native V hashmap, simple and fast |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Sokol GFX | Current | Texture lifecycle | Already used, supports multiple sg.Image |
| V arrays | - | Circular buffer | Page age tracking, LRU list |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate textures | Texture arrays | Arrays need GL_TEXTURE_2D_ARRAY sampler (Sokol/V integration complex) |
| Custom LRU | V maps only | LRU provides bounded memory, simple map unbounded |
| Assert on collision | Linear probe | Assert catches bugs in debug, probe adds runtime cost |

**Installation:**
No new dependencies - uses existing OpenGL, FreeType, Sokol stack.

## Architecture Patterns

### Recommended Project Structure
```
renderer.v           # Add metrics_cache field
glyph_atlas.v        # Extend to multi-page (pages []AtlasPage)
context.v            # Add font metrics cache (MetricsCache struct)
```

### Pattern 1: Multi-Page Atlas with Separate Textures

**What:** Array of atlas pages (structs), each with own sg.Image. Grow on demand up to max count.

**When to use:** Prevents mid-frame atlas resets when single atlas fills.

**Structure:**
```v
struct AtlasPage {
mut:
    image      gg.Image
    width      int
    height     int
    cursor_x   int
    cursor_y   int
    row_height int
    dirty      bool
    age        u64        // Frame counter, updated on use
    utilization i64      // Used pixels for profiling
}

struct GlyphAtlas {
mut:
    ctx         &gg.Context
    pages       []AtlasPage
    max_pages   int = 4
    current_page int
    frame_counter u64
}
```

**Allocation logic:**
```v
fn (mut atlas GlyphAtlas) insert_bitmap(bmp Bitmap, left int, top int) !(CachedGlyph, bool) {
    // Try current page
    if atlas.pages[atlas.current_page].has_space(bmp.width, bmp.height) {
        return atlas.pages[atlas.current_page].insert(bmp, left, top)!
    }

    // Try to grow if under max
    if atlas.pages.len < atlas.max_pages {
        atlas.pages << atlas.new_page()!
        atlas.current_page = atlas.pages.len - 1
        return atlas.pages[atlas.current_page].insert(bmp, left, top)!
    }

    // All pages full: reset oldest page (circular reuse)
    oldest_idx := atlas.find_oldest_page()
    atlas.reset_page(oldest_idx)
    atlas.current_page = oldest_idx
    return atlas.pages[atlas.current_page].insert(bmp, left, top)!, true
}
```

**Source:** [Mozilla WebRender multi-atlas allocation](https://mozillagfx.wordpress.com/2021/02/04/improving-texture-atlas-allocation-in-webrender/)

### Pattern 2: LRU Cache with HashMap + Doubly-Linked List

**What:** Combine hashmap for O(1) lookup with doubly-linked list for O(1) eviction.

**When to use:** Bounded cache with eviction policy (metrics cache, 256 entries).

**Structure:**
```v
struct LRUNode {
mut:
    key      u64
    value    FontMetrics
    prev     &LRUNode
    next     &LRUNode
}

struct MetricsCache {
mut:
    entries  map[u64]&LRUNode
    head     &LRUNode  // Most recent
    tail     &LRUNode  // Least recent
    capacity int
    size     int
}
```

**Operations:**
```v
fn (mut cache MetricsCache) get(key u64) ?FontMetrics {
    node := cache.entries[key] or { return none }
    cache.move_to_head(node)  // Mark as recently used
    return node.value
}

fn (mut cache MetricsCache) put(key u64, value FontMetrics) {
    if cache.size >= cache.capacity {
        // Evict tail (least recently used)
        evict_key := cache.tail.key
        cache.entries.delete(evict_key)
        cache.remove_node(cache.tail)
        cache.size--
    }
    node := &LRUNode{key: key, value: value}
    cache.entries[key] = node
    cache.add_to_head(node)
    cache.size++
}
```

**Source:** [LRU Cache Implementation - GeeksforGeeks](https://www.geeksforgeeks.org/system-design/lru-cache-implementation/)

### Pattern 3: Secondary Key Validation for Hash Collisions

**What:** Store full cache key in entry, validate on hit. Assert if mismatch in debug builds.

**When to use:** Detect hash collisions that corrupt glyph lookups.

**Structure:**
```v
struct CachedGlyph {
pub:
    x      int
    y      int
    width  int
    height int
    left   int
    top    int
    page   int   // New: which atlas page
    // Secondary key for collision detection
    font_face  voidptr  // Original face pointer
    glyph_index u32     // Original glyph index
    subpixel_bin u8     // Original bin
}
```

**Validation:**
```v
fn (mut renderer Renderer) get_or_load_glyph(item Item, glyph Glyph, bin int) !CachedGlyph {
    key := compute_cache_key(item.ft_face, glyph.index, bin)

    if cached := renderer.cache[key] {
        // Secondary key validation
        if cached.font_face == voidptr(item.ft_face) &&
           cached.glyph_index == glyph.index &&
           cached.subpixel_bin == u8(bin) {
            return cached  // Valid hit
        }
        // Collision detected
        $if debug {
            panic('Glyph cache collision: key=${key} expected face=${voidptr(item.ft_face)} glyph=${glyph.index} bin=${bin}')
        }
        $if profile ? {
            renderer.glyph_cache_collisions++
        }
        // Evict colliding entry, reload
        renderer.cache.delete(key)
    }

    // Load from FreeType
    cached := renderer.load_glyph(...)!
    renderer.cache[key] = cached
    return cached
}
```

**Source:** [Warp glyph cache with collision handling](https://www.warp.dev/blog/adventures-text-rendering-kerning-glyph-atlases)

### Pattern 4: GPU Emoji Scaling with Native Resolution Upload

**What:** Upload emoji bitmaps at native resolution (e.g., 136x128), scale via GL_LINEAR in shader.

**When to use:** Avoids per-frame CPU bicubic scaling (current: 16 samples/pixel).

**Implementation:**
```v
// In ft_bitmap_to_bitmap for BGRA mode
u8(C.FT_PIXEL_MODE_BGRA) {
    // Copy BGRA data without scaling
    for y in 0 .. height {
        src_y := if pitch_positive { y } else { height - 1 - y }
        row := unsafe { bmp.buffer + src_y * abs_pitch }
        for x in 0 .. width {
            src := unsafe { row + x * 4 }
            i := (y * width + x) * 4
            data[i + 0] = unsafe { src[2] } // R
            data[i + 1] = unsafe { src[1] } // G
            data[i + 2] = unsafe { src[0] } // B
            data[i + 3] = unsafe { src[3] } // A
        }
    }
    // NO scaling here - upload native resolution
    // Atlas stores at native size, GPU scales during draw
}

// In draw_layout
if cg.width > 0 && cg.height > 0 {
    // Scale factor applied to destination rect
    target_size_logical := f32(item.ascent)
    native_size_logical := f32(cg.height) * scale_inv
    emoji_scale := target_size_logical / native_size_logical

    dst := gg.Rect{
        x:      draw_x
        y:      draw_y
        width:  f32(cg.width) * scale_inv * emoji_scale
        height: f32(cg.height) * scale_inv * emoji_scale
    }
    // GL_LINEAR sampler does bilinear filtering
    renderer.ctx.draw_image_with_config(...)
}
```

**Source:** Current renderer already uses GL_LINEAR sampler (renderer.v:60-68)

### Anti-Patterns to Avoid

- **OpenGL texture arrays:** Require GL_TEXTURE_2D_ARRAY sampler, incompatible with current Sokol/gg setup
- **Single shared LRU for all caches:** Metrics and glyphs have different access patterns, separate caches better
- **Runtime collision probing:** Adds latency to hot path, use evict-on-collision or debug-only assertion
- **Caching per-glyph metrics:** FreeType warns "no easy way" due to hinting variance, cache font-level only

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OpenGL texture arrays | Custom GL_TEXTURE_2D_ARRAY | Separate textures | Sokol abstraction doesn't expose array samplers |
| LRU eviction policy | Custom sorting/timestamps | Doubly-linked list | Standard O(1) pattern, well-tested |
| Cache key hashing | Custom hash function | XOR of face ptr + shifted index | Simple, collision rate acceptable with validation |
| Bilinear filtering | Custom interpolation | GL_LINEAR sampler | Already configured, GPU-accelerated |

**Key insight:** Performance optimization is about removing work, not adding cleverness. Multi-page avoids resets, metrics cache avoids FreeType calls, GPU scaling avoids CPU loops.

## Common Pitfalls

### Pitfall 1: Using OpenGL Texture Arrays in Sokol

**What goes wrong:** GL_TEXTURE_2D_ARRAY requires different sampler type in shader, current renderer uses GL_TEXTURE_2D.

**Why it happens:** OpenGL wiki shows texture arrays as "alternative to atlases" without mentioning shader changes needed.

**How to avoid:** Use array of separate textures ([]AtlasPage each with sg.Image). Sokol sg.Image encapsulates GL_TEXTURE_2D.

**Warning signs:** Compiler error binding texture array to GL_TEXTURE_2D sampler, or black quads from wrong sampler type.

**Source:** [OpenGL Array Texture wiki](https://wikis.khronos.org/opengl/Array_Texture) - "Shader access patterns: Array textures require shader-based access using dedicated sampler types"

### Pitfall 2: Caching Per-Glyph Hinted Metrics

**What goes wrong:** Hinting varies per glyph at each size, cache explodes with (font, size, glyph_index) entries.

**Why it happens:** FreeType docs say "no easy way to get hinted glyph widths" but this is often missed.

**How to avoid:** Cache only font-level metrics (ascent, descent, linegap) by (face, size) tuple. Per-glyph metrics computed on demand.

**Warning signs:** Metrics cache hit rate <50%, memory usage grows unbounded.

**Source:** [FreeType Glyph Conventions](https://freetype.org/freetype2/docs/glyphs/glyphs-3.html) - "there is no easy way to get the hinted glyph and advance widths of a range of glyphs"

### Pitfall 3: Resetting All Pages When One Fills

**What goes wrong:** Invalidates cache entries for all pages, forces massive re-rasterization.

**Why it happens:** Single-atlas logic extended to multi-page without per-page invalidation.

**How to avoid:** Track page index in CachedGlyph. On page reset, only invalidate entries with matching page index.

**Warning signs:** Profile shows massive rasterize time spike despite multi-page atlas.

**Implementation:**
```v
fn (mut atlas GlyphAtlas) reset_page(page_idx int) {
    // Clear page texture and reset cursors
    atlas.pages[page_idx].reset()
}

// In renderer after reset
for key, cached in renderer.cache {
    if cached.page == reset_page_idx {
        renderer.cache.delete(key)
    }
}
```

### Pitfall 4: Not Updating Page Age on Every Use

**What goes wrong:** "Oldest" page might actually be most-used, reset thrashes active glyphs.

**Why it happens:** Age set only at allocation, not updated on cache hits.

**How to avoid:** Increment page age (frame counter) whenever a glyph from that page is drawn.

**Warning signs:** Atlas resets don't reduce, page utilization metrics show recently-reset pages at 90%+.

**Implementation:**
```v
fn (mut renderer Renderer) draw_layout(layout Layout, x f32, y f32) {
    atlas.frame_counter++
    for item in layout.items {
        for glyph in item.glyphs {
            cached := renderer.get_or_load_glyph(...)!
            // Update page age on use
            atlas.pages[cached.page].age = atlas.frame_counter
        }
    }
}
```

### Pitfall 5: Linear Filtering on Text Glyphs

**What goes wrong:** Grayscale glyphs blurred when scaled, subpixel AA ruined.

**Why it happens:** GL_LINEAR applied to all atlas textures including text.

**How to avoid:** This is NOT a pitfall for emoji (user decision: linear filtering). Current renderer already uses GL_LINEAR for all glyphs. If future need arises, separate atlases for text (GL_NEAREST) and emoji (GL_LINEAR).

**Warning signs:** Text looks blurry at non-integer scales (but user accepted this for emoji).

## Code Examples

### Multi-Page Atlas Initialization

```v
// Source: Adapted from current glyph_atlas.v:72-116
fn new_multi_page_atlas(mut ctx gg.Context, page_w int, page_h int, max_pages int) !GlyphAtlas {
    // Start with 1 page, grow on demand
    mut first_page := new_atlas_page(mut ctx, page_w, page_h)!

    return GlyphAtlas{
        ctx:           ctx
        pages:         [first_page]
        max_pages:     max_pages
        current_page:  0
        frame_counter: 0
        max_height:    page_h
    }
}

fn new_atlas_page(mut ctx gg.Context, w int, h int) !AtlasPage {
    size := i64(w) * i64(h) * 4
    if size <= 0 || size > max_i32 {
        return error('Atlas page size overflow: ${w}x${h} = ${size} bytes')
    }

    mut img := gg.Image{
        width:       w
        height:      h
        nr_channels: 4
    }

    desc := sg.ImageDesc{
        width:        w
        height:       h
        pixel_format: .rgba8
        usage:        .dynamic
    }

    img.simg = sg.make_image(&desc)
    img.simg_ok = true
    img.id = ctx.cache_image(img)
    img.data = unsafe { vcalloc(int(size)) }

    return AtlasPage{
        image:       img
        width:       w
        height:      h
        age:         0
        utilization: 0
    }
}
```

### Font Metrics Cache with LRU

```v
// Source: Standard LRU pattern from GeeksforGeeks
struct FontMetrics {
    ascent  int
    descent int
    linegap int
}

struct MetricsCache {
mut:
    entries  map[u64]FontMetrics
    access_order []u64  // Simple LRU: most recent at end
    capacity int = 256
}

fn (mut cache MetricsCache) get(face voidptr, size int) ?FontMetrics {
    key := u64(face) ^ (u64(size) << 32)

    if key in cache.entries {
        // Move to end (most recent)
        cache.access_order = cache.access_order.filter(it != key)
        cache.access_order << key
        return cache.entries[key]
    }
    return none
}

fn (mut cache MetricsCache) put(face voidptr, size int, metrics FontMetrics) {
    key := u64(face) ^ (u64(size) << 32)

    if cache.entries.len >= cache.capacity {
        // Evict oldest (first in access_order)
        evict_key := cache.access_order[0]
        cache.entries.delete(evict_key)
        cache.access_order.delete(0)
    }

    cache.entries[key] = metrics
    cache.access_order << key
}
```

### Secondary Key Validation in Debug

```v
// Source: Collision detection pattern from Warp glyph cache article
struct CachedGlyph {
pub:
    // ... existing fields
    page   int
    // Secondary key fields
    font_face    voidptr
    glyph_index  u32
    subpixel_bin u8
}

fn (mut renderer Renderer) get_or_load_glyph(item Item, glyph Glyph, bin int) !CachedGlyph {
    font_id := u64(voidptr(item.ft_face))
    index_with_bin := (u64(glyph.index) << 2) | u64(bin)
    key := font_id ^ (index_with_bin << 32)

    if cached := renderer.cache[key] {
        // Validate secondary key
        $if debug {
            if cached.font_face != voidptr(item.ft_face) ||
               cached.glyph_index != glyph.index ||
               cached.subpixel_bin != u8(bin) {
                panic('Glyph cache collision detected at key ${key:016x}')
            }
        }
        $if profile ? {
            renderer.glyph_cache_hits++
        }
        return cached
    }

    // Cache miss: load from FreeType
    $if profile ? {
        renderer.glyph_cache_misses++
    }

    target_h := int(f32(item.ascent) * renderer.scale_factor)
    cached := renderer.load_glyph(LoadGlyphConfig{
        face:          item.ft_face
        index:         glyph.index
        target_height: target_h
        subpixel_bin:  bin
    })!

    // Store with secondary key
    mut cached_with_key := cached
    cached_with_key.font_face = voidptr(item.ft_face)
    cached_with_key.glyph_index = glyph.index
    cached_with_key.subpixel_bin = u8(bin)

    renderer.cache[key] = cached_with_key
    return cached_with_key
}
```

### GPU Emoji Scaling (Remove CPU Scaling)

```v
// Source: Current bitmap_scaling.v to be replaced
// In ft_bitmap_to_bitmap, BGRA case:
u8(C.FT_PIXEL_MODE_BGRA) {
    // Clamp to max texture size
    if width > 256 || height > 256 {
        return error('Emoji bitmap exceeds max size 256x256: ${width}x${height}')
    }

    // Copy BGRA without scaling
    for y in 0 .. height {
        src_y := if pitch_positive { y } else { height - 1 - y }
        row := unsafe { bmp.buffer + src_y * abs_pitch }
        for x in 0 .. width {
            src := unsafe { row + x * 4 }
            i := (y * width + x) * 4
            data[i + 0] = unsafe { src[2] } // R
            data[i + 1] = unsafe { src[1] } // G
            data[i + 2] = unsafe { src[0] } // B
            data[i + 3] = unsafe { src[3] } // A
        }
    }
    // Return native resolution bitmap - GPU handles scaling
}

// In draw_layout, emoji size adjustment:
// Current code at line 278 computes target_h from item.ascent
// This target_h is passed to load_glyph for emoji sizing
// With GPU scaling, pass target_h = 0 to signal "native resolution"
// Then in draw, scale destination rect to match target size

// Modified load_glyph call:
cached_glyph := renderer.load_glyph(LoadGlyphConfig{
    face:          item.ft_face
    index:         glyph.index
    target_height: 0  // Signal: upload native, scale on GPU
    subpixel_bin:  bin
})!
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single atlas reset | Multi-page circular reuse | 2021 (WebRender) | Eliminates mid-frame stalls |
| FreeType cache subsystem | Custom LRU caches | 2020s (most renderers) | Simpler, domain-specific |
| CPU bicubic emoji | GPU bilinear scaling | 2020+ (HarfBuzz) | 16x fewer samples per pixel |
| Separate chaining | Open addressing with validation | 2020s | Lower memory overhead |

**Deprecated/outdated:**
- FreeType FTC_Manager: Complex API, overkill for simple metrics cache
- Texture atlases with border padding: Multi-page eliminates need for padding between items
- Hash tables without collision detection: Modern caches validate secondary keys in debug

## Open Questions

1. **Page size vs count tradeoff**
   - What we know: 4 pages * 4K = 64MB VRAM, Mozilla uses adaptive sizes
   - What's unclear: Does 2 pages * 8K vs 4 pages * 4K affect allocation success?
   - Recommendation: Start with user's decision (4 pages, same size as current atlas)

2. **Metrics cache for Pango vs FreeType**
   - What we know: User decided (font, size) tuple, context.v uses Pango
   - What's unclear: Pango caches internally, is additional cache helpful?
   - Recommendation: Profile first, implement if >5% time in font_metrics calls

3. **LRU for glyph cache vs unbounded map**
   - What we know: Current glyph cache unbounded, user didn't request LRU
   - What's unclear: Does glyph cache grow unbounded in practice?
   - Recommendation: Keep unbounded, implement LRU only if profiling shows issue

4. **Page reset policy: LRU vs FIFO**
   - What we know: User decided "circular reuse" and "track page age"
   - What's unclear: LRU needs per-glyph age tracking, FIFO uses page-level
   - Recommendation: Use LRU page age (update on cache hit drawing from that page)

## Sources

### Primary (HIGH confidence)
- [OpenGL Array Texture - Khronos Wiki](https://wikis.khronos.org/opengl/Array_Texture) - Texture array technical constraints
- [FreeType Cache Sub-System API](http://freetype.org/freetype2/docs/reference/ft2-cache_subsystem.html) - Cache types and metrics
- [FreeType Glyph Conventions](https://freetype.org/freetype2/docs/glyphs/glyphs-3.html) - Font-level vs glyph-level metrics
- [OpenGL Sampler Object - Khronos Wiki](https://www.khronos.org/opengl/wiki/Sampler_Object) - GL_LINEAR filtering

### Secondary (MEDIUM confidence)
- [Mozilla WebRender: Improving texture atlas allocation](https://mozillagfx.wordpress.com/2021/02/04/improving-texture-atlas-allocation-in-webrender/) - Multi-page atlas patterns
- [LRU Cache Implementation - GeeksforGeeks](https://www.geeksforgeeks.org/system-design/lru-cache-implementation/) - Standard LRU data structure
- [Warp: Adventures in Text Rendering](https://www.warp.dev/blog/adventures-text-rendering-kerning-glyph-atlases) - Glyph cache collision handling
- [Hash Table Collision Resolution - GeeksforGeeks](https://www.geeksforgeeks.org/dsa/collision-resolution-techniques/) - Secondary key validation pattern

### Tertiary (LOW confidence)
- [Texture filtering - Wikipedia](https://en.wikipedia.org/wiki/Texture_filtering) - Bilinear filtering theory
- [V language documentation - Maps](https://modules.vlang.io/maps.html) - V map implementation
- [Texture Atlas Optimization - GarageFarm](https://garagefarm.net/blog/texture-atlas-optimizing-textures-in-3d-rendering) - General atlas patterns

## Metadata

**Confidence breakdown:**
- Multi-page atlas strategy: HIGH - Mozilla WebRender real-world implementation
- Metrics cache structure: HIGH - FreeType official docs, standard LRU pattern
- Collision handling: MEDIUM - WebSearch pattern + debug assertion approach
- GPU emoji scaling: HIGH - Already using GL_LINEAR sampler, remove CPU code

**Research date:** 2026-02-02
**Valid until:** 2026-04-02 (60 days - stable rendering domain)
