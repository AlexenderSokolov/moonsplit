#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
moon check
moon test
moon test --target js

moon info
moon fmt --check

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

stamp="$(date +%Y%m%d_%H%M%S)"
root="artifacts/check_${stamp}"
mkdir -p "$root"
wasm_out="$root/wasm_plan"
js_out="$root/js_plan"
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

run_expected wasm-gc 0 "wasm-gc plan" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$wasm_out" --format jsonl
run_expected js 0 "JS plan" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$js_out" --format jsonl

for name in plan.json assignments.jsonl components.jsonl report.md; do
  cmp "$wasm_out/$name" "$js_out/$name"
done

run_expected wasm-gc 0 "Chinese path with a space" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$chinese_out" --format jsonl
run_expected wasm-gc 0 "independent audit" audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments "$wasm_out/assignments.jsonl"
run_expected wasm-gc 3 "audit failure" audit --data examples/voice_records.jsonl --spec examples/holdout_spec.json --assignments examples/bad_assignments.jsonl
run_expected wasm-gc 2 "missing spec file" plan --data examples/voice_records.jsonl --spec examples/missing_spec.json --out "$root/never_created"
run_expected wasm-gc 4 "existing output path" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$wasm_out"
run_expected wasm-gc 4 "missing output parent" plan --data examples/voice_records.jsonl --spec examples/holdout_spec.json --out "$missing_out"

echo "check=ok artifacts=$root"
