# Changelog

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
