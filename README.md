# MoonSplit

MoonSplit is a MoonBit CLI and library for grouped dataset splitting and leakage auditing. It keeps records linked by declared metadata keys in the same partition, produces deterministic split plans, and independently audits the resulting assignment.

This release is `0.2.0`.

## Features

- Multi-key isolation with transitive grouping.
- Deterministic holdout and k-fold splitting.
- Independent audit from raw records and assignment manifest.
- Canonical spec normalization and no-write validation preflight.
- Stable JSON, JSONL, and Markdown exports, including label-aware summaries and K-fold membership manifests.
- wasm-gc and JS targets.

## Installation

```bash
moon add AlexenderSokolov/moonsplit
```

To run from source:

```bash
git clone https://github.com/AlexenderSokolov/moonsplit.git
cd moonsplit
```

The `examples/` directory contains ready-made JSON, JSONL, and split specs.

## Quick Start

```powershell
./run_check.ps1
./run_demo.ps1
```

```bash
./run_check.sh
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

Holdout plans write the four legacy files plus `summary.json`. K-fold plans also write `folds.jsonl`. Existing consumers should ignore unknown files; the legacy file fields remain unchanged, but the Markdown bytes and total output file count are not preserved from 0.1.x.

The output files are documented in [docs/output.md](docs/output.md).

## Scope

MoonSplit does not do time-series splitting, raw media similarity detection, fingerprinting, training, scheduling, databases, web UIs, or CSV frameworks. It does not claim that data are completely leak-free; it only audits the declared metadata isolation rules.
