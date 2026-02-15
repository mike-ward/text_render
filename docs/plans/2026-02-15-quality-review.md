# VGlyph Quality Review - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use
> superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all high and medium-priority bugs found in the vglyph
quality review.

**Architecture:** Targeted fixes to existing files. No new modules or
architectural changes. Each task is a self-contained fix.

**Tech Stack:** V language, Objective-C (IME files)

---

## Findings Summary

| Severity | Total found | Fixable | Deferred |
|----------|-------------|---------|----------|
| High     | 6           | 6       | 0        |
| Medium   | 47          | 17      | 30       |
| Low      | ~70         | 0       | all      |

### Deferred Medium Items (too disruptive or low-risk)

- MetricsCache filter() O(n) allocation — data structure change
- evict_oldest_glyph O(n) scan — architecture change
- Layout pub mut fields — breaking API change
- Byte-by-byte map lookups in layout_query — refactoring
- move_cursor_* fresh array per call — refactoring
- Per-frame NSString allocs in backend_darwin — architecture
- font_height/font_metrics code duplication — refactoring
- Duplicated constructor logic in renderer — refactoring
- No nil guards on pango_wrapper methods — V design constraint
- get_attributes returns raw pointer — API change
- IME bridge global thread safety — ObjC architecture
- IME bridge NSView category scope — known design trade-off
- cstring_to_vstring per run for emoji check — micro-opt
- Debug memory tracking inconsistency — cosmetic
- Test gaps (bitmap_scaling, pango_wrappers, undo,
  composition, accessibility, layout_mutation, cursor
  movement) — significant effort, separate task

---

### Task 1: Fix accessibility text empty in release builds

**Files:**
- Modify: `layout_accessibility.v:33-50`
- Modify: `layout_iter.v:218-297` (verify)

**Problem:** `extract_text()` reads `item.run_text` which is only
populated in `$if debug` builds. In release, all accessibility text
is empty — screen reader support silently broken.

**Step 1:** Read layout_accessibility.v and layout_iter.v to confirm
the bug.

**Step 2:** Fix `extract_text()` to use the original layout text
with `item.start_index` and `item.length` instead of `run_text`:

```v
fn extract_text(l Layout) string {
    mut sb := strings.new_builder(64)
    for item in l.items {
        if item.start_index >= 0
            && item.length > 0
            && item.start_index + item.length <= l.text.len {
            sb.write_string(
                l.text[item.start_index..item.start_index + item.length]
            )
        }
    }
    return sb.str()
}
```

Note: This requires Layout to carry the original text. If `l.text`
does not exist, store it during layout build or pass it as parameter.

**Step 3:** Run `v fmt -w layout_accessibility.v`

**Step 4:** Run `v test .` to verify no regressions.

**Step 5:** Commit.

---

### Task 2: Add free() methods for resource cleanup

**Files:**
- Modify: `api.v` — add `TextSystem.free()`
- Modify: `renderer.v` — add `Renderer.free()`
- Modify: `glyph_atlas.v` — add `GlyphAtlas.free()`

**Problem:** No cleanup methods exist. FT_Stroker, Sokol sampler,
atlas pages' vcalloc'd image.data, and Sokol images are never freed.

**Step 1:** Add `GlyphAtlas.free()`:
```v
pub fn (mut atlas GlyphAtlas) free() {
    for mut page in atlas.pages {
        if page.image.data != unsafe { nil } {
            unsafe { free(page.image.data) }
            page.image.data = unsafe { nil }
        }
        sg.destroy_image(page.image.simg)
    }
    for id in atlas.garbage {
        sg.destroy_image(sg.Image{id: id})
    }
    atlas.pages.clear()
    atlas.garbage.clear()
}
```

**Step 2:** Add `Renderer.free()`:
```v
pub fn (mut r Renderer) free() {
    if r.ft_stroker != unsafe { nil } {
        C.FT_Stroker_Done(r.ft_stroker)
        r.ft_stroker = unsafe { nil }
    }
    r.atlas.free()
    r.cache.clear()
    r.cache_ages.clear()
}
```

**Step 3:** Add `TextSystem.free()`:
```v
pub fn (mut ts TextSystem) free() {
    if ts.renderer != unsafe { nil } {
        ts.renderer.free()
    }
    ts.ctx.free()
    ts.cache.clear()
}
```

**Step 4:** Format and test.

**Step 5:** Commit.

---

### Task 3: Fix undo/redo out-of-bounds panics

**Files:**
- Modify: `undo.v:196-257`

**Problem:** `undo()` and `redo()` use text slicing without
validating that stored ranges are within current text bounds.
If text was modified outside undo system, this panics.

**Step 1:** Add bounds guard at top of undo():
```v
if op.range_start > text.len || op.range_end > text.len
    || op.range_start > op.range_end {
    return none
}
```

