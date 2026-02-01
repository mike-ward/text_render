# Phase 3: Layout Safety - Research

**Researched:** 2026-02-01
**Domain:** V language memory safety, Pango FFI, pointer casts, string lifetime
**Confidence:** HIGH

## Summary

Researched V language patterns for documenting unsafe pointer casts, debug validation, and
manual string memory management in C FFI contexts.

V requires `unsafe` blocks for pointer casts but PangoLayoutRun/PangoGlyphItem cast safe via
typedef. Debug validation uses `$if debug` with panic() for failures. String lifetime managed
via explicit `.clone()` with manual tracking for `.free()` in cleanup methods.

**Primary recommendation:** Use Pango docs URL in comment, panic() in $if debug block, array
to track cloned strings.

## Standard Stack

### Core Language Features
| Feature | Purpose | Why Standard |
|---------|---------|--------------|
| `$if debug` | Conditional compilation | Built-in, enabled by -g/-cg flags |
| `panic(msg)` | Unrecoverable error | Standard for fatal runtime errors |
| `unsafe { }` | Memory-unsafe operations | Required by compiler for pointer ops |
| `string.clone()` | Deep copy strings | Creates independent owned copy |
| `free(ptr)` | Manual deallocation | C FFI memory cleanup |

### Supporting
| Feature | Purpose | When to Use |
|---------|---------|-------------|
| `[]string` array | Track allocations | Simple indexed collection |
| `.free()` method | Cleanup pattern | Resource deallocation in types |
| `voidptr(x) != unsafe { nil }` | Null check | Before freeing C pointers |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `$if debug` | `$if test` | test only runs during testing |
| panic() | assert | assert removed in production builds |
| []string | []&char | Array easier, no manual pointer mgmt |

**Installation:**
N/A - built-in language features

## Architecture Patterns

### Recommended Pattern
```v
struct MyType {
mut:
    cloned_strings []string  // Track owned strings
}

fn (mut t MyType) free() {
    // Free tracked strings
    for s in t.cloned_strings {
        unsafe { free(s.str) }
    }
    // Free C resources
    if voidptr(t.c_resource) != unsafe { nil } {
        C.some_free_function(t.c_resource)
    }
}
```

### Pattern 1: Debug Validation
**What:** Runtime checks enabled only in debug builds
**When to use:** Validate unsafe assumptions without production overhead
**Example:**
```v
// Source: https://docs.vlang.io/conditional-compilation.html
$if debug {
    if some_invariant_violated {
        panic('invariant violation detected')
    }
}
```

### Pattern 2: String Cloning for C FFI
**What:** Clone V strings before passing to C code that stores pointers
**When to use:** C code stores `char*` beyond function call lifetime
**Example:**
```v
// Source: https://github.com/vlang/v/blob/master/vlib/builtin/string.v
cloned := original_string.clone()
unsafe { C.some_function_that_stores(cloned.str) }
// Track cloned for later free()
```

### Pattern 3: Panic for Debug Validation
**What:** Use panic() not assert for debug checks
**When to use:** Runtime validation in debug builds
**Example:**
```v
// Source: existing codebase pattern
$if debug {
    if condition_failed {
        panic('validation failed')
    }
}
```

### Anti-Patterns to Avoid
- **assert in $if debug:** Redundant - assert already removed in production
- **log.error for panics:** panic() provides stack trace, log doesn't
- **Forgetting to track clones:** Memory leak if not freed

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| String copying | Custom memcpy | string.clone() | Handles V string metadata |
| Debug checks | Custom flags | $if debug | Compiler-integrated |
| Fatal errors | Custom exit | panic(msg) | Stack trace included |
| Pointer validation | Manual checks | Type system + unsafe | Compiler enforced |

**Key insight:** V compiler handles conditional compilation and memory safety checks - use
built-in mechanisms.

## Common Pitfalls

### Pitfall 1: String Lifetime in C FFI
**What goes wrong:** Pass `string.str` to C code that stores pointer beyond call
**Why it happens:** V strings may be freed after function returns
**How to avoid:** Clone string, track clone, free in cleanup method
**Warning signs:** Crashes accessing C-stored strings, use-after-free

### Pitfall 2: Assert in $if debug
**What goes wrong:** Redundant checks - assert already conditional
**Why it happens:** Unclear that assert removed in production
**How to avoid:** Use panic() directly in $if debug blocks
**Warning signs:** Double-nesting conditions

