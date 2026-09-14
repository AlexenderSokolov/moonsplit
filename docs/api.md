# API

## Installation and package paths

Add the released module with:

```bash
moon add AlexenderSokolov/moonsplit@0.3.0
```

MoonSplit exposes its APIs through focused subpackages, rather than the empty module-root package. Import the package that owns the API in your consumer's `moon.pkg`:

```moonbit
import {
  "AlexenderSokolov/moonsplit/src/record" @record,
  "AlexenderSokolov/moonsplit/src/spec" @spec,
  "AlexenderSokolov/moonsplit/src/plan" @plan,
  "AlexenderSokolov/moonsplit/src/audit" @audit,
  "AlexenderSokolov/moonsplit/src/temporal" @temporal,
}
```

For example, `@record.Interval::new(100L, 200L).end()` returns `200L`. The public release and clean-install verification are recorded in [acceptance.md](acceptance.md).

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

## Schema v2 records and rules

```moonbit
pub fn parse_v2_records(
  input : String,
  format : InputFormat,
) -> Result[Array[V2Record], Array[Issue]]

pub fn parse_v2_spec(input : String) -> Result[V2Spec, Array[Issue]]

pub fn build_rule_components(
  records : Array[V2Record],
  rules : Array[LeakageRule],
) -> Result[RuleComponents, Array[Issue]]
```

`V2Record` preserves the v1 fields and adds optional `text` plus a named `intervals` map of `Interval { start : Int64, end : Int64 }`. Parsed interval endpoints must be safe JSON integers and satisfy `start < end`; snapshots preserve both new fields. `V2Spec` is parser-created, and rule-component, planning, and audit entrypoints also recheck every supplied record interval, so a manually constructed `V2Record` cannot bypass the CLI-level interval invariant.

V2 accepts exactly three rule types:

- `exact_key`: same named key and value.
- `text_jaccard`: normalized Unicode character q-gram set Jaccard similarity. Defaults are `q = 3` and `threshold_bp = 8000`; equality matches. It uses complete prefix-filter candidates followed by exact integer cross-multiplication.
- `interval_overlap`: same declared source key and overlapping half-open named interval. The scan retains the maximum-end witness needed for connectivity; touching endpoints do not overlap.

Rules are canonicalized by ID before grouping. `RuleComponents` exposes sorted components, its deterministic witness forest, `text_candidate_count()`, and `text_comparison_count()`. The forest explains connectivity only; it is not the complete set of matching pairs. The two portable `Int` evidence counters reject `text_count_overflow` before they could exceed `2147483647`; dense candidate joins remain resource-bound and are not silently truncated.

## Schema v2 grouped planning and audit

```moonbit
pub fn plan_split_with_rules(
  records : Array[V2Record],
  spec : V2Spec,
) -> Result[RuleSplitPlan, Array[Issue]]

pub fn audit_split_with_rules(
  records : Array[V2Record],
  spec : V2Spec,
  assignments : Array[Assignment],
) -> Result[RuleAuditReport, Array[Issue]]
```

These functions accept only v2 `holdout` or `kfold`. Greedy initialization is followed by at most ten deterministic component-move rounds. The objective uses arbitrary-precision integer arithmetic for size and optional label squared error. A move must strictly lower the objective, cannot split a component, and cannot empty its source partition. `RuleSplitPlan` exposes the initial and final decimal objectives plus move rounds. The implementation guarantees a result no worse than greedy initialization; it does not claim a global optimum.

The audit reconstructs components from raw records and rules, then checks the supplied manifest for missing, duplicate, unknown, empty-partition, and cross-component assignments. It does not trust a plan or summary file. `RuleSplitPlan` and `RuleAuditReport` are produced by those entrypoints; their serializers are presentation helpers, not a way to establish audit validity.

## Time-forward planning and audit

```moonbit
pub fn plan_temporal(
  records : Array[V2Record],
  spec : V2Spec,
) -> Result[TemporalPlan, Array[Issue]]

pub fn audit_temporal(
  records : Array[V2Record],
  spec : V2Spec,
  roles : Array[TemporalRole],
) -> Result[TemporalAuditReport, Array[Issue]]

pub fn parse_temporal_roles(
  input : String,
) -> Result[Array[TemporalRole], Array[Issue]]
```

These functions require `kind: "time_forward"` and an explicit `TimeConfig` containing interval name, unit, epoch, non-negative gap, and sorted non-overlapping validation windows. Each role contains `fold_id`, `id`, `role` (`train`, `validation`, or `excluded`), and a reason. For every fold and record, exactly one role is required. Excluded rows are outside the active train/validation partition, and a rule component may never have both active roles in one fold. `TemporalRole::new` remains available to build a submitted role manifest, while `TemporalPlan` and `TemporalAuditReport` are produced by the validated entrypoints. The auditor recomputes the prescribed role for every raw record before validating the supplied `roles.jsonl` manifest.

Schema v1 `Record`, `SplitSpec`, `plan_split`, `audit_split`, and `fold_members` remain supported with their original contracts.
