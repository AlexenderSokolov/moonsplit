# MoonSplit v0.3.0 Remediation Implementation Plan

> **For agentic workers:** Use test-first implementation and task-scoped review. This plan is the executable record of the user-approved v0.3.0 remediation contract.

**Goal:** Extend MoonSplit from metadata equality grouping to rule-driven leakage detection, temporal forward validation, deterministic allocation refinement, and reproducible acceptance evidence.

**Architecture:** Preserve the v0.2 public holdout/K-fold path for schema v1. Add schema v2 parsing and a rule-aware grouping/audit path for exact keys, text Jaccard similarity, and source-scoped interval overlap. Keep temporal forward validation as a separate plan and audit model, with role manifests instead of retrofitting K-fold complement semantics.

**Tech stack:** MoonBit, `moonbitlang/core/bigint`, JSON/JSONL CLI, wasm-gc and JS targets, PowerShell and Bash acceptance runners.

**Global constraints:** No output directory overwrite; preserve exit codes 0/2/3/4; retain v1 fields and existing public constructors; use half-open intervals; same-seed output must be deterministic across input/rule ordering and both targets; do not claim external publication or official acceptance from local checks.

---

### Task 1: Establish compatible local validation and v0.3 input contracts

- [x] Use a project-local compatible MoonBit binary without changing the user's global installation; record the selected toolchain in generated acceptance evidence only.
- [x] Add failing parser and public API tests for schema v2 records, named intervals, leakage rules, duplicate rule IDs, invalid interval boundaries, and v1 compatibility.
- [x] Implement minimal record/spec extensions and normalization required by those tests.

### Task 2: Implement deterministic rule-aware components and audit

- [x] Add failing tests and fixtures for exact-key, text Jaccard, and source-scoped overlap relationships, including negative/boundary cases and input/rule order stability.
- [x] Implement union-by-size iterative DSU, canonical evidence edges, text candidate filtering with exact Jaccard verification, and interval scan grouping.
- [x] Add rule-aware independent audit tests proving a manually split text or interval relationship is rejected.

### Task 3: Implement time-forward planning and independent role audit

- [x] Add failing tests for validation retention, component conflict exclusion, gap/future/boundary reasons, invalid windows, and hand-calculated role manifests.
- [x] Implement temporal plan, roles, exclusions, and audit using the approved priority order.
- [x] Expose temporal planning and audit through the CLI without altering v1 K-fold semantics.

### Task 4: Refine grouped allocation, exports, and CLI integration

- [x] Add failing tests for overflow-safe objective comparisons, fixed local-improvement fixture, v2 plan/audit exports, and target byte equality.
- [x] Replace score/tolerance intermediates with BigInt and add deterministic bounded component moves.
- [x] Implement v2 evidence/audit output and route plan, validate, normalize-spec, and audit through schema-aware paths.

### Task 5: Build acceptance runners, fixtures, and project materials

- [x] Add fixed examples, negative controls, benchmark reports, hash manifest, and safe fresh-output acceptance runners.
- [x] Run required checks using the compatible toolchain and capture real results.
- [x] Update README, API/output docs, PROJECT.md, CHANGELOG, acceptance record, repository proposal, and external MoonSplit proposal with actual v0.3 evidence and acceptance deliverables.