### Pitfall 3: Not Tracking Cloned Strings
**What goes wrong:** Memory leak from cloned strings never freed
**Why it happens:** No reference to cloned string for later free
**How to avoid:** Store in array field, free in cleanup method
**Warning signs:** Growing memory usage over time

### Pitfall 4: Nullable Pointer Free
**What goes wrong:** Crash freeing null pointer
**Why it happens:** Resource never initialized or already freed
**How to avoid:** Check `voidptr(ptr) != unsafe { nil }` before free
**Warning signs:** Segfault in cleanup code

## Code Examples

Verified patterns from official sources and existing codebase:

### Debug Conditional Compilation
```v
// Source: https://docs.vlang.io/conditional-compilation.html
$if debug {
    println('debugging')
}

// Also valid: $if debug || test for debug OR test builds
```

### Panic for Fatal Errors
```v
// Source: existing codebase renderer.v:27
mut atlas := new_glyph_atlas(mut ctx, 1024, 1024) or { panic(err) }
```

### String Clone and Track
```v
// Source: https://github.com/vlang/v/blob/master/vlib/toml/any.v
pub fn (a Any) string() string {
    match a {
        string { return (a as string).clone() }
        else { return a.str().clone() }
    }
}
```

### Cleanup Method Pattern
```v
// Source: existing codebase context.v:80
pub fn (mut ctx Context) free() {
    if voidptr(ctx.pango_context) != unsafe { nil } {
        C.g_object_unref(ctx.pango_context)
    }
    if voidptr(ctx.ft_lib) != unsafe { nil } {
        C.FT_Done_FreeType(ctx.ft_lib)
    }
}
```

### Unsafe Pointer Cast
```v
// Source: layout.v:156 (existing code)
run_ptr := C.pango_layout_iter_get_run_readonly(iter)
if run_ptr != unsafe { nil } {
    run := unsafe { &C.PangoLayoutRun(run_ptr) }
    // ... use run
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| assert everywhere | Conditional assert | V 0.3+ | assert only in debug |
| Manual free tracking | autofree flag | V 0.2+ | Optional automatic cleanup |
| Log errors | panic/Result types | V 0.1+ | Explicit error handling |

**Deprecated/outdated:**
- Using assert for runtime validation (still works but use panic in $if debug)
- Assuming strings never freed (autofree may enable automatic cleanup)

## Open Questions

Things that couldn't be fully resolved:

1. **Layout.destroy() vs Layout.free() naming**
   - What we know: Codebase uses Context.free() pattern
   - What's unclear: Whether Layout should have free() or if handled by autofree
   - Recommendation: Follow Context.free() pattern for consistency

2. **Optimal validation thoroughness**
   - What we know: Can check null, can check struct fields
   - What's unclear: How deep validation should go for performance
   - Recommendation: Null check sufficient - struct field check if cost acceptable

3. **Pointer nullification after free**
   - What we know: Not standard V pattern, C safety pattern exists
   - What's unclear: V compiler may already prevent use-after-free
   - Recommendation: Skip nullification unless evidence of issues

## Sources

### Primary (HIGH confidence)
- [V Conditional Compilation](https://docs.vlang.io/conditional-compilation.html) - $if debug,
  compile-time flags
- [V Memory Unsafe Code](https://docs.vlang.io/memory-unsafe-code.html) - unsafe blocks,
  pointer operations
- [V builtin/string.v](https://github.com/vlang/v/blob/master/vlib/builtin/string.v) -
  clone(), cstring_to_vstring
- [Pango pango-layout.h](https://github.com/ImageMagick/pango/blob/main/pango/pango-layout.h)
  - PangoLayoutRun typedef
- [Pango GTK Docs](https://docs.gtk.org/Pango/) - PangoGlyphItem, iterator behavior
- Existing codebase: context.v, layout.v, renderer.v, glyph_atlas.v

### Secondary (MEDIUM confidence)
- [V toml/any.v](https://github.com/vlang/v/blob/master/vlib/toml/any.v) - clone() usage
  pattern
- [V Memory Management Docs](https://docs.vlang.io/memory-management.html) - autofree, GC
  options
- [V string discussions](https://github.com/vlang/v/discussions/11687) - clone performance

### Tertiary (LOW confidence)
- GitHub discussions about panic() vs error() - design still evolving
- V language release notes for memory management changes

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official docs + existing codebase patterns
- Architecture: HIGH - Verified with official examples + codebase
- Pitfalls: MEDIUM - Inferred from docs + common C FFI issues

**Research date:** 2026-02-01
**Valid until:** 2026-03-01 (30 days - V language stable features)
