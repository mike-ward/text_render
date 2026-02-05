# Phase 31: Fix - Research

**Researched:** 2026-02-05
**Domain:** V language memory safety, buffer management, git revert strategy
**Confidence:** HIGH

## Summary

Phase 31 applies memcpy fix to double-buffer swap without accumulation (Phase 27 root
cause). Research confirms V builtin vmemcpy is correct tool for buffer preservation,
unsafe blocks required, array.data field gives pointer access. Git revert fallback
requires reverting 2 commits in reverse order if fix fails.

User decisions constrain scope: memcpy fix first, full Phase 27 revert if ANY symptom
persists. Dirty-only vs all-pages copy is Claude's discretion (recommend all pages
for simplicity, correctness priority over perf per user budget). Keep Phase 30
diagnostic code ($if diag blocks).

**Primary recommendation:** Apply vmemcpy staging_front.data → staging_back.data
after swap in swap_staging_buffers(). All pages, not dirty-only (page-level dirty
flag doesn't track per-glyph state). Test with `v test .` before user validation.

## Standard Stack

V builtin functions for memory operations:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| builtin.vmemcpy | V stdlib | Copy n bytes src→dest | Only buffer copy in V |
| builtin.unsafe | V stdlib | Mark memory-unsafe ops | Required for vmemcpy |
| builtin.assert | V stdlib | Test verification | Standard V testing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| git revert | git 2.x | Undo commits cleanly | If memcpy fix fails |
| v test | V CLI | Run test suite | Pre-validation gate |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| vmemcpy | Manual loop | Slower, no compiler optimization |
| All-pages copy | Dirty-page tracking | Complex, error-prone, premature |
| Fix forward | Immediate revert | Doesn't attempt fix-first strategy |

**Installation:**
Builtin functions, no install needed. Git already present.

## Architecture Patterns

### Recommended Change Scope
```
glyph_atlas.v
└── swap_staging_buffers()  # ONLY function modified
    ├── Existing: pointer swap
    └── ADD: vmemcpy front→back after swap
```

### Pattern 1: Buffer Preservation After Swap
**What:** Copy staging_front.data to staging_back.data after pointer swap to preserve
accumulated glyph data for next frame's CPU writes.

**When to use:** Double-buffer systems where CPU writes accumulate across frames and
buffers alternate roles.

**Example:**
```v
// Source: Phase 30 diagnosis report + V builtin docs
fn (mut page AtlasPage) swap_staging_buffers() {
	// Existing diagnostic code preserved
	$if diag ? {
		sample_len := if page.staging_front.len < 16 { page.staging_front.len } else { 16 }
		front_pre := page.staging_front[..sample_len]
		back_pre := page.staging_back[..sample_len]
		identical_pre := front_pre == back_pre
		eprintln('[DIAG] PRE-SWAP: front[0..16]=${front_pre} back[0..16]=${back_pre} identical=${identical_pre}')
	}

	// Existing swap logic
	tmp := page.staging_front
	page.staging_front = page.staging_back
	page.staging_back = tmp

	// FIX: Preserve accumulated data for next frame
	unsafe {
		vmemcpy(page.staging_back.data, page.staging_front.data, page.staging_front.len)
	}

	// Existing diagnostic code preserved
	$if diag ? {
		sample_len := if page.staging_front.len < 16 { page.staging_front.len } else { 16 }
		front_post := page.staging_front[..sample_len]
		back_post := page.staging_back[..sample_len]
		identical_post := front_post == back_post
		eprintln('[DIAG] POST-SWAP: front[0..16]=${front_post} back[0..16]=${back_post} identical=${identical_post}')
		if identical_post {
			eprintln('[DIAG] WARNING: Buffers identical after swap - possible data loss')
		}
	}
}
```

### Pattern 2: Clean Git Revert (If Fix Fails)
**What:** Revert Phase 27 commits in reverse chronological order to restore pre-async
state.

**When to use:** If ANY of 3 symptoms persists after memcpy fix per user threshold.

**Example:**
```bash
# Revert in reverse order (newest first)
git revert 2a63170 --no-edit  # async commit with swap+upload
git revert 9febd3d --no-edit  # add staging buffers to AtlasPage

# Also revert Phase 30 diag code that references async paths (dead code)
# User decision: if full revert, also remove diagnostics referencing removed code
```

### Anti-Patterns to Avoid
- **Dirty-page-only copy:** Page dirty flag is coarse (page-level), doesn't track
  which glyphs are in which buffer. Copying only dirty pages still loses non-dirty
  accumulated glyphs.
- **Manual byte-by-byte copy:** V arrays with vmemcpy exist for this. Don't hand-roll.
- **Modifying sync path:** Sync path (renderer.v:113-127) does NOT have bug, copies
  staging_back→image.data directly with no swap. Do not touch.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Buffer copy | for loop over bytes | vmemcpy | Compiler-optimized, standard |
| Dirty tracking | Per-glyph state map | Copy all pages | Premature optimization, complex |
| Partial revert | Cherry-pick changes | Full commit revert | Clean history, no merge conflicts |
| Test validation | Manual demo runs | `v test .` | Automated, catches regressions |

**Key insight:** Correctness priority over performance per user budget. Simple all-page
copy is correct, measurable, validatable. Dirty-only optimization adds complexity without
validated need.

## Common Pitfalls

### Pitfall 1: Wrong vmemcpy Parameter Order
**What goes wrong:** Swapped src/dest causes front←back copy instead of back←front,
perpetuating bug.

**Why it happens:** vmemcpy signature is (dest, src, n) matching C memcpy, but reading
left-to-right suggests opposite.

**How to avoid:** Remember assignment direction: page.staging_back = front's data.
Dest is staging_back, src is staging_front.

**Warning signs:** Post-fix symptoms unchanged. Diag output shows identical buffers after
swap (wrong - copy makes them identical, expected).

### Pitfall 2: Forgetting unsafe Block
**What goes wrong:** Compiler error "vmemcpy must be called in unsafe block".

**Why it happens:** V safety model requires explicit unsafe marking for pointer ops.

**How to avoid:** Wrap vmemcpy call in `unsafe { }` block per V convention.

**Warning signs:** Build fails with clear error message.

### Pitfall 3: Using .len Instead of .data for Pointers
**What goes wrong:** Passing page.staging_front to vmemcpy (array itself) instead of
page.staging_front.data (pointer to array data).

**Why it happens:** V arrays are value types with data field containing actual pointer.

**How to avoid:** Access .data field for pointer: staging_front.data, staging_back.data.

**Warning signs:** Compiler type error "expected voidptr, got []u8".

### Pitfall 4: Modifying Sync Path
**What goes wrong:** Changing renderer.v sync path (lines 113-127) introduces new bug.

**Why it happens:** Misunderstanding root cause - sync path does NOT swap buffers, has
no accumulation bug.

**How to avoid:** Only modify swap_staging_buffers() in glyph_atlas.v. Do not touch
renderer.v commit() sync path.

**Warning signs:** Sync mode (-d diag_sync) starts failing user validation.

### Pitfall 5: Incomplete Revert (If Fallback Needed)
**What goes wrong:** Reverting only one Phase 27 commit leaves codebase in broken state
(staging buffers allocated but not swapped, or swapped but not allocated).

**Why it happens:** Phase 27 implemented in 2 commits (9febd3d adds buffers, 2a63170
uses them).

**How to avoid:** Revert BOTH commits in reverse order. Atomic operation: both or neither.

**Warning signs:** Compilation errors referencing staging_front/staging_back, or runtime
errors in atlas page allocation.

### Pitfall 6: Skipping `v test` Before User Validation
**What goes wrong:** User validation on stress_demo fails due to unrelated regression
caught by test suite.

**Why it happens:** Test suite catches API contract violations, memory safety issues.

**How to avoid:** Run `v test .` successfully before considering fix complete. User
requirement: tests must pass.

**Warning signs:** User reports bug unrelated to scroll symptoms, wasted validation time.

## Code Examples

Verified patterns from codebase and V documentation:

### vmemcpy Signature (V Builtin)
```v
// Source: github.com/vlang/v/blob/master/vlib/builtin/cfns_wrapper.c.v
@[inline; unsafe]
pub fn vmemcpy(dest voidptr, const_src voidptr, n isize) voidptr
```

### Array Data Field Access
```v
// Source: V array internal structure (verified in codebase usage)
// Arrays are value types with .data field containing pointer to heap data
staging_front []u8  // Array value type
staging_front.data  // voidptr to actual bytes (for vmemcpy)
staging_front.len   // int, byte count (for vmemcpy n parameter)
```

### Existing vmemcpy Usage in Codebase
```v
// Source: glyph_atlas.v:717 (grow_page), glyph_atlas.v:730 (staging resize)
unsafe {
	vmemcpy(new_data, page.image.data, int(old_size))
}

// Source: renderer.v:121 (sync path)
unsafe {
	vmemcpy(page.image.data, page.staging_back.data, page.staging_back.len)
}

// Source: glyph_atlas.v:808 (copy_bitmap_to_page row copy)
unsafe {
	vmemcpy(dst_ptr, src_ptr, row_bytes)
}
```

### V Test Pattern (Existing Tests)
```v
// Source: _validation_test.v:5-12
fn test_validate_text_valid() {
	result := validate_text_input('Hello, World!', 1024, 'test') or {
		assert false, 'Valid text should not error: ${err}'
		return
	}
	assert result == 'Hello, World!'
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Sync path only | Async swap + sync fallback | Phase 27 (v1.6) | CPU/GPU overlap, but introduced bug |
| Swap pointers only | Swap + memcpy (planned) | Phase 31 (v1.7) | Preserves accumulation, fixes regressions |
| No diagnostics | $if diag ? blocks | Phase 30 | Root cause identified via instrumentation |

**Deprecated/outdated:**
- Pointer swap without data copy: Insufficient for accumulated glyph data across frames.
- Assumption both buffers always identical: False - async path causes divergence.

## Open Questions

### Question 1: Dirty-only vs All-pages Copy Scope
- What we know: User marked as Claude's discretion. Page.dirty is coarse (page-level).
  No per-glyph tracking exists.
- What's unclear: Could dirty-only optimization work if we track which glyphs are in
  which buffer?
- Recommendation: Copy all pages for Phase 31. Correctness over perf per user budget.
  If perf becomes issue in Phase 32+, instrument first, optimize with data.

### Question 2: Auto-scroll Toggle Retention
- What we know: Phase 30 added auto-scroll to stress_demo for diagnostics. User marked
  retention as Claude's discretion.
- What's unclear: Does auto-scroll have value for Phase 32+ testing, or was it
  diagnostic-only?
- Recommendation: Keep auto-scroll. Useful for regression testing in Phase 32 (other
  demos). Low cost (simple toggle), high value (reproducible stress).

### Question 3: Post-Fix Diagnostic Output Expectation
- What we know: Phase 30 diag warns if staging_front == staging_back post-swap (line 782).
  After memcpy fix, buffers WILL be identical (correct behavior).
- What's unclear: Should we remove/invert the warning, or keep it for other failure modes?
- Recommendation: Keep warning but update message: "Buffers identical after swap+copy -
  expected with fix applied". Documents fix presence.

## Sources

### Primary (HIGH confidence)
- V builtin cfns_wrapper.c.v - vmemcpy/vmemset/vmemmove signatures verified
  [github.com/vlang/v/blob/master/vlib/builtin/cfns_wrapper.c.v](https://github.com/vlang/v/blob/master/vlib/builtin/cfns_wrapper.c.v)
- V official docs - memory-unsafe code requirements
  [docs.vlang.io/memory-unsafe-code.html](https://docs.vlang.io/memory-unsafe-code.html)
- V official docs - testing framework conventions
  [docs.vlang.io/testing.html](https://docs.vlang.io/testing.html)
- Codebase: glyph_atlas.v lines 717, 730, 808 - existing vmemcpy usage patterns
- Codebase: renderer.v lines 113-150 - sync vs async paths
- Phase 30 diagnosis report - root cause and fix recommendation
- Phase 27 commits - 9febd3d (buffers), 2a63170 (async commit)

### Secondary (MEDIUM confidence)
- Git revert documentation - multiple commit rollback strategies
  [git-scm.com/docs/git-revert](https://git-scm.com/docs/git-revert)
- V array implementation - .data field semantics
  [github.com/vlang/v/blob/master/vlib/builtin/array.v](https://github.com/vlang/v/blob/master/vlib/builtin/array.v)

### Tertiary (LOW confidence)
- None - all findings verified with primary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - V builtin functions verified in official repo, used in codebase
- Architecture: HIGH - Phase 30 diagnosis prescribes exact fix location and approach
- Pitfalls: HIGH - Derived from V safety model (docs) and existing codebase patterns

**Research date:** 2026-02-05
**Valid until:** 2026-03-07 (30 days) - V stdlib stable, git revert unchanged
