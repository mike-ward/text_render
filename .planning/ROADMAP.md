# Roadmap

## Milestone: Pango RAII Refactor
Refactor manual memory management of Pango pointers into V structs with RAII-like ownership.

### Phase 35: Pango Ownership
**Goal:** Implement Pango wrappers and refactor codebase to use them for safer memory management.
**Status:** [Complete]
**Plans:**
- [x] 35-01-PLAN.md — Core Pango wrappers
- [x] 35-02-PLAN.md — Refactor Context and Attributes
- [x] 35-03-PLAN.md — Refactor Layout and Pango Integration
- [x] 35-04-PLAN.md — Final cleanup and verification

### Phase 36: Integration Testing
**Goal:** Replace 'unsafe { nil }' mocks in unit tests with real Pango/Cairo backend interactions to ensure C-binding and layout logic integrity.
**Status:** [Complete]
**Plans:**
- [x] 36-01-PLAN.md — Integration Test Infrastructure
- [x] 36-02-PLAN.md — API Test Refactor

### Phase 37: Layout Cache Optimization
**Goal:** Optimize `get_cache_key` and improve telemetry for layout cache.
**Status:** [Complete]
**Plans:**
- [x] 37-01-PLAN.md — Layout Cache Telemetry
- [x] 37-02-PLAN.md — Layout Cache Optimization

### Phase 38: macOS Accessibility Completion
**Goal:** Complete `DarwinAccessibilityBackend` to enable VoiceOver support (tree building, properties, interaction).
**Status:** [In Progress]
**Plans:**
- [x] 38-01-PLAN.md — Core Tree Implementation
- [x] 38-02-PLAN.md — Interaction & Text Support
- [ ] 38-03-PLAN.md — Verification

### Phase 39: IME Quality and Security Polish
**Goal:** Improve consistency, security, and quality of recently added IME code.
**Status:** [Complete]
**Plans:**
- [x] 39-01-PLAN.md — V-side Polish
- [x] 39-02-PLAN.md — macOS Native Polish

### Phase 40: IME API Refinement and Encapsulation
**Goal:** Move repetitive IME callback logic into 'api.v' to improve consistency and reduce boilerplate.
**Status:** [Planned]
**Plans:**
- [ ] 40-01-PLAN.md — Refactor TextSystem for IME state management
- [ ] 40-02-PLAN.md — Provide StandardIMEHandler and callbacks in api.v
- [ ] 40-03-PLAN.md — Update editor_demo.v to use refined API