# Output Contract

`plan` writes five files for a holdout plan and six files for a K-fold plan into a new output directory. The directory must not exist; its parent directory must exist. All files use UTF-8 and LF line endings. Their bytes are deterministic for the same record set, spec, input order, and target.

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

The fields of `plan.json`, `assignments.jsonl`, `components.jsonl`, and the legacy report sections remain available. v0.2.0 adds output files and extends `report.md`; consumers must ignore unknown files and must not assume a four-file directory or byte-identical Markdown.

## CLI behavior

`plan` and `demo` do not overwrite an existing output path. They require the parent directory to exist. Exit code `4` covers output-directory creation, inspection, or file-writing failures.
