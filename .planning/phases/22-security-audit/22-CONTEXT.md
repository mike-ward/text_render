# Phase 22: Security Audit - Context

**Gathered:** 2026-02-04
**Status:** Ready for planning

<domain>
## Phase Boundary

All input paths validated, all error paths verified, all resources properly cleaned up. This is a
hardening audit focused on defensive coding — not new features.

</domain>

<decisions>
## Implementation Decisions

### Input Validation Behavior
- Invalid UTF-8: Return error (reject entire string, caller must fix)
- Null/empty strings: Return error (explicitly reject, not silent no-op)
- File paths: Existence check only (let FreeType handle format validation)
- Numeric parameters: Claude's discretion (clamp vs error based on context)

### Error Reporting Strategy
- Error detail: Descriptive ("Invalid UTF-8 at byte 47" — helps debugging)
- Source location: Yes, always include V source file:line
- Error chains: Claude's discretion (contextual decision)
- Library errors: Wrap with context ("FreeType error 6 loading font X")

### Audit Priorities
- Primary threat model: Untrusted text content (users pass arbitrary external text)
- Resource cleanup priority: Claude's discretion based on codebase analysis
- Audit scope: Everything (all code paths regardless of exposure)
- DoS protection: Add limits (max string length, max font size, etc.)

### Verification Approach
- Primary method: Unit tests per fix (each fix has test proving the issue)
- Memory verification: V's GC/autofree (trust V's memory management)
- Test organization: Inline with existing test files
- Documentation: Both in-code comments AND separate SECURITY.md

### Claude's Discretion
- Numeric parameter validation (clamp vs reject per-parameter)
- Error chain handling (root cause vs full chain)
- Resource cleanup prioritization order
- Specific DoS limits (exact max values)

</decisions>

<specifics>
## Specific Ideas

- Errors should help debugging — include byte positions, file names, parameter values
- Security model should be documented centrally (SECURITY.md) with inline details
- All fixes need corresponding tests proving the vulnerability is closed

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 22-security-audit*
*Context gathered: 2026-02-04*
