# Output Contract

`plan` writes four files into a new output directory. The directory must not exist; its parent directory must exist. All files use UTF-8 and LF line endings. Their bytes are deterministic for the same record set, spec, input order, and target.

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

A deterministic Markdown report with the algorithm, seed, isolation keys, component and assignment counts, partition counts in spec order, and warnings. It is a summary, not an independent audit result.

## CLI behavior

`plan` and `demo` do not overwrite an existing output path. They require the parent directory to exist. Exit code `4` covers output-directory creation, inspection, or file-writing failures.
