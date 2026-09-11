# API

## Records

```moonbit
pub fn parse_records(
  input : String,
  format : InputFormat,
) -> Result[Array[Record], Array[Issue]]
```

`InputFormat` is either `Json` or `Jsonl`. A record has a non-empty string `id`, an optional string `label`, and an object `keys` whose values are strings.

## Spec

```moonbit
pub fn parse_spec(input : String) -> Result[SplitSpec, Array[Issue]]
```

`kind` can be `holdout` or `kfold`. `isolation_keys` must contain 1 to 8 unique non-empty key names. Holdout accepts 2 to 8 partitions with positive integer weights. K-fold accepts `k` from 2 to 20.

`SplitSpec::to_json()` emits the canonical specification form: fields use a fixed order, default values are explicit, isolation keys are sorted lexicographically, and holdout partitions retain declaration order. K-fold output contains `k` instead of generated partitions.

## Grouping

```moonbit
pub fn build_components(
  records : Array[Record],
  isolation_keys : Array[String],
) -> Result[Components, Array[Issue]]
```

Records with the same `(key_name, key_value)` pair belong to the same component. The component ID is the lexicographically smallest member ID. Witness edges are canonical: each edge has lexicographically ordered endpoint IDs, and each component's edges are sorted by `(key_name, key_value, left_id, right_id)`.

## Planning

```moonbit
pub fn plan_split(
  records : Array[Record],
  spec : SplitSpec,
) -> Result[SplitPlan, Array[Issue]]
```

The algorithm is `group-greedy-v1`. Components are ordered by size and a seeded deterministic hash. `seed` must be a non-negative integer. A component is never split. Optional label balancing uses an integer squared-error objective. `ratio_tolerance_bp` is evaluated with exact cross-multiplication and emits deterministic non-fatal warnings when the strict threshold is exceeded.

`SplitPlan::summaries()` returns declared partitions in specification order with record counts and target, actual, and absolute deviation basis points. Each summary also exposes stable `label_counts()` and `unlabeled_count()` values.

`summary_json(plan)` serializes component size, largest-component, partition-ratio, and label diagnostics with a fixed schema. `ratio_tolerance_bp` produces non-fatal warnings using exact cross-multiplication when the strict threshold is exceeded.

## Auditing

```moonbit
pub fn audit_split(
  records : Array[Record],
  spec : SplitSpec,
  assignments : Array[Assignment],
) -> Result[AuditReport, Array[Issue]]
```

The auditor recomputes grouping from raw records. It detects unknown records, duplicate assignments, missing assignments, invalid partitions, empty partitions, and cross-partition isolation conflicts.

`audit_report_json(report, spec, record_count, assignment_count)` emits a stable machine-readable report. The CLI selects it with `audit --report json`; `--report text` retains the human-readable form.

## K-fold members

```moonbit
pub fn fold_members(
  plan : SplitPlan,
  fold_name : String,
  side : FoldSide,
) -> Result[Array[String], Array[Issue]]
```

`FoldSide` is either `Validation` or `Train`. This function accepts only K-fold plans. For a valid fold name, `Validation` returns the record IDs assigned to that fold; `Train` returns the complement. Returned IDs are sorted lexicographically.

`folds_jsonl(plan)` exports one `id`/`validation_fold` line per record for K-fold plans, sorted by ID and without a trailing newline. Calling it for a holdout plan returns `not_kfold_plan`.
