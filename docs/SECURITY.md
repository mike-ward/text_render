# VGlyph Security Model

## Threat Model

**Primary threat:** Untrusted text content from external sources.

VGlyph is a text rendering library that processes user-provided text. The main security
concerns are:

1. **Malformed input** - Invalid UTF-8, extreme sizes, malicious paths
2. **Resource exhaustion** - DoS through large text, many glyphs
3. **Memory corruption** - Buffer overflows, use-after-free in C libraries

## Input Validation

All public APIs validate input at entry:

| Input Type | Validation | Error Behavior |
|------------|------------|----------------|
| Text strings | UTF-8 encoding, max 10KB | Return error |
| Font paths | Existence, no traversal (..) | Return error |
| Font size | Range [0.1, 500] | Clamp with warning |
| Dimensions | Positive, max 16384 | Return error |

Validation functions in `validation.v`:
- `validate_text_input()` - UTF-8 and length checks
- `validate_font_path()` - Path traversal and existence checks
- `validate_size()` - Size range enforcement
- `validate_dimension()` - Dimension bounds enforcement

## Resource Limits

| Resource | Limit | Enforcement |
|----------|-------|-------------|
| Text length | 10KB | validate_text_input() |
| Font size | 500pt max | validate_size() |
| Glyph bitmap | 256x256 | max_glyph_size constant |
| Atlas page | 4096x4096 | GlyphAtlas.max_height |
| Total atlas | 4 pages (~256MB) | GlyphAtlas.max_pages |
| Single alloc | 1GB | check_allocation_size() |
| Max texture | 16384 | max_texture_dimension |

## Error Handling

- All errors include source location (`@FILE:@LINE`)
- C library errors wrapped with context (e.g., "FreeType error 6 loading font X")
- No silent failures in public APIs - functions return `!T` result types
- V result types enforce error handling at compile time

Error categories:
- **Validation errors:** Invalid input detected before processing
- **C library errors:** FreeType, Pango, FontConfig failures wrapped with context
- **Resource errors:** Allocation failures, atlas full conditions

## Resource Lifecycle

### FreeType

| Resource | Creation | Cleanup | Owner |
|----------|----------|---------|-------|
| FT_Library | `new_context()` | `Context.free()` | Context |
| FT_Face | `pango_ft2_font_get_face()` | Do NOT free | Pango (borrowed) |

**FT_Face ownership:** Faces are borrowed from Pango via `pango_ft2_font_get_face`. VGlyph does
not own these pointers and must not call `FT_Done_Face`. The face lifetime is tied to the
PangoFont that provides it.

### Pango

| Resource | Creation | Cleanup | Pattern |
|----------|----------|---------|---------|
| PangoLayout | `pango_layout_new()` | `g_object_unref()` | defer immediately after creation |
| PangoLayoutIter | `pango_layout_get_iter()` | `pango_layout_iter_free()` | defer after nil check |
| PangoAttrList | `pango_attr_list_new/copy()` | `pango_attr_list_unref()` | unref after set_attributes |
| PangoFontDescription | `pango_font_description_*()` | `pango_font_description_free()` | defer or caller-owns |
| PangoFont | `pango_context_load_font()` | `g_object_unref()` | defer immediately |
| PangoFontMetrics | `pango_font_get_metrics()` | `pango_font_metrics_unref()` | defer or immediate unref |

**AttrList lifecycle pattern:**
1. Copy existing or create new (caller owns, refcount=1)
2. Modify with `pango_attr_list_insert` (list takes ownership of attributes)
3. Call `set_attributes` (layout refs the list)
4. MUST unref caller's copy (exactly once after set_attributes)

### Atlas Memory

| Resource | Creation | Cleanup | Pattern |
|----------|----------|---------|---------|
| Atlas page data | `vcalloc()` | `free()` | On grow, old data freed |
| Sokol images | `sg.make_image()` | `remove_cached_image_by_idx()` | Deferred via garbage list |

Atlas lifecycle:
- Pages allocated via `vcalloc` with nil check
- Old textures queued for cleanup in `garbage` list (avoid destroying while bound)
- `cleanup()` called per frame to release old resources after frame completes
- LRU eviction when max_pages reached

## Debug Features

Enable debug builds (`v -d debug`) for additional checks:

| Feature | Purpose |
|---------|---------|
| AttrList leak counter | `check_attr_list_leaks()` panics if any AttrList leaked |
| Iterator exhaustion detection | Panics if iterator reused after exhausted |
| Glyph cache collision detection | Validates secondary key on cache hit |
| FreeType state validation | Asserts on invalid outline/glyph states |

## NSView Hierarchy Discovery (macOS Overlay API)

### Overview

The overlay API discovers MTKView by walking NSWindow's subview tree. This
enables transparent IME overlay creation without requiring direct handle access.

### Trust Boundary Diagram

```
[TRUSTED]              [BOUNDARY]            [VALIDATED]
V application    -->   FFI call      -->     NSWindow view tree
editor_demo.v          vglyph_discover_      Subviews checked via
                       mtkview_from_window() isKindOfClass
```

### Implementation Safety

- **NULL check** on NSWindow before access
- **Depth limit** 100 levels to prevent infinite recursion
- **isKindOfClass** runtime type check (not string matching)
- **NULL return** on not found (no exceptions)

### Failure Handling

Returns NULL when MTKView not found. Caller falls back to global callbacks.
No exceptions thrown. Logs discovery failure to stderr.

### Security Properties

- Cannot crash (all pointers validated)
- Cannot be spoofed (runtime type checking)
- Fails safe (returns NULL)
- No privilege escalation possible

### Known Limitations

- Assumes MTKView present (sokol always creates one)
- Does not validate subclass behavior beyond type check

---

## Other Known Limitations

1. **Korean IME first-keypress** - macOS-level bug, documented upstream. User
   workaround: type first character twice, or refocus field.

2. **Font format validation** - Delegated entirely to FreeType. VGlyph
   validates path existence but not font file contents.

3. **Thread safety** - VGlyph is designed for single-threaded use (V's
   default model). Context, Renderer, and TextSystem are not thread-safe.

4. **Overlay API macOS-only** - Overlay discovery requires NSWindow.
   Non-macOS platforms use global callback fallback. Not a security issue.

## Security Checklist

Before releasing:
- [ ] All public APIs validate input before processing
- [ ] All C library calls check return values
- [ ] All allocations checked against limits
- [ ] All FreeType/Pango objects cleaned up on all exit paths
- [ ] Error messages include location context
- [ ] Tests cover error paths

## Reporting Security Issues

Report security issues to: [GitHub Issues with security label](../../issues/new?labels=security)

For critical vulnerabilities, please mark the issue as confidential or contact maintainers
directly before public disclosure.
