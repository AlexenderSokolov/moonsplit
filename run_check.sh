#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon test --target js --deny-warn

moon info

version="$(moon run cmd/moonsplit -- --version)"
if [ "$version" != "MoonSplit 0.1.1" ]; then
  echo "--version printed '$version', expected 'MoonSplit 0.1.1'" >&2
  exit 1
fi

version="$(moon run cmd/moonsplit -- version)"
if [ "$version" != "MoonSplit 0.1.1" ]; then
  echo "version printed '$version', expected 'MoonSplit 0.1.1'" >&2
  exit 1
fi

stamp="$(date +%Y%m%d_%H%M%S_%N)"
root="artifacts/check_${stamp}"
mkdir -p "$root"
wasm_out="$root/wasm_plan"
js_out="$root/js_plan"
kfold_wasm_out="$root/wasm_kfold"
kfold_js_out="$root/js_kfold"
multikey_out="$root/multikey_plan"
label_out="$root/label_plan"
chinese_out="$root/中文 路径"
missing_out="$root/missing_parent/plan"

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

echo "check=ok artifacts=$root"
