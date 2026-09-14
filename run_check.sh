#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
moon_bin="${MOON_BIN:-moon}"
moon() { command "$moon_bin" "$@"; }
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon test --target js --deny-warn

moon info

version="$(moon run cmd/moonsplit -- --version)"
if [ "$version" != "MoonSplit 0.3.0" ]; then
  echo "--version printed '$version', expected 'MoonSplit 0.3.0'" >&2
  exit 1
fi

version="$(moon run cmd/moonsplit -- version)"
if [ "$version" != "MoonSplit 0.3.0" ]; then
  echo "version printed '$version', expected 'MoonSplit 0.3.0'" >&2
  exit 1
fi

stamp="$(date +%Y%m%d_%H%M%S_%N)"
root="artifacts/check_${stamp}"
if [ -e "$root" ]; then
  echo "refusing to reuse output path: $root" >&2
  exit 1
fi
mkdir -p "$root"
wasm_out="$root/wasm_plan"
js_out="$root/js_plan"
kfold_wasm_out="$root/wasm_kfold"
kfold_js_out="$root/js_kfold"
multikey_out="$root/multikey_plan"
label_out="$root/label_plan"
chinese_out="$root/中文 路径"
missing_out="$root/missing_parent/plan"
v2_wasm_out="$root/v2_wasm_plan"
v2_js_out="$root/v2_js_plan"
v2_repeat_out="$root/v2_repeat_plan"
v2_reordered_out="$root/v2_reordered_plan"
v2_kfold_out="$root/v2_kfold_plan"
v2_kfold_js_out="$root/v2_kfold_js_plan"
v2_kfold_normalized_spec="$root/v2_kfold_normalized_spec.json"
time_wasm_out="$root/time_wasm_plan"
time_js_out="$root/time_js_plan"
time_multi_wasm_out="$root/time_multi_wasm_plan"
time_multi_js_out="$root/time_multi_js_plan"
time_zero_gap_wasm_out="$root/time_zero_gap_wasm_plan"
time_zero_gap_js_out="$root/time_zero_gap_js_plan"
time_multi_wasm_repeat_out="$root/time_multi_wasm_repeat_plan"
time_multi_js_repeat_out="$root/time_multi_js_repeat_plan"
time_multi_wasm_reversed_out="$root/time_multi_wasm_reversed_plan"
time_multi_js_reversed_out="$root/time_multi_js_reversed_plan"
time_multi_wasm_reordered_out="$root/time_multi_wasm_reordered_plan"
time_multi_js_reordered_out="$root/time_multi_js_reordered_plan"

run_expected() {
  target="$1"
  expected="$2"
  label="$3"
  shift 3
  echo "check: $label"
  set +e
  moon run --target "$target" cmd/moonsplit -- "$@"
  actual="$?"
  set -e
  if [ "$actual" -ne "$expected" ]; then
    echo "$label exited with $actual, expected $expected" >&2
    exit 1
  fi
}

capture_expected() {
  target="$1"
  expected="$2"
  label="$3"
  shift 3
  echo "check: $label" >&2
  set +e
  output="$(moon run --target "$target" cmd/moonsplit -- "$@" 2>&1)"
  actual="$?"
  set -e
  if [ "$actual" -ne "$expected" ]; then
    echo "$label exited with $actual, expected $expected" >&2
    echo "$output" >&2
    exit 1
  fi
  printf '%s' "$output"
}

assert_contains() {
  text="$1"
  needle="$2"
  label="$3"
  case "$text" in
    *"$needle"*) ;;
    *) echo "$label did not contain '$needle'" >&2; exit 1 ;;
  esac
}

