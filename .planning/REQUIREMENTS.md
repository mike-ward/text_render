# Requirements: VGlyph Memory & Safety Hardening

**Defined:** 2026-02-01
**Core Value:** Prevent crashes and undefined behavior from memory safety issues

## v1 Requirements

### Memory Operations (glyph_atlas.v)

- [ ] **MEM-01**: Add null check after vcalloc at line 72 before dereferencing
- [ ] **MEM-02**: Add null check after vcalloc at line 389 before dereferencing
- [ ] **MEM-03**: Add null check after vcalloc at line 439 before dereferencing
- [ ] **MEM-04**: Add null checks after vcalloc at lines 447-450 before dereferencing
- [ ] **MEM-05**: Validate width * height doesn't overflow before allocation

### Error Propagation (glyph_atlas.v)

- [ ] **ERR-01**: Change new_glyph_atlas return type to `!GlyphAtlas`
- [ ] **ERR-02**: Replace assert at line 49 with error return
- [ ] **ERR-03**: Replace assert at line 53 with error return
- [ ] **ERR-04**: Replace assert at line 73 with error return for allocation failure
- [ ] **ERR-05**: Update all callers to handle GlyphAtlas error

### Pointer Safety (layout.v)

- [ ] **PTR-01**: Document unsafe pointer cast assumption at line 156
- [ ] **PTR-02**: Add $if debug block with runtime type validation

### String Lifetime (layout.v)

- [ ] **STR-01**: Clone object.id string before storing in Pango attribute
- [ ] **STR-02**: Free cloned string when layout is destroyed

## v2 Requirements

(None — all memory/safety issues addressed in v1)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Performance optimizations | Separate CONCERNS.md section, different scope |
| Tech debt cleanup | Separate CONCERNS.md section, different scope |
| Test coverage expansion | Separate CONCERNS.md section, different scope |
| Dependency version pinning | Separate CONCERNS.md section, different scope |
| Thread safety | V is single-threaded by design per CONCERNS.md |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| MEM-01 | TBD | Pending |
| MEM-02 | TBD | Pending |
| MEM-03 | TBD | Pending |
| MEM-04 | TBD | Pending |
| MEM-05 | TBD | Pending |
| ERR-01 | TBD | Pending |
| ERR-02 | TBD | Pending |
| ERR-03 | TBD | Pending |
| ERR-04 | TBD | Pending |
| ERR-05 | TBD | Pending |
| PTR-01 | TBD | Pending |
| PTR-02 | TBD | Pending |
| STR-01 | TBD | Pending |
| STR-02 | TBD | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 0
- Unmapped: 14

---
*Requirements defined: 2026-02-01*
*Last updated: 2026-02-01 after initial definition*
