# Changelog

## 0.3.0 - 2026-09-14

### Added

- Schema v2 records, specifications, and rule-aware components with `exact_key`, Unicode q-gram `text_jaccard`, and same-source half-open `interval_overlap`.
- Independent v2 grouped audit, rule witness forests, text candidate/comparison evidence, and 7/8-file grouped output contracts.
- `time_forward` planning and audit with explicit coordinate metadata, validation windows, role manifests, component-conflict exclusions, and 8-file temporal output.
- Deterministic local component-move optimization after greedy grouping, fixed-case exhaustive evidence, expanded bench modes, and `run_acceptance` entries.

### Changed

- v1 union-find now uses iterative path compression and union by size; v1 scoring, ratio checks, and summaries avoid intermediate `Int` overflow through `BigInt` arithmetic.
- Rule/record/component ordering is explicit and stable across record reversal and rule declaration order.
- CLI, README, API/output documentation, proposal material, project memory, CI, and acceptance records now describe v0.3 contracts.

### Compatibility and release status

- V1 JSON, library APIs, holdout/K-fold semantics, and 5/6-file output contracts remain supported.
- V2 output contracts are selected by `schema_version` and must not be compared byte-for-byte with v1 layouts.
- [GitHub Release](https://github.com/AlexenderSokolov/moonsplit/releases/tag/v0.3.0)、main/tag CI、[Mooncakes manifest](https://mooncakes.io/api-new/v0/manifest/AlexenderSokolov/moonsplit)、干净安装和最终验收摘要已记录在 `docs/acceptance.md`。Official hackathon acceptance remains the organizers' decision.

## 0.2.0 - 2026-09-11

### Added

- Canonical `SplitSpec::to_json()` serialization and `normalize-spec` CLI command.
- Component diagnostics, deterministic partition summaries, and label-aware `summary.json` output.
- Non-fatal exact ratio-tolerance warnings.
- Stable audit JSON reports via `audit --report json`.
- K-fold `folds.jsonl` membership manifests and no-write `validate` preflight.
- Expanded multi-target acceptance fixtures and format checks.

### Compatibility

- `plan.json`, `assignments.jsonl`, and `components.jsonl` retain their existing fields.
- Holdout output grows from four files to five; K-fold output has six. Consumers must ignore unknown files, and the Markdown report is extended.

## 0.1.1 - 2026-09-06

### Added

- `--version` and `version` CLI entry points.
- Output file contract documentation.
- K-fold `fold_members` API documentation.

## 0.1.0 - 2026-09-06

- Initial grouped dataset splitting and leakage audit library and CLI.
- Deterministic holdout and K-fold assignment.
- Independent audit from raw records and assignment manifests.
- Stable JSON, JSONL, and Markdown exports for wasm-gc and JS.
