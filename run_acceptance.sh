#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
moon_bin="${MOON_BIN:-moon}"
moon() { command "$moon_bin" "$@"; }

if [ -n "${PYTHON_BIN:-}" ]; then
  python_bin="$PYTHON_BIN"
elif command -v python3 >/dev/null 2>&1; then
  python_bin="python3"
elif command -v python >/dev/null 2>&1; then
  python_bin="python"
else
  echo "run_acceptance.sh requires Python 3; set PYTHON_BIN to its executable" >&2
  exit 2
fi

stamp="$(date +%Y%m%d_%H%M%S_%N)"
root="artifacts/acceptance_${stamp}_$$"
if [ -e "$root" ]; then
  echo "refusing to reuse output path: $root" >&2
  exit 1
fi
mkdir -p "$root"
generated_at_local="$(date '+%Y-%m-%dT%H:%M:%S%z')"

MOON_BIN="$moon_bin" ./run_check.sh | tee "$root/run_check.log"

run_bench() {
  mode="$1"
  records="$2"
  log="$root/bench_${mode}_${records}.log"
  started="$(date +%s%3N)"
  moon run cmd/moonsplit -- bench --mode "$mode" --records "$records" | tee "$log"
  finished="$(date +%s%3N)"
  elapsed=$((finished - started))
  printf '%s\t%s\t%s\t%s\n' "$mode" "$records" "$elapsed" "$(basename "$log")" >> "$root/benchmarks.tsv"
}

optimizer_out="$root/optimizer_plan"
moon run cmd/moonsplit -- plan --data examples/optimizer_case.json --spec examples/optimizer_case_spec.json --out "$optimizer_out" --format json | tee "$root/optimizer_plan.log"
"$python_bin" tools/exhaustive_optimizer_reference.py --plan "$optimizer_out/plan.json" --out "$root/optimizer_reference.json"

v2_grouped_out="$root/v2_grouped_plan"
moon run cmd/moonsplit -- plan --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --out "$v2_grouped_out" --format jsonl | tee "$root/v2_grouped_plan.log"
moon run cmd/moonsplit -- audit --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --assignments "$v2_grouped_out/assignments.jsonl" --format jsonl --report json > "$root/v2_grouped_audit_recheck.json"

time_forward_out="$root/time_forward_plan"
moon run cmd/moonsplit -- plan --data examples/time_records.jsonl --spec examples/time_forward_spec.json --out "$time_forward_out" --format jsonl | tee "$root/time_forward_plan.log"
moon run cmd/moonsplit -- audit --data examples/time_records.jsonl --spec examples/time_forward_spec.json --roles "$time_forward_out/roles.jsonl" --format jsonl --report json > "$root/time_forward_audit_recheck.json"

{
  printf '# MoonSplit v0.3.0 acceptance commands; executed from %s\n' "$PWD"
  printf './run_acceptance.sh\n'
  printf 'MOON_BIN=%q ./run_check.sh\n' "$moon_bin"
  printf '%q run cmd/moonsplit -- plan --data examples/optimizer_case.json --spec examples/optimizer_case_spec.json --out %q --format json\n' "$moon_bin" "$optimizer_out"
  printf '%q tools/exhaustive_optimizer_reference.py --plan %q --out %q\n' "$python_bin" "$optimizer_out/plan.json" "$root/optimizer_reference.json"
  printf '%q run cmd/moonsplit -- plan --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --out %q --format jsonl\n' "$moon_bin" "$v2_grouped_out"
  printf '%q run cmd/moonsplit -- audit --data examples/v2_rule_records.jsonl --spec examples/v2_rule_spec.json --assignments %q --format jsonl --report json\n' "$moon_bin" "$v2_grouped_out/assignments.jsonl"
  printf '%q run cmd/moonsplit -- plan --data examples/time_records.jsonl --spec examples/time_forward_spec.json --out %q --format jsonl\n' "$moon_bin" "$time_forward_out"
  printf '%q run cmd/moonsplit -- audit --data examples/time_records.jsonl --spec examples/time_forward_spec.json --roles %q --format jsonl --report json\n' "$moon_bin" "$time_forward_out/roles.jsonl"
  for mode_records in 'exact 100000' 'interval 100000' 'text 1000' 'text 5000' 'text 10000'; do
    set -- $mode_records
    printf '%q run cmd/moonsplit -- bench --mode %s --records %s\n' "$moon_bin" "$1" "$2"
  done
} > "$root/commands.txt"