normalized_wasm="$(capture_expected wasm-gc 0 "wasm-gc normalize-spec" normalize-spec --spec examples/holdout_spec.json)"
normalized_js="$(capture_expected js 0 "JS normalize-spec" normalize-spec --spec examples/holdout_spec.json)"
expected_normalized="$(cat <<'EOF'
{
  "schema_version": 1,
  "kind": "holdout",
  "isolation_keys": ["speaker_id"],
  "seed": 42,
  "balance_labels": false,
  "ratio_tolerance_bp": 500,
  "partitions": [
    {"name": "train", "weight": 8},
    {"name": "validation", "weight": 1},
    {"name": "test", "weight": 1}
  ]
}
EOF
)"
if [ "$normalized_wasm" != "$expected_normalized" ] || [ "$normalized_js" != "$expected_normalized" ]; then
  echo "normalize-spec output does not match the canonical fixture" >&2
  exit 1
fi

wasm_plan_log="$(capture_expected wasm-gc 0 "wasm-gc plan" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$wasm_out" --format jsonl)"
assert_contains "$wasm_plan_log" "plan=ok" "wasm-gc plan"
assert_contains "$wasm_plan_log" "files=5" "wasm-gc plan"
js_plan_log="$(capture_expected js 0 "JS plan" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$js_out" --format jsonl)"
assert_contains "$js_plan_log" "files=5" "JS plan"

for name in plan.json assignments.jsonl components.jsonl report.md summary.json; do
  cmp "$wasm_out/$name" "$js_out/$name"
done
grep -Fq '"schema_version": 1' "$wasm_out/summary.json"
grep -Fq '"algorithm": "group-greedy-v1"' "$wasm_out/summary.json"
grep -Fq '"components": 4' "$wasm_out/summary.json"
grep -Fq '"partitions": [' "$wasm_out/summary.json"
grep -Fq '## Labels' "$wasm_out/report.md"
grep -Fq 'Target (bp)' "$wasm_out/report.md"

kfold_wasm_log="$(capture_expected wasm-gc 0 "wasm-gc kfold plan" plan --data examples/kfold_records.jsonl --spec examples/kfold_spec.json --out "$kfold_wasm_out" --format jsonl)"
assert_contains "$kfold_wasm_log" "files=6" "wasm-gc kfold plan"
kfold_js_log="$(capture_expected js 0 "JS kfold plan" plan --data examples/kfold_records.jsonl --spec examples/kfold_spec.json --out "$kfold_js_out" --format jsonl)"
assert_contains "$kfold_js_log" "files=6" "JS kfold plan"
for name in plan.json assignments.jsonl components.jsonl report.md summary.json folds.jsonl; do
  cmp "$kfold_wasm_out/$name" "$kfold_js_out/$name"
done
if [ -e "$wasm_out/folds.jsonl" ]; then
  echo "holdout output unexpectedly contains folds.jsonl" >&2
  exit 1
fi
if [ -z "$(tail -c 1 "$kfold_wasm_out/folds.jsonl")" ]; then
  echo "folds.jsonl has a trailing newline" >&2
  exit 1
fi
if [ "$(grep -c '^' "$kfold_wasm_out/folds.jsonl")" -ne 5 ]; then
  echo "folds.jsonl does not contain one line per record" >&2
  exit 1