**Step 2:** Add same guard in redo():
```v
if op.range_start > text.len {
    return none
}
```

**Step 3:** Also fix redo's undo_stack push to respect max_history:
```v
if um.undo_stack.len >= um.max_history {
    um.undo_stack.delete(0)
}
um.undo_stack << inverse
```

**Step 4:** Format and test.

**Step 5:** Commit.

---

### Task 4: Fix backend_stub.v compile guard

**Files:**
- Modify: `accessibility/backend_stub.v`

**Problem:** `@[if !darwin]` allows stub to compile on Linux where
`backend_linux.v` already provides a real backend. The guard is
too broad.

**Step 1:** Check if V supports combined `@[if]` guards like
`@[if !darwin && !linux]` or if file suffix is the right approach.

**Step 2:** Most likely fix: remove the `@[if !darwin]` attribute
entirely since V's `_stub` files or manual platform suffixes
handle this. Or add `@[if !linux]` as a second attribute. Verify
which approach V supports.

**Step 3:** Update the misleading comment from "non-macOS
platforms" to "platforms without native accessibility (Windows,
FreeBSD, etc.)".

**Step 4:** Format and test.

**Step 5:** Commit.

---

### Task 5: Fix IME vstring borrowing C pointer

**Files:**
- Modify: `api.v:472,500`

**Problem:** `unsafe { text.vstring() }` borrows the C pointer
without copying. If the C caller reuses the buffer, retained
references point to freed memory.

**Step 1:** Replace both occurrences:
```v
// Before:
v_text := unsafe { text.vstring() }
// After:
v_text := unsafe { cstring_to_vstring(text) }
```

`cstring_to_vstring` copies the string data, making it safe.

**Step 2:** Format and test.

**Step 3:** Commit.

---

### Task 6: Fix trim(', ') corrupting font family names

**Files:**
- Modify: `context.v:474-486`

**Problem:** `new_fam.trim(', ')` strips individual characters
from the set {',', ' ', '\''}, not the substring ", ". This
can corrupt font family names starting/ending with those chars.

**Step 1:** Replace with proper logic:
```v
// Only prepend comma when original family is non-empty
if fam.len > 0 {
    new_fam = fam
}
for alias in aliases {
    if new_fam.len > 0 {
        new_fam += ', '
    }
    new_fam += alias
}
```

**Step 2:** Format and test.

**Step 3:** Commit.

---

### Task 7: Fix frame_counter increment per draw call

**Files:**
- Modify: `renderer.v`

**Problem:** `frame_counter` is incremented in draw_layout (175),
draw_layout_impl (808-811), and draw_layout_placed (610-611).
Multiple draws per frame skew LRU ages and cause premature
glyph eviction.

**Step 1:** Remove frame_counter increment from all draw methods.

**Step 2:** Add it to `commit()` instead (called once per frame):
```v
pub fn (mut renderer Renderer) commit() {
    renderer.atlas.frame_counter++
    // ... existing commit logic
}
```

**Step 3:** Format and test.

**Step 4:** Commit.

---

### Task 8: Fix division by zero in gradient computation

**Files:**
- Modify: `renderer.v:521` (emit_decoration_quad area)

**Problem:** `grad_w` and `grad_h` can be 0 when layout has
zero visual dimensions but has_gradient is true.

**Step 1:** Add guard:
```v
grad_w := if layout.visual_width > 0 {
    f32(layout.visual_width)
} else {
    f32(1.0)
}
grad_h := if layout.visual_height > 0 {
    f32(layout.visual_height)
} else {
    f32(1.0)
}
```

**Step 2:** Format and test.

**Step 3:** Commit.

---

### Task 9: Fix atlas reset cache_ages orphans

**Files:**
- Modify: `glyph_atlas.v:326-333, 406-411`

**Problem:** Atlas reset evicts from `renderer.cache` but not
`renderer.cache_ages`, leaving orphan entries.

**Step 1:** Add cache_ages cleanup after cache eviction:
```v
for key, c in renderer.cache {
    if c.page == reset_page {
        renderer.cache.delete(key)
        renderer.cache_ages.delete(key)  // Add this
    }
}
```

**Step 2:** Apply same fix in load_stroked_glyph path.

**Step 3:** Format and test.

**Step 4:** Commit.

---

### Task 10: Fix FT_Glyph leak on error in load_stroked_glyph

**Files:**
- Modify: `glyph_atlas.v:370-414`

**Problem:** If ft_bitmap_to_bitmap or insert_bitmap fails,
`ft_glyph` is not freed (FT_Done_Glyph at line 414 not reached).

**Step 1:** Add defer immediately after successful FT_Get_Glyph:
```v
if C.FT_Get_Glyph(glyph, &ft_glyph) != 0 {
    return error('FT_Get_Glyph failed')
}
defer { C.FT_Done_Glyph(ft_glyph) }
```