run_bench exact 100000
run_bench interval 100000
run_bench text 1000
run_bench text 5000
run_bench text 10000

moon --version > "$root/moon_version.txt"
moon info > "$root/moon_info.txt" 2>&1
git -c safe.directory="$PWD" rev-parse HEAD > "$root/git_sha.txt"
git -c safe.directory="$PWD" status --short > "$root/git_status.txt"
{
  uname -a
  if command -v lscpu >/dev/null 2>&1; then
    lscpu
  fi
  if command -v free >/dev/null 2>&1; then
    free -b
  fi
} > "$root/machine.txt"
{
  printf 'schema_version=1\n'
  printf 'status=candidate_evidence\n'
  printf 'generated_at_local=%s\n' "$generated_at_local"
  printf 'git_sha=%s\n' "$(cat "$root/git_sha.txt")"
  printf 'moon_version=%s\n' "$(tr '\n' ' ' < "$root/moon_version.txt")"
  printf 'checks=run_check.sh passed\n'
  printf 'commands_manifest=commands.txt\n'
  printf 'machine_file=machine.txt\n'
} > "$root/metadata.txt"
sha256sum \
  examples/v2_rule_records.jsonl \
  examples/v2_rule_spec.json \
  examples/v2_kfold_spec.json \
  examples/v2_text_only_bad_assignments.jsonl \
  examples/v2_interval_only_bad_assignments.jsonl \
  examples/time_records.jsonl \
  examples/time_forward_spec.json \
  examples/time_multi_records.jsonl \
  examples/time_multi_spec.json \
  examples/time_multi_spec_reordered.json \
  examples/time_zero_gap_spec.json \
  examples/optimizer_case.json \
  examples/optimizer_case_spec.json > "$root/input_hashes.sha256"

{
  echo "# MoonSplit v0.3.0 候选验收证据"
  echo
  echo "- 状态：自动化候选证据已生成；官方验收状态仍为“未通过”，本文件不替代官方结论。"
  echo "- Git SHA：\`$(cat "$root/git_sha.txt")\`"
  echo "- MoonBit：\`$(tr '\n' ' ' < "$root/moon_version.txt")\`"
  echo "- 基础检查：\`run_check.sh\` 已通过，完整日志为 \`run_check.log\`。"
  echo
  echo "## 固定优化对照"
  echo
  echo '```json'
  cat "$root/optimizer_reference.json"
  echo '```'
  echo
  echo "## 规模运行（机器相关）"
  echo
  echo "| 模型 | 记录数 | 耗时 ms | 日志 |"
  echo "| --- | ---: | ---: | --- |"
  while IFS=$'\t' read -r mode records elapsed log; do
    echo "| $mode | $records | $elapsed | \`$log\` |"
  done < "$root/benchmarks.tsv"
  echo
  echo "完整命令见 \`commands.txt\`；生成时间、Git SHA、MoonBit 版本和基础检查见 \`metadata.txt\`；输入 SHA-256、工具链、机器环境和命令输出分别见 \`input_hashes.sha256\`、\`moon_info.txt\`、\`machine.txt\` 和各 \`bench_*.log\`；执行时工作树状态见 \`git_status.txt\`。\`v2_grouped_plan\` 和 \`time_forward_plan\` 含可直接复核的产品文件及独立 audit 重检结果；\`artifact_hashes.sha256\` 覆盖本证据包的全部文件（不含自身）。耗时与机器信息不进入产品输出；产品输出的 wasm-gc/JS 字节比较由 \`run_check.sh\` 执行。"
} > "$root/acceptance.md"

find "$root" -type f ! -name artifact_hashes.sha256 -print0 | sort -z | xargs -0 sha256sum > "$root/artifact_hashes.sha256"

echo "acceptance=ok artifacts=$root"
