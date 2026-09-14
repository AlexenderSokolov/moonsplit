# Output Contract

`plan` writes five files for a holdout plan and six files for a K-fold plan into a new output directory. The directory must not exist; its parent directory must exist. All files use UTF-8 and LF line endings. Their bytes are deterministic for the same record set, spec, seed, and target, independent of record input order (and, for v2, rule declaration order).

## plan.json

A stable, human-readable JSON summary. It contains:

- `schema_version`: output contract version.
- `algorithm`: fixed as `group-greedy-v1`.
- `kind`: `holdout` or `kfold`.
- `seed`, `isolation_keys`, `balance_labels`, and `ratio_tolerance_bp` copied from the spec.
- `partitions`: partition names and weights in spec order.
- `k`: the K-fold size, or `0` for holdout.
- `component_count` and `assignment_count`.
- `warnings`: deterministic text warnings.

## assignments.jsonl

One assignment per line:

```json
{"id": "utt_0001", "partition": "train"}
```

Lines are sorted by record `id`. This is the only input used by the independent `audit` command.

## components.jsonl

One component per line, sorted by component ID. `member_ids` are sorted lexicographically. `witness_edges` are canonical and sorted by `(key_name, key_value, left_id, right_id)`:

```json
{"id":"spk_01","member_ids":["utt_0001"],"witness_edges":[]}
```

Each edge has lexicographically ordered endpoint IDs.

## report.md

A deterministic Markdown report with the algorithm, seed, isolation keys, component and assignment counts, partition ratios in basis points, per-partition label counts, and warnings. It is a summary, not an independent audit result.

## summary.json

A stable machine-readable summary with the fixed top-level fields `schema_version`, `algorithm`, `records`, `components`, `largest_component`, and `partitions`. Each partition contains `name`, `weight`, `record_count`, `target_bp`, `actual_bp`, `deviation_bp`, `label_counts`, and `unlabeled_count`. Label keys are sorted lexicographically; empty labels and unlabeled records are distinct.

## folds.jsonl

K-fold plans only. Each record appears exactly once, sorted by record ID:

```json
{"id": "utt_0001", "validation_fold": "fold_0"}
```

The file has no trailing newline. Holdout plans do not create it.

## Compatibility

The legacy v1 fields of `plan.json`, `assignments.jsonl`, `components.jsonl`, and the report remain available. Schema v2 adds its own files and extends the report; consumers must select by `schema_version`, ignore unknown files, and must not assume a four-file directory or byte-identical Markdown across schema versions.

## CLI behavior

`plan` and `demo` do not overwrite an existing output path. They require the parent directory to exist. Exit code `4` covers output-directory creation, inspection, or file-writing failures.

## Schema v2 grouped output

Schema v2 `holdout` writes seven files:

1. `plan.json`
2. `assignments.jsonl`
3. `components.jsonl`
4. `report.md`
5. `summary.json`
6. `evidence.jsonl`
7. `audit.json`

V2 K-fold writes the same seven files plus `folds.jsonl`, for eight files. `plan.json` includes the canonical leakage rules, `algorithm: "group-local-v2"`, greedy and final objectives, and completed local-move rounds. `summary.json` includes text candidate and exact-comparison counts. `audit.json` records an audit rebuilt from the raw data, v2 spec, and assignment manifest.

`evidence.jsonl` contains selected rule witnesses with component ID, endpoints, rule ID/type, and rule detail. It is a deterministic explanatory forest, not a claim to list every matching text or interval pair. V2 `components.jsonl` reports member IDs and witness-edge counts; use `evidence.jsonl` for witness details.

## Schema v2 time-forward output

`time_forward` always writes eight files:

1. `plan.json`
2. `roles.jsonl`
3. `exclusions.jsonl`
4. `components.jsonl`
5. `witnesses.jsonl`
6. `summary.json`
7. `report.md`
8. `audit.json`

`roles.jsonl` is the authoritative audit manifest. Every line has `fold_id`, `id`, `role`, and `reason`; every raw record occurs exactly once in each declared fold. `exclusions.jsonl` is derived from those `role: "excluded"` rows and is not an independent audit input. Reasons are `validation_window`, `component_conflict`, `historical`, `gap`, `future`, and `boundary_overlap` as applicable to the role policy.

`witnesses.jsonl` is an explanatory forest. Time audit rebuilds components and roles from the original records and spec, so changing a plan summary cannot make a bad role manifest pass.

## Determinism boundary

For a fixed schema, record set, spec, seed, and target, product files have deterministic bytes regardless of record input order or rule declaration order. Acceptance evidence such as elapsed time, timestamps, toolchain paths, machine metadata, and input hashes belongs under `artifacts/acceptance_*` and is deliberately excluded from those product-file comparisons. V1 and v2 have different file-count contracts; consumers must select the contract by `schema_version`.
