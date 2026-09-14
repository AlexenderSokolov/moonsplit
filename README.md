# MoonSplit

MoonSplit is a MoonBit CLI and library for leakage-aware dataset splitting and independent audit. Schema v2 combines declared exact keys, Unicode text near-duplicates, and source-scoped interval overlap into indivisible leakage components; it also provides explicit time-forward validation with per-record exclusion reasons.

`v0.3.0` is published at [GitHub](https://github.com/AlexenderSokolov/moonsplit/releases/tag/v0.3.0) and [Mooncakes](https://mooncakes.io/api-new/v0/manifest/AlexenderSokolov/moonsplit). The [acceptance record](docs/acceptance.md) links the matching tag, CI, registry and clean-install evidence. Official hackathon acceptance remains a decision of the organizers.

## Features

- Schema v1-compatible exact-key grouping with transitive closure.
- Schema v2 leakage rules: `exact_key`, Unicode character q-gram `text_jaccard`, and same-source half-open `interval_overlap`.
- Deterministic grouped holdout/K-fold allocation with a bounded local component-move optimization that never worsens greedy initialization.
- Time-forward validation windows with `train`, `validation`, and explicit `excluded` reasons.
- Independent audit rebuilt from raw records, spec, and assignment/role manifests.
- Canonical spec normalization and no-write validation preflight.
- Stable JSON, JSONL, and Markdown exports, including label-aware summaries and K-fold membership manifests.
- wasm-gc and JS targets.

## Installation

Run the checked-out source to reproduce this version:

```bash
git clone https://github.com/AlexenderSokolov/moonsplit.git
cd moonsplit
```

Install the released library with:

```bash
moon add AlexenderSokolov/moonsplit@0.3.0
```

The public APIs are subpackages such as `AlexenderSokolov/moonsplit/src/record` and `AlexenderSokolov/moonsplit/src/plan`; see [docs/api.md](docs/api.md). The release was verified in a new project with this exact dependency, an imported public API, `moon check --deny-warn`, `moon build --deny-warn`, and an installed CLI wrapper. Details and limits of the binary-wrapper verification are in [docs/acceptance.md](docs/acceptance.md).

The `examples/` directory contains ready-made JSON, JSONL, and split specs.

## Quick Start

```powershell
./run_check.ps1
./run_acceptance.ps1
./run_demo.ps1
```

```bash
./run_check.sh
./run_acceptance.sh
./run_demo.sh
./run_bench.sh
```

## Commands

```bash
moon run cmd/moonsplit -- plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out examples/demo_run
moon run cmd/moonsplit -- audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments examples/demo_run/assignments.jsonl
moon run cmd/moonsplit -- audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments examples/demo_run/assignments.jsonl --report json
moon run cmd/moonsplit -- normalize-spec --spec examples/holdout_spec.json
moon run cmd/moonsplit -- validate --data examples/voice_records.jsonl --spec examples/holdout_spec.json --format jsonl
moon run cmd/moonsplit -- plan --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --out artifacts/v2_plan --format jsonl
moon run cmd/moonsplit -- audit --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --assignments artifacts/v2_plan/assignments.jsonl --format jsonl --report json
moon run cmd/moonsplit -- plan --data examples/time_records.jsonl --spec examples/time_forward_spec.json --out artifacts/time_plan --format jsonl
moon run cmd/moonsplit -- audit --data examples/time_records.jsonl --spec examples/time_forward_spec.json --roles artifacts/time_plan/roles.jsonl --format jsonl --report json
moon run cmd/moonsplit -- bench --mode interval --records 100000
moon run cmd/moonsplit -- bench --mode text --records 10000
moon run cmd/moonsplit -- demo --out examples/demo_run
moon run cmd/moonsplit -- --version
moon run cmd/moonsplit -- smoke --data examples/voice_records.jsonl
```

The output directory must not already exist. The parent directory must exist. Exit codes are:

- `0`: success
- `2`: usage, input, or read error
- `3`: audit failure
- `4`: output write error

`smoke` reads one input file and prints its character count for quick file-system checks.

Schema v1 holdout plans write five files and v1 K-fold plans write six. Schema v2 grouped holdout writes seven (`evidence.jsonl` and `audit.json` are added), grouped K-fold writes eight (plus `folds.jsonl`), and `time_forward` writes eight role/audit files. Existing v1 APIs and input schemas remain available. See [docs/output.md](docs/output.md) and [docs/api.md](docs/api.md).

The output files are documented in [docs/output.md](docs/output.md).

## Scope

Text Jaccard detects character-overlap near duplicates; it does not claim semantic paraphrase, audio, image, or video similarity. Interval overlap only compares records sharing the declared source key and treats intervals as `[start, end)`, so touching endpoints do not match. Time coordinates must use the explicitly declared interval, unit, and epoch; source-local character offsets are not global time. MoonSplit does not train models, schedule jobs, manage databases, or claim that a dataset is completely leak-free.

## v2 record and specification shape

V2 records retain `id`, optional `label`, and `keys`; they add optional `text` and named `intervals`:

```json
{"id":"r1","keys":{"source":"doc-1"},"text":"example text","intervals":{"segment":{"start":0,"end":20}}}
```

The default text rule uses Unicode 3-gram sets and `threshold_bp: 8000`. It folds ASCII case and repeated whitespace, preserves Chinese characters and punctuation, and treats equality at the threshold as a match. Missing or empty normalized text is an input error when that rule is enabled. A dense corpus may require quadratic candidate comparisons; MoonSplit does not silently cap them, and rejects `text_count_overflow` before its portable `Int` evidence counters could wrap. Memory capacity remains a practical limit for unusually dense corpora.

`time_forward` assigns each record in every validation window in this order: complete-window validation; other members of a validation component as `excluded/component_conflict`; historical training ending no later than `validation_start - gap`; then `gap`, `future`, or `boundary_overlap` exclusions. Active train and validation sets must both be non-empty.