Remove the manual FT_Done_Glyph call at line 414.

**Step 2:** Format and test.

**Step 3:** Commit.

---

### Task 11: Fix grow_page height not clamped

**Files:**
- Modify: `glyph_atlas.v:662`

**Problem:** `new_height = page.height * 2` can exceed max_height.

**Step 1:** Add clamp:
```v
mut new_height := page.height * 2
if new_height > atlas.max_height {
    new_height = atlas.max_height
}
```

**Step 2:** Format and test.

**Step 3:** Commit.

---

### Task 12: Fix debug/release item branch divergence

**Files:**
- Modify: `layout_iter.v:218-297`

**Problem:** Debug branch includes `run_text` but NOT `object_id`,
`is_object`. Release branch includes `object_id`, `is_object` but
NOT `run_text`. Debug also skips glyph_count > 0 filter.

**Step 1:** Add missing fields to debug branch:
```v
$if debug {
    items << Item{
        run_text:  run_str
        object_id: attrs.object_id  // Add
        is_object: attrs.is_object  // Add
        // ... rest unchanged
    }
    // Add filter
    if items.last().glyph_count > 0
        || items.last().is_object {
        // keep
    } else {
        items.pop()
    }
}
```

Or better: unify both branches and only conditionally set run_text.

**Step 2:** Format and test.

**Step 3:** Commit.

---

### Task 13: Fix move_cursor_line_end wrong fallback

**Files:**
- Modify: `layout_query.v:405-408`

**Problem:** Fallback returns `l.log_attrs.len - 1` (array index)
instead of a byte index.

**Step 1:** Fix fallback to return `byte_index` unchanged:
```v
return byte_index  // instead of l.log_attrs.len - 1
```

**Step 2:** Format and test.

**Step 3:** Commit.

---

### Task 14: Fix mutation functions bounds checking

**Files:**
- Modify: `layout_mutation.v:31,73,199,258`

**Problem:** insert_text, delete_backward, delete_selection,
get_selected_text don't validate cursor/anchor bounds. Out-of-range
values cause panics.

**Step 1:** Add bounds clamping at start of each function:
```v
cursor = math.clamp(cursor, 0, text.len)
```

**Step 2:** Format and test.

**Step 3:** Commit.

---

### Task 15: Fix announcer dead key rune mismatch

**Files:**
- Modify: `accessibility/announcer.v:196-207`

**Problem:** Checks for Unicode accents (0x00B4, 0x00B8) but
composition.v uses ASCII chars (backtick, apostrophe, caret, etc.).

**Step 1:** Match the rune values used in composition.v:
```v
fn announce_dead_key(dead rune, ...) {
    name := match dead {
        `\`` { 'grave accent' }
        `'`  { 'acute accent' }
        `^`  { 'circumflex' }
        `~`  { 'tilde' }
        `"`  { 'diaeresis' }
        `,`  { 'cedilla' }
        `:`  { 'diaeresis' }
        else { 'dead key' }
    }
    // ...
}
```

**Step 2:** Fix byte vs rune threshold in announce_selection:
```v
// Use rune count for both threshold and message
rune_count := selected_text.runes().len
if rune_count <= 20 {
    // read aloud
} else {
    // "N characters selected"
}
```

**Step 3:** Format and test.

**Step 4:** Commit.

---

### Task 16: Fix @[if darwin] in objc_bindings_darwin.v

**Files:**
- Modify: `accessibility/objc_bindings_darwin.v:6`

**Problem:** `@[if darwin]` may not work in V 0.5.0 (per
MEMORY.md). The `_darwin.v` file suffix already restricts to
macOS. The `@[if darwin]` is redundant.

**Step 1:** Remove the `@[if darwin]` attribute since the file
suffix handles platform restriction.

**Step 2:** Remove redundant `$if macos` guard inside
`announce_to_voiceover` (line 139) since the entire file is
macOS-only.

**Step 3:** Format and test.

**Step 4:** Commit.

---

### Task 17: Add `implements` keyword to accessibility backends

**Files:**
- Modify: `accessibility/backend_darwin.v:8`
- Modify: `accessibility/backend_linux.v:8`
- Modify: `accessibility/backend_stub.v:8`

**Problem:** Per CLAUDE.md working agreements, interface
implementations must use V's `implements` keyword.

**Step 1:** Add to each struct:
```v
struct DarwinAccessibilityBackend {
implements AccessibilityBackend
    // ...
}
```

**Step 2:** Format and test.

**Step 3:** Commit.

---

## Unresolved Questions

1. Does Layout carry original text (`l.text` field) for Task 1?
   If not, how to access text in extract_text()?
2. V support for `@[if !darwin && !linux]`? Needed for Task 4.
3. Is `sg.destroy_image` the correct cleanup for Sokol images
   in Task 2?
4. Should undo/redo return `none` or original text on bounds
   error (Task 3)?