fi
fold_ids="$(sed -n 's/.*"id": "\([^"]*\)".*/\1/p' "$kfold_wasm_out/folds.jsonl" | sort | uniq | wc -l)"
if [ "$fold_ids" -ne 5 ]; then
  echo "folds.jsonl repeats a record id" >&2
  exit 1
fi

multikey_log="$(capture_expected wasm-gc 0 "multi-key transitive-closure plan" plan --data examples/multikey_records.jsonl --spec examples/multikey_spec.json --out "$multikey_out" --format jsonl)"
assert_contains "$multikey_log" "files=5" "multi-key transitive-closure plan"
grep -Fq '"components": 2' "$multikey_out/summary.json"
grep -Fq '"size": 3' "$multikey_out/summary.json"
grep -Fq '"member_ids": ["chain_a", "chain_b", "chain_c"]' "$multikey_out/components.jsonl"

capture_expected wasm-gc 0 "label-aware summary plan" plan --data examples/label_records.jsonl --spec examples/label_spec.json --out "$label_out" --format jsonl >/dev/null
grep -Fq '"label_counts"' "$label_out/summary.json"
grep -Fq '"unlabeled_count": 1' "$label_out/summary.json"
grep -Fq '"": 1' "$label_out/summary.json"
grep -Fq '"a": 1' "$label_out/summary.json"
grep -Fq '"z": 1' "$label_out/summary.json"

run_expected wasm-gc 0 "Chinese path with a space" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$chinese_out" --format jsonl
audit_text="$(capture_expected wasm-gc 0 "independent audit" audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments "$wasm_out/assignments.jsonl")"
assert_contains "$audit_text" "audit=pass" "independent audit"
audit_valid="$(capture_expected wasm-gc 0 "audit JSON success" audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments "$wasm_out/assignments.jsonl" --report json)"
assert_contains "$audit_valid" '"valid": true' "audit JSON success"
assert_contains "$audit_valid" '"records": 4' "audit JSON success"
assert_contains "$audit_valid" '"assignments": 4' "audit JSON success"
audit_invalid="$(capture_expected wasm-gc 3 "audit JSON semantic failure" audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments examples/bad_assignments.jsonl --report json)"
assert_contains "$audit_invalid" '"valid": false' "audit JSON semantic failure"
assert_contains "$audit_invalid" '"issues": [' "audit JSON semantic failure"
run_expected wasm-gc 3 "audit failure" audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments examples/bad_assignments.jsonl
run_expected wasm-gc 2 "assignment input failure" audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments examples/invalid_empty_assignments.jsonl
validate_args=(validate --data examples/voice_records.jsonl --spec examples/holdout_spec.json --format jsonl)
validate_wasm="$(capture_expected wasm-gc 0 "wasm-gc validation preflight" "${validate_args[@]}")"
validate_js="$(capture_expected js 0 "JS validation preflight" "${validate_args[@]}")"
if [ "$validate_wasm" != "$validate_js" ]; then
  echo "validate output differs between wasm-gc and JS" >&2
  exit 1
fi
assert_contains "$validate_wasm" "validate=ok" "validate output"
assert_contains "$validate_wasm" "records=4" "validate output"
assert_contains "$validate_wasm" "warnings=3" "validate output"
if [ -e "$root/validate_should_not_exist" ]; then
  echo "validate created an output path" >&2
  exit 1
fi
run_expected wasm-gc 2 "validate input failure" validate --data examples/voice_records.jsonl --spec examples/missing_spec.json
run_expected wasm-gc 2 "missing spec file" plan --data examples/voice_records.jsonl --spec examples/missing_spec.json --out "$root/never_created"
run_expected wasm-gc 4 "existing output path" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$wasm_out"
run_expected wasm-gc 4 "missing output parent" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$missing_out"

v2_normalized_wasm="$(capture_expected wasm-gc 0 "wasm-gc v2 normalize-spec" normalize-spec --spec examples/v2_rule_spec.json)"
v2_normalized_js="$(capture_expected js 0 "JS v2 normalize-spec" normalize-spec --spec examples/v2_rule_spec.json)"
if [ "$v2_normalized_wasm" != "$v2_normalized_js" ]; then
  echo "v2 normalize-spec differs between wasm-gc and JS" >&2
  exit 1
fi
assert_contains "$v2_normalized_wasm" '"schema_version": 2' "v2 normalize-spec"
assert_contains "$v2_normalized_wasm" '"type": "text_jaccard"' "v2 normalize-spec"
assert_contains "$v2_normalized_wasm" '"partitions":' "v2 holdout normalize-spec"
assert_contains "$v2_normalized_wasm" '"name": "train", "weight": 1' "v2 holdout normalize-spec"
if printf '%s' "$v2_normalized_wasm" | grep -Fq '"k"'; then
  echo "v2 holdout normalize-spec unexpectedly contains k" >&2
  exit 1
fi

v2_kfold_normalized_wasm="$(capture_expected wasm-gc 0 "wasm-gc v2 kfold normalize-spec" normalize-spec --spec examples/v2_kfold_spec.json)"
v2_kfold_normalized_js="$(capture_expected js 0 "JS v2 kfold normalize-spec" normalize-spec --spec examples/v2_kfold_spec.json)"
if [ "$v2_kfold_normalized_wasm" != "$v2_kfold_normalized_js" ]; then
  echo "v2 kfold normalize-spec differs between wasm-gc and JS" >&2
  exit 1
fi
assert_contains "$v2_kfold_normalized_wasm" '"kind": "kfold"' "v2 kfold normalize-spec"
assert_contains "$v2_kfold_normalized_wasm" '"k": 2' "v2 kfold normalize-spec"
if printf '%s' "$v2_kfold_normalized_wasm" | grep -Fq '"partitions"'; then
  echo "v2 kfold normalize-spec unexpectedly contains generated partitions" >&2
  exit 1
fi
printf '%s\n' "$v2_kfold_normalized_wasm" > "$v2_kfold_normalized_spec"
v2_kfold_roundtrip_wasm="$(capture_expected wasm-gc 0 "wasm-gc v2 kfold normalize-spec round trip" normalize-spec --spec "$v2_kfold_normalized_spec")"
v2_kfold_roundtrip_js="$(capture_expected js 0 "JS v2 kfold normalize-spec round trip" normalize-spec --spec "$v2_kfold_normalized_spec")"
if [ "$v2_kfold_roundtrip_wasm" != "$v2_kfold_normalized_wasm" ] || [ "$v2_kfold_roundtrip_js" != "$v2_kfold_normalized_wasm" ]; then
  echo "v2 kfold normalize-spec does not round trip canonically" >&2
  exit 1
fi

v2_validate_wasm="$(capture_expected wasm-gc 0 "wasm-gc v2 validation preflight" validate --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --format jsonl)"
v2_validate_js="$(capture_expected js 0 "JS v2 validation preflight" validate --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --format jsonl)"
if [ "$v2_validate_wasm" != "$v2_validate_js" ]; then
  echo "v2 validate output differs between wasm-gc and JS" >&2
  exit 1
fi
assert_contains "$v2_validate_wasm" "schema_version=2" "v2 validation preflight"
if [ -e "$root/v2_validate_should_not_exist" ]; then
  echo "v2 validate created an output path" >&2
  exit 1
fi

v2_wasm_log="$(capture_expected wasm-gc 0 "wasm-gc v2 plan" plan --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --out "$v2_wasm_out" --format jsonl)"
assert_contains "$v2_wasm_log" "files=7" "wasm-gc v2 plan"
v2_js_log="$(capture_expected js 0 "JS v2 plan" plan --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --out "$v2_js_out" --format jsonl)"
assert_contains "$v2_js_log" "files=7" "JS v2 plan"
for name in plan.json assignments.jsonl components.jsonl report.md summary.json evidence.jsonl audit.json; do
  cmp "$v2_wasm_out/$name" "$v2_js_out/$name"
done
grep -Fq '"components": 4' "$v2_wasm_out/summary.json"
grep -Fq '"text_candidate_count"' "$v2_wasm_out/summary.json"
grep -Fq 'explanatory forest' "$v2_wasm_out/report.md"

capture_expected wasm-gc 0 "v2 repeated deterministic plan" plan --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --out "$v2_repeat_out" --format jsonl >/dev/null
for name in plan.json assignments.jsonl components.jsonl report.md summary.json evidence.jsonl audit.json; do
  cmp "$v2_wasm_out/$name" "$v2_repeat_out/$name"
done

tac examples/v2_rule_records.jsonl > "$root/v2_rule_records_reversed.jsonl"
capture_expected wasm-gc 0 "v2 reordered deterministic plan" plan --data "$root/v2_rule_records_reversed.jsonl" --spec examples/v2_rule_spec_reordered.json --out "$v2_reordered_out" --format jsonl >/dev/null
for name in plan.json assignments.jsonl components.jsonl report.md summary.json evidence.jsonl audit.json; do
  cmp "$v2_wasm_out/$name" "$v2_reordered_out/$name"
done

v2_kfold_log="$(capture_expected wasm-gc 0 "v2 kfold plan" plan --data examples/v2_rule_records.jsonl --spec examples/v2_kfold_spec.json --out "$v2_kfold_out" --format jsonl)"
assert_contains "$v2_kfold_log" "files=8" "v2 kfold plan"
v2_kfold_js_log="$(capture_expected js 0 "JS v2 kfold plan" plan --data examples/v2_rule_records.jsonl --spec examples/v2_kfold_spec.json --out "$v2_kfold_js_out" --format jsonl)"
assert_contains "$v2_kfold_js_log" "files=8" "JS v2 kfold plan"
for name in plan.json assignments.jsonl components.jsonl report.md summary.json evidence.jsonl audit.json folds.jsonl; do
  test -f "$v2_kfold_out/$name"
  cmp "$v2_kfold_out/$name" "$v2_kfold_js_out/$name"
done

v2_audit_valid="$(capture_expected wasm-gc 0 "v2 independent audit" audit --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --assignments "$v2_wasm_out/assignments.jsonl" --format jsonl --report json)"
assert_contains "$v2_audit_valid" '"valid": true' "v2 independent audit"
v2_text_audit="$(capture_expected wasm-gc 3 "v2 text-only audit failure" audit --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --assignments examples/v2_text_only_bad_assignments.jsonl --format jsonl --report json)"
assert_contains "$v2_text_audit" '"cross_partition_rule"' "v2 text-only audit failure"
assert_contains "$v2_text_audit" 'rule component text_a' "v2 text-only audit failure"
v2_interval_audit="$(capture_expected wasm-gc 3 "v2 interval-only audit failure" audit --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --assignments examples/v2_interval_only_bad_assignments.jsonl --format jsonl --report json)"
assert_contains "$v2_interval_audit" '"cross_partition_rule"' "v2 interval-only audit failure"
assert_contains "$v2_interval_audit" 'rule component interval_a' "v2 interval-only audit failure"

time_files=(plan.json roles.jsonl exclusions.jsonl components.jsonl witnesses.jsonl summary.json report.md audit.json)
time_normalized_wasm="$(capture_expected wasm-gc 0 "wasm-gc time-forward normalize-spec" normalize-spec --spec examples/time_multi_spec.json)"
time_normalized_js="$(capture_expected js 0 "JS time-forward normalize-spec" normalize-spec --spec examples/time_multi_spec.json)"
if [ "$time_normalized_wasm" != "$time_normalized_js" ]; then
  echo "time-forward normalize-spec differs between wasm-gc and JS" >&2
  exit 1
fi
assert_contains "$time_normalized_wasm" '"kind": "time_forward"' "time-forward normalize-spec"
assert_contains "$time_normalized_wasm" '"id": "fold_1"' "time-forward normalize-spec"

time_validate_wasm="$(capture_expected wasm-gc 0 "wasm-gc time-forward validation preflight" validate --data examples/time_multi_records.jsonl --spec examples/time_multi_spec.json --format jsonl)"
time_validate_js="$(capture_expected js 0 "JS time-forward validation preflight" validate --data examples/time_multi_records.jsonl --spec examples/time_multi_spec.json --format jsonl)"
if [ "$time_validate_wasm" != "$time_validate_js" ]; then
  echo "time-forward validate output differs between wasm-gc and JS" >&2
  exit 1
fi
assert_contains "$time_validate_wasm" "roles=18" "time-forward validation preflight"
if [ -e "$root/time_validate_should_not_exist" ]; then
  echo "time-forward validate created an output path" >&2
  exit 1
fi

time_wasm_log="$(capture_expected wasm-gc 0 "wasm-gc time-forward plan" plan --data examples/time_records.jsonl --spec examples/time_forward_spec.json --out "$time_wasm_out" --format jsonl)"
assert_contains "$time_wasm_log" "files=8" "wasm-gc time-forward plan"
time_js_log="$(capture_expected js 0 "JS time-forward plan" plan --data examples/time_records.jsonl --spec examples/time_forward_spec.json --out "$time_js_out" --format jsonl)"
assert_contains "$time_js_log" "files=8" "JS time-forward plan"
for name in "${time_files[@]}"; do
  cmp "$time_wasm_out/$name" "$time_js_out/$name"
done
grep -Fq '"reason": "component_conflict"' "$time_wasm_out/roles.jsonl"
grep -Fq '"reason": "historical"' "$time_wasm_out/roles.jsonl"
grep -Fq '"reason": "gap"' "$time_wasm_out/roles.jsonl"
grep -Fq '"reason": "boundary_overlap"' "$time_wasm_out/roles.jsonl"
grep -Fq '"reason": "future"' "$time_wasm_out/roles.jsonl"
time_audit_valid="$(capture_expected wasm-gc 0 "time-forward independent audit" audit --data examples/time_records.jsonl --spec examples/time_forward_spec.json --roles "$time_wasm_out/roles.jsonl" --format jsonl --report json)"
assert_contains "$time_audit_valid" '"valid": true' "time-forward independent audit"
time_audit_invalid="$(capture_expected wasm-gc 3 "time-forward conflict audit failure" audit --data examples/time_records.jsonl --spec examples/time_forward_spec.json --roles examples/time_bad_roles.jsonl --format jsonl --report json)"
assert_contains "$time_audit_invalid" '"temporal_component_leak"' "time-forward conflict audit failure"
run_expected wasm-gc 2 "time-forward rejects assignments manifest" audit --data examples/time_records.jsonl --spec examples/time_forward_spec.json --assignments examples/v2_bad_assignments.jsonl --format jsonl

time_multi_wasm_log="$(capture_expected wasm-gc 0 "wasm-gc multi-window time-forward plan" plan --data examples/time_multi_records.jsonl --spec examples/time_multi_spec.json --out "$time_multi_wasm_out" --format jsonl)"
assert_contains "$time_multi_wasm_log" "files=8" "wasm-gc multi-window time-forward plan"
time_multi_js_log="$(capture_expected js 0 "JS multi-window time-forward plan" plan --data examples/time_multi_records.jsonl --spec examples/time_multi_spec.json --out "$time_multi_js_out" --format jsonl)"
assert_contains "$time_multi_js_log" "files=8" "JS multi-window time-forward plan"
for name in "${time_files[@]}"; do
  cmp "$time_multi_wasm_out/$name" "$time_multi_js_out/$name"
done
if [ "$(grep -c '^' "$time_multi_wasm_out/roles.jsonl")" -ne 18 ]; then
  echo "multi-window roles.jsonl does not contain one role per record and fold" >&2
  exit 1
fi
for expected_role in \
  '{"fold_id": "fold_0", "id": "cutoff", "role": "train", "reason": "historical"}' \
  '{"fold_id": "fold_0", "id": "duplicate_history", "role": "excluded", "reason": "component_conflict"}' \
  '{"fold_id": "fold_0", "id": "touch_0", "role": "excluded", "reason": "gap"}' \
  '{"fold_id": "fold_0", "id": "boundary_0", "role": "excluded", "reason": "boundary_overlap"}' \
  '{"fold_id": "fold_0", "id": "future", "role": "excluded", "reason": "future"}' \
  '{"fold_id": "fold_1", "id": "between", "role": "train", "reason": "historical"}' \
  '{"fold_id": "fold_1", "id": "gap_1", "role": "excluded", "reason": "gap"}' \
  '{"fold_id": "fold_1", "id": "validation_1", "role": "validation", "reason": "validation_window"}'; do
  grep -Fqx "$expected_role" "$time_multi_wasm_out/roles.jsonl"
done
time_multi_audit="$(capture_expected wasm-gc 0 "multi-window time-forward independent audit" audit --data examples/time_multi_records.jsonl --spec examples/time_multi_spec.json --roles "$time_multi_wasm_out/roles.jsonl" --format jsonl --report json)"
assert_contains "$time_multi_audit" '"valid": true' "multi-window time-forward independent audit"

time_zero_gap_wasm_log="$(capture_expected wasm-gc 0 "wasm-gc zero-gap time-forward plan" plan --data examples/time_multi_records.jsonl --spec examples/time_zero_gap_spec.json --out "$time_zero_gap_wasm_out" --format jsonl)"
time_zero_gap_js_log="$(capture_expected js 0 "JS zero-gap time-forward plan" plan --data examples/time_multi_records.jsonl --spec examples/time_zero_gap_spec.json --out "$time_zero_gap_js_out" --format jsonl)"
for name in "${time_files[@]}"; do
  cmp "$time_zero_gap_wasm_out/$name" "$time_zero_gap_js_out/$name"
done
grep -Fqx '{"fold_id": "fold_0", "id": "touch_0", "role": "train", "reason": "historical"}' "$time_zero_gap_wasm_out/roles.jsonl"

capture_expected wasm-gc 0 "wasm-gc repeated multi-window time-forward plan" plan --data examples/time_multi_records.jsonl --spec examples/time_multi_spec.json --out "$time_multi_wasm_repeat_out" --format jsonl >/dev/null
capture_expected js 0 "JS repeated multi-window time-forward plan" plan --data examples/time_multi_records.jsonl --spec examples/time_multi_spec.json --out "$time_multi_js_repeat_out" --format jsonl >/dev/null
for name in "${time_files[@]}"; do
  cmp "$time_multi_wasm_out/$name" "$time_multi_wasm_repeat_out/$name"
  cmp "$time_multi_wasm_out/$name" "$time_multi_js_repeat_out/$name"
done

tac examples/time_multi_records.jsonl > "$root/time_multi_records_reversed.jsonl"
capture_expected wasm-gc 0 "wasm-gc reversed multi-window time-forward plan" plan --data "$root/time_multi_records_reversed.jsonl" --spec examples/time_multi_spec.json --out "$time_multi_wasm_reversed_out" --format jsonl >/dev/null
capture_expected js 0 "JS reversed multi-window time-forward plan" plan --data "$root/time_multi_records_reversed.jsonl" --spec examples/time_multi_spec.json --out "$time_multi_js_reversed_out" --format jsonl >/dev/null
for name in "${time_files[@]}"; do
  cmp "$time_multi_wasm_out/$name" "$time_multi_wasm_reversed_out/$name"
  cmp "$time_multi_wasm_out/$name" "$time_multi_js_reversed_out/$name"
done

capture_expected wasm-gc 0 "wasm-gc reordered-rule multi-window time-forward plan" plan --data examples/time_multi_records.jsonl --spec examples/time_multi_spec_reordered.json --out "$time_multi_wasm_reordered_out" --format jsonl >/dev/null
capture_expected js 0 "JS reordered-rule multi-window time-forward plan" plan --data examples/time_multi_records.jsonl --spec examples/time_multi_spec_reordered.json --out "$time_multi_js_reordered_out" --format jsonl >/dev/null
for name in "${time_files[@]}"; do
  cmp "$time_multi_wasm_out/$name" "$time_multi_wasm_reordered_out/$name"
  cmp "$time_multi_wasm_out/$name" "$time_multi_js_reordered_out/$name"
done

echo "check=ok artifacts=$root"
