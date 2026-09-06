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

The algorithm is `group-greedy-v1`. Components are ordered by size and a seeded deterministic hash. `seed` must be a non-negative integer. A component is never split. Optional label balancing uses an integer squared-error objective. `ratio_tolerance_bp` is retained as metadata in v0.1.0 and is not enforced as a warning or hard error.

## Auditing

```moonbit
pub fn audit_split(
  records : Array[Record],
  spec : SplitSpec,
  assignments : Array[Assignment],
) -> Result[AuditReport, Array[Issue]]
```

The auditor recomputes grouping from raw records. It detects unknown records, duplicate assignments, missing assignments, invalid partitions, empty partitions, and cross-partition isolation conflicts.

## K-fold members

```moonbit
pub fn fold_members(
  plan : SplitPlan,
  fold_name : String,
  side : FoldSide,
) -> Result[Array[String], Array[Issue]]
```

`FoldSide` is either `Validation` or `Train`. This function accepts only K-fold plans. For a valid fold name, `Validation` returns the record IDs assigned to that fold; `Train` returns the complement. Returned IDs are sorted lexicographically.
