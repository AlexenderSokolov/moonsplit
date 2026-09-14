param(
  [string]$MoonExe = "moon"
)

$ErrorActionPreference = "Stop"
function moon {
  & $script:MoonExe @args
}
Set-Location -LiteralPath $PSScriptRoot
moon check --deny-warn
if ($LASTEXITCODE -ne 0) { throw "moon check failed" }
moon test --deny-warn
if ($LASTEXITCODE -ne 0) { throw "moon test failed" }
moon test --target js --deny-warn
if ($LASTEXITCODE -ne 0) { throw "moon test --target js failed" }

moon info
if ($LASTEXITCODE -ne 0) { throw "moon info failed" }
moon fmt --check
if ($LASTEXITCODE -ne 0) { throw "moon fmt --check failed" }

$version = & moon run cmd/moonsplit -- --version
if ($version -ne "MoonSplit 0.3.0") {
  throw "--version printed '$version', expected 'MoonSplit 0.3.0'"
}

$version = & moon run cmd/moonsplit -- version
if ($version -ne "MoonSplit 0.3.0") {
  throw "version printed '$version', expected 'MoonSplit 0.3.0'"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$root = Join-Path $PSScriptRoot "artifacts\check_$stamp"
if (Test-Path -LiteralPath $root) {
  throw "refusing to reuse output path: $root"
}
New-Item -ItemType Directory -Path $root | Out-Null
$wasm_out = Join-Path $root "wasm_plan"
$js_out = Join-Path $root "js_plan"
$kfold_wasm_out = Join-Path $root "wasm_kfold"
$kfold_js_out = Join-Path $root "js_kfold"
$multikey_out = Join-Path $root "multikey_plan"
$label_out = Join-Path $root "label_plan"
$chinese_out = Join-Path $root "中文 路径"
$missing_out = Join-Path $root "missing_parent\plan"
$v2_wasm_out = Join-Path $root "v2_wasm_plan"
$v2_js_out = Join-Path $root "v2_js_plan"
$v2_repeat_out = Join-Path $root "v2_repeat_plan"
$v2_reordered_out = Join-Path $root "v2_reordered_plan"
$v2_kfold_out = Join-Path $root "v2_kfold_plan"
$v2_kfold_js_out = Join-Path $root "v2_kfold_js_plan"
$v2_kfold_normalized_spec = Join-Path $root "v2_kfold_normalized_spec.json"
$time_wasm_out = Join-Path $root "time_wasm_plan"
$time_js_out = Join-Path $root "time_js_plan"
$time_multi_wasm_out = Join-Path $root "time_multi_wasm_plan"
$time_multi_js_out = Join-Path $root "time_multi_js_plan"
$time_zero_gap_wasm_out = Join-Path $root "time_zero_gap_wasm_plan"
$time_zero_gap_js_out = Join-Path $root "time_zero_gap_js_plan"
$time_multi_wasm_repeat_out = Join-Path $root "time_multi_wasm_repeat_plan"
$time_multi_js_repeat_out = Join-Path $root "time_multi_js_repeat_plan"
$time_multi_wasm_reversed_out = Join-Path $root "time_multi_wasm_reversed_plan"
$time_multi_js_reversed_out = Join-Path $root "time_multi_js_reversed_plan"
$time_multi_wasm_reordered_out = Join-Path $root "time_multi_wasm_reordered_plan"
$time_multi_js_reordered_out = Join-Path $root "time_multi_js_reordered_plan"

function Invoke-Expected {
  param(
    [string]$Target,
    [string[]]$CommandArgs,
    [int]$ExpectedExitCode,
    [string]$Label
  )
  Write-Host "check: $Label"
  & moon run --target $Target cmd/moonsplit -- @CommandArgs
  if ($LASTEXITCODE -ne $ExpectedExitCode) {
    throw "$Label exited with $LASTEXITCODE, expected $ExpectedExitCode"
  }
}

function Invoke-Captured {
  param(
    [string]$Target,
    [string[]]$CommandArgs,
    [int]$ExpectedExitCode,
    [string]$Label
  )
  Write-Host "check: $Label"
  $lines = @(& moon run --target $Target cmd/moonsplit -- @CommandArgs 2>&1)
  $actual = $LASTEXITCODE
  if ($actual -ne $ExpectedExitCode) {
    $text = [string]::Join("`n", ($lines | ForEach-Object { $_.ToString() }))
    throw "$Label exited with $actual, expected $ExpectedExitCode`n$text"
  }
  [string]::Join("`n", ($lines | ForEach-Object { $_.ToString() }))
}

function Assert-Contains {
  param([string]$Text, [string]$Needle, [string]$Label)
  if (-not $Text.Contains($Needle)) {
    throw "$Label did not contain '$Needle'"
  }
}

$normalized_wasm = (Invoke-Captured wasm-gc @(
  "normalize-spec", "--spec", "examples\holdout_spec.json"
) 0 "wasm-gc normalize-spec").TrimEnd()
$normalized_js = (Invoke-Captured js @(
  "normalize-spec", "--spec", "examples\holdout_spec.json"
) 0 "JS normalize-spec").TrimEnd()
$expected_normalized = @'
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
'@.Trim()
if ($normalized_wasm -ne $expected_normalized -or $normalized_js -ne $expected_normalized) {
  throw "normalize-spec output does not match the canonical fixture"
}

$wasm_plan_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--out", $wasm_out, "--format", "jsonl"
) 0 "wasm-gc plan"
Assert-Contains $wasm_plan_log "plan=ok" "wasm-gc plan"
Assert-Contains $wasm_plan_log "files=5" "wasm-gc plan"
$js_plan_log = Invoke-Captured js @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--out", $js_out, "--format", "jsonl"
) 0 "JS plan"
Assert-Contains $js_plan_log "files=5" "JS plan"

foreach ($name in @("plan.json", "assignments.jsonl", "components.jsonl", "report.md", "summary.json")) {
  $wasm_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $wasm_out $name)).Hash
  $js_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $js_out $name)).Hash
  if ($wasm_hash -ne $js_hash) {
    throw "$name differs between wasm-gc and JS"
  }
}
$summary = Get-Content -LiteralPath (Join-Path $wasm_out "summary.json") -Raw | ConvertFrom-Json
if ($summary.schema_version -ne 1 -or $summary.algorithm -ne "group-greedy-v1") {
  throw "summary.json schema or algorithm is incorrect"
}
if ($summary.records -ne 4 -or $summary.components -ne 4 -or $summary.partitions.Count -ne 3) {
  throw "summary.json counts are incorrect"
}
$report_raw = Get-Content -LiteralPath (Join-Path $wasm_out "report.md") -Raw
Assert-Contains $report_raw "## Labels" "report.md"
Assert-Contains $report_raw "Target (bp)" "report.md"

$kfold_wasm_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\kfold_records.jsonl", "--spec", "examples\kfold_spec.json", "--out", $kfold_wasm_out, "--format", "jsonl"
) 0 "wasm-gc kfold plan"
Assert-Contains $kfold_wasm_log "files=6" "wasm-gc kfold plan"
$kfold_js_log = Invoke-Captured js @(
  "plan", "--data", "examples\kfold_records.jsonl", "--spec", "examples\kfold_spec.json", "--out", $kfold_js_out, "--format", "jsonl"
) 0 "JS kfold plan"
Assert-Contains $kfold_js_log "files=6" "JS kfold plan"
$kfold_files = @("plan.json", "assignments.jsonl", "components.jsonl", "report.md", "summary.json", "folds.jsonl")
foreach ($name in $kfold_files) {
  $wasm_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $kfold_wasm_out $name)).Hash
  $js_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $kfold_js_out $name)).Hash
  if ($wasm_hash -ne $js_hash) {
    throw "kfold $name differs between wasm-gc and JS"
  }
}
if (Test-Path -LiteralPath (Join-Path $wasm_out "folds.jsonl")) {
  throw "holdout output unexpectedly contains folds.jsonl"
}
$fold_raw = Get-Content -LiteralPath (Join-Path $kfold_wasm_out "folds.jsonl") -Raw
if ($fold_raw.EndsWith("`n") -or $fold_raw.EndsWith("`r")) {
  throw "folds.jsonl has a trailing newline"
}
$fold_lines = $fold_raw -split "`n"
if ($fold_lines.Count -ne 5) {
  throw "folds.jsonl does not contain one line per record"
}
$fold_ids = @{}
foreach ($line in $fold_lines) {
  $entry = $line | ConvertFrom-Json
  if ($fold_ids.ContainsKey($entry.id)) {
    throw "folds.jsonl repeats record $($entry.id)"
  }
  $fold_ids[$entry.id] = $true
  if (-not $entry.validation_fold.StartsWith("fold_")) {
    throw "folds.jsonl contains an invalid fold name"
  }
}

$multikey_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\multikey_records.jsonl", "--spec", "examples\multikey_spec.json", "--out", $multikey_out, "--format", "jsonl"
) 0 "multi-key transitive-closure plan"
Assert-Contains $multikey_log "files=5" "multi-key transitive-closure plan"
$multikey_summary = Get-Content -LiteralPath (Join-Path $multikey_out "summary.json") -Raw | ConvertFrom-Json
if ($multikey_summary.components -ne 2 -or $multikey_summary.largest_component.size -ne 3) {
  throw "multi-key component closure was not reflected in summary.json"
}
Assert-Contains (Get-Content -LiteralPath (Join-Path $multikey_out "components.jsonl") -Raw) '"member_ids": ["chain_a", "chain_b", "chain_c"]' "components.jsonl"

$label_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\label_records.jsonl", "--spec", "examples\label_spec.json", "--out", $label_out, "--format", "jsonl"
) 0 "label-aware summary plan"
$label_raw = Get-Content -LiteralPath (Join-Path $label_out "summary.json") -Raw
Assert-Contains $label_raw '"label_counts"' "label-aware summary"
Assert-Contains $label_raw '"unlabeled_count": 1' "label-aware summary"
Assert-Contains $label_raw '"": 1' "label-aware summary"
Assert-Contains $label_raw '"a": 1' "label-aware summary"
Assert-Contains $label_raw '"z": 1' "label-aware summary"

Invoke-Expected wasm-gc @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--out", $chinese_out, "--format", "jsonl"
) 0 "Chinese path with a space"
$audit_text = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--assignments", "$wasm_out\assignments.jsonl"
) 0 "independent audit"
Assert-Contains $audit_text "audit=pass" "independent audit"
$audit_valid_raw = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--assignments", "$wasm_out\assignments.jsonl", "--report", "json"
) 0 "audit JSON success"
$audit_valid = $audit_valid_raw | ConvertFrom-Json
if (-not $audit_valid.valid -or $audit_valid.records -ne 4 -or $audit_valid.assignments -ne 4) {
  throw "audit JSON success report is incorrect"
}
$audit_invalid_raw = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--assignments", "examples\bad_assignments.jsonl", "--report", "json"
) 3 "audit JSON semantic failure"
$audit_invalid = $audit_invalid_raw | ConvertFrom-Json
if ($audit_invalid.valid -or $audit_invalid.issues.Count -eq 0) {
  throw "audit JSON semantic failure report is incorrect"
}
Invoke-Expected wasm-gc @(
  "audit", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--assignments", "examples\bad_assignments.jsonl"
) 3 "audit failure"
Invoke-Expected wasm-gc @(
  "audit", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--assignments", "examples\invalid_empty_assignments.jsonl"
) 2 "assignment input failure"
$validate_args = @(
  "validate", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--format", "jsonl"
)
$validate_wasm = Invoke-Captured wasm-gc $validate_args 0 "wasm-gc validation preflight"
$validate_js = Invoke-Captured js $validate_args 0 "JS validation preflight"
if ($validate_wasm -ne $validate_js) {
  throw "validate output differs between wasm-gc and JS"
}
Assert-Contains $validate_wasm "validate=ok" "validate output"
Assert-Contains $validate_wasm "records=4" "validate output"
Assert-Contains $validate_wasm "warnings=3" "validate output"
if (Test-Path -LiteralPath (Join-Path $root "validate_should_not_exist")) {
  throw "validate created an output path"
}
Invoke-Expected wasm-gc @(
  "validate", "--data", "examples\voice_records.jsonl", "--spec", "examples\missing_spec.json"
) 2 "validate input failure"
Invoke-Expected wasm-gc @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\missing_spec.json", "--out", "$root\never_created"
) 2 "missing spec file"
Invoke-Expected wasm-gc @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--out", $wasm_out
) 4 "existing output path"
Invoke-Expected wasm-gc @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--out", $missing_out
) 4 "missing output parent"

$v2_normalized_wasm = (Invoke-Captured wasm-gc @(
  "normalize-spec", "--spec", "examples\v2_rule_spec.json"
) 0 "wasm-gc v2 normalize-spec").TrimEnd()
$v2_normalized_js = (Invoke-Captured js @(
  "normalize-spec", "--spec", "examples\v2_rule_spec.json"
) 0 "JS v2 normalize-spec").TrimEnd()
if ($v2_normalized_wasm -ne $v2_normalized_js) {
  throw "v2 normalize-spec differs between wasm-gc and JS"
}
Assert-Contains $v2_normalized_wasm '"schema_version": 2' "v2 normalize-spec"
Assert-Contains $v2_normalized_wasm '"type": "text_jaccard"' "v2 normalize-spec"
Assert-Contains $v2_normalized_wasm '"partitions":' "v2 holdout normalize-spec"
Assert-Contains $v2_normalized_wasm '"name": "train", "weight": 1' "v2 holdout normalize-spec"
if ($v2_normalized_wasm.Contains('"k"')) {
  throw "v2 holdout normalize-spec unexpectedly contains k"
}

$v2_kfold_normalized_wasm = (Invoke-Captured wasm-gc @(
  "normalize-spec", "--spec", "examples\v2_kfold_spec.json"
) 0 "wasm-gc v2 kfold normalize-spec").TrimEnd()
$v2_kfold_normalized_js = (Invoke-Captured js @(
  "normalize-spec", "--spec", "examples\v2_kfold_spec.json"
) 0 "JS v2 kfold normalize-spec").TrimEnd()
if ($v2_kfold_normalized_wasm -ne $v2_kfold_normalized_js) {
  throw "v2 kfold normalize-spec differs between wasm-gc and JS"
}
Assert-Contains $v2_kfold_normalized_wasm '"kind": "kfold"' "v2 kfold normalize-spec"
Assert-Contains $v2_kfold_normalized_wasm '"k": 2' "v2 kfold normalize-spec"
if ($v2_kfold_normalized_wasm.Contains('"partitions"')) {
  throw "v2 kfold normalize-spec unexpectedly contains generated partitions"
}
Set-Content -LiteralPath $v2_kfold_normalized_spec -Value $v2_kfold_normalized_wasm -NoNewline -Encoding utf8
$v2_kfold_roundtrip_wasm = (Invoke-Captured wasm-gc @(
  "normalize-spec", "--spec", $v2_kfold_normalized_spec
) 0 "wasm-gc v2 kfold normalize-spec round trip").TrimEnd()
$v2_kfold_roundtrip_js = (Invoke-Captured js @(
  "normalize-spec", "--spec", $v2_kfold_normalized_spec
) 0 "JS v2 kfold normalize-spec round trip").TrimEnd()
if ($v2_kfold_roundtrip_wasm -ne $v2_kfold_normalized_wasm -or $v2_kfold_roundtrip_js -ne $v2_kfold_normalized_wasm) {
  throw "v2 kfold normalize-spec does not round trip canonically"
}

$v2_validate_wasm = Invoke-Captured wasm-gc @(
  "validate", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--format", "jsonl"
) 0 "wasm-gc v2 validation preflight"
$v2_validate_js = Invoke-Captured js @(
  "validate", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--format", "jsonl"
) 0 "JS v2 validation preflight"
if ($v2_validate_wasm -ne $v2_validate_js) {
  throw "v2 validate output differs between wasm-gc and JS"
}
Assert-Contains $v2_validate_wasm "schema_version=2" "v2 validation preflight"
if (Test-Path -LiteralPath (Join-Path $root "v2_validate_should_not_exist")) {
  throw "v2 validate created an output path"
}

$v2_wasm_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--out", $v2_wasm_out, "--format", "jsonl"
) 0 "wasm-gc v2 plan"
Assert-Contains $v2_wasm_log "files=7" "wasm-gc v2 plan"
$v2_js_log = Invoke-Captured js @(
  "plan", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--out", $v2_js_out, "--format", "jsonl"
) 0 "JS v2 plan"
Assert-Contains $v2_js_log "files=7" "JS v2 plan"
foreach ($name in @("plan.json", "assignments.jsonl", "components.jsonl", "report.md", "summary.json", "evidence.jsonl", "audit.json")) {
  $wasm_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $v2_wasm_out $name)).Hash
  $js_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $v2_js_out $name)).Hash
  if ($wasm_hash -ne $js_hash) {
    throw "v2 $name differs between wasm-gc and JS"
  }
}
$v2_summary = Get-Content -LiteralPath (Join-Path $v2_wasm_out "summary.json") -Raw | ConvertFrom-Json
if ($v2_summary.components -ne 4 -or $v2_summary.text_candidate_count -lt 1) {
  throw "v2 summary misses rule-component or text evidence"
}
Assert-Contains (Get-Content -LiteralPath (Join-Path $v2_wasm_out "report.md") -Raw) "explanatory forest" "v2 report"

Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--out", $v2_repeat_out, "--format", "jsonl"
) 0 "v2 repeated deterministic plan" | Out-Null
foreach ($name in @("plan.json", "assignments.jsonl", "components.jsonl", "report.md", "summary.json", "evidence.jsonl", "audit.json")) {
  $canonical_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $v2_wasm_out $name)).Hash
  $repeat_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $v2_repeat_out $name)).Hash
  if ($canonical_hash -ne $repeat_hash) {
    throw "v2 repeated output differs for $name"
  }
}

$reversed_records_path = Join-Path $root "v2_rule_records_reversed.jsonl"
$reversed_lines = @(Get-Content -LiteralPath "examples\v2_rule_records.jsonl")
[array]::Reverse($reversed_lines)
[System.IO.File]::WriteAllLines($reversed_records_path, [string[]]$reversed_lines, [System.Text.UTF8Encoding]::new($false))
Invoke-Captured wasm-gc @(
  "plan", "--data", $reversed_records_path, "--spec", "examples\v2_rule_spec_reordered.json", "--out", $v2_reordered_out, "--format", "jsonl"
) 0 "v2 reordered deterministic plan" | Out-Null
foreach ($name in @("plan.json", "assignments.jsonl", "components.jsonl", "report.md", "summary.json", "evidence.jsonl", "audit.json")) {
  $canonical_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $v2_wasm_out $name)).Hash
  $reordered_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $v2_reordered_out $name)).Hash
  if ($canonical_hash -ne $reordered_hash) {
    throw "v2 deterministic output differs for $name"
  }
}

$v2_kfold_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_kfold_spec.json", "--out", $v2_kfold_out, "--format", "jsonl"
) 0 "v2 kfold plan"
Assert-Contains $v2_kfold_log "files=8" "v2 kfold plan"
$v2_kfold_js_log = Invoke-Captured js @(
  "plan", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_kfold_spec.json", "--out", $v2_kfold_js_out, "--format", "jsonl"
) 0 "JS v2 kfold plan"
Assert-Contains $v2_kfold_js_log "files=8" "JS v2 kfold plan"
foreach ($name in @("plan.json", "assignments.jsonl", "components.jsonl", "report.md", "summary.json", "evidence.jsonl", "audit.json", "folds.jsonl")) {
  if (-not (Test-Path -LiteralPath (Join-Path $v2_kfold_out $name))) {
    throw "v2 kfold output is missing $name"
  }
  $wasm_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $v2_kfold_out $name)).Hash
  $js_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $v2_kfold_js_out $name)).Hash
  if ($wasm_hash -ne $js_hash) {
    throw "v2 kfold $name differs between wasm-gc and JS"
  }
}

$v2_audit_valid_raw = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--assignments", (Join-Path $v2_wasm_out "assignments.jsonl"), "--format", "jsonl", "--report", "json"
) 0 "v2 independent audit"
$v2_audit_valid = $v2_audit_valid_raw | ConvertFrom-Json
if (-not $v2_audit_valid.valid) {
  throw "v2 independent audit did not pass"
}
$v2_text_audit_raw = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--assignments", "examples\v2_text_only_bad_assignments.jsonl", "--format", "jsonl", "--report", "json"
) 3 "v2 text-only audit failure"
$v2_text_audit = $v2_text_audit_raw | ConvertFrom-Json
if ($v2_text_audit.valid -or -not (($v2_text_audit.issues | ForEach-Object { $_.code }) -contains "cross_partition_rule")) {
  throw "v2 text-only audit did not detect rule leakage"
}
Assert-Contains ([string]::Join("`n", @($v2_text_audit.issues | ForEach-Object { $_.message }))) "rule component text_a" "v2 text-only audit"
$v2_interval_audit_raw = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--assignments", "examples\v2_interval_only_bad_assignments.jsonl", "--format", "jsonl", "--report", "json"
) 3 "v2 interval-only audit failure"
$v2_interval_audit = $v2_interval_audit_raw | ConvertFrom-Json
if ($v2_interval_audit.valid -or -not (($v2_interval_audit.issues | ForEach-Object { $_.code }) -contains "cross_partition_rule")) {
  throw "v2 interval-only audit did not detect rule leakage"
}
Assert-Contains ([string]::Join("`n", @($v2_interval_audit.issues | ForEach-Object { $_.message }))) "rule component interval_a" "v2 interval-only audit"

$time_files = @("plan.json", "roles.jsonl", "exclusions.jsonl", "components.jsonl", "witnesses.jsonl", "summary.json", "report.md", "audit.json")
$time_normalized_wasm = (Invoke-Captured wasm-gc @(
  "normalize-spec", "--spec", "examples\time_multi_spec.json"
) 0 "wasm-gc time-forward normalize-spec").TrimEnd()
$time_normalized_js = (Invoke-Captured js @(
  "normalize-spec", "--spec", "examples\time_multi_spec.json"
) 0 "JS time-forward normalize-spec").TrimEnd()
if ($time_normalized_wasm -ne $time_normalized_js) {
  throw "time-forward normalize-spec differs between wasm-gc and JS"
}
Assert-Contains $time_normalized_wasm '"kind": "time_forward"' "time-forward normalize-spec"
Assert-Contains $time_normalized_wasm '"id": "fold_1"' "time-forward normalize-spec"

$time_validate_wasm = Invoke-Captured wasm-gc @(
  "validate", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec.json", "--format", "jsonl"
) 0 "wasm-gc time-forward validation preflight"
$time_validate_js = Invoke-Captured js @(
  "validate", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec.json", "--format", "jsonl"
) 0 "JS time-forward validation preflight"
if ($time_validate_wasm -ne $time_validate_js) {
  throw "time-forward validate output differs between wasm-gc and JS"
}
Assert-Contains $time_validate_wasm "roles=18" "time-forward validation preflight"
if (Test-Path -LiteralPath (Join-Path $root "time_validate_should_not_exist")) {
  throw "time-forward validate created an output path"
}

$time_wasm_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\time_records.jsonl", "--spec", "examples\time_forward_spec.json", "--out", $time_wasm_out, "--format", "jsonl"
) 0 "wasm-gc time-forward plan"
Assert-Contains $time_wasm_log "files=8" "wasm-gc time-forward plan"
$time_js_log = Invoke-Captured js @(
  "plan", "--data", "examples\time_records.jsonl", "--spec", "examples\time_forward_spec.json", "--out", $time_js_out, "--format", "jsonl"
) 0 "JS time-forward plan"
Assert-Contains $time_js_log "files=8" "JS time-forward plan"
foreach ($name in $time_files) {
  $wasm_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_wasm_out $name)).Hash
  $js_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_js_out $name)).Hash
  if ($wasm_hash -ne $js_hash) {
    throw "time-forward $name differs between wasm-gc and JS"
  }
}
$roles_raw = Get-Content -LiteralPath (Join-Path $time_wasm_out "roles.jsonl") -Raw
foreach ($reason in @("component_conflict", "historical", "gap", "boundary_overlap", "future")) {
  Assert-Contains $roles_raw "`"reason`": `"$reason`"" "time roles"
}
$time_audit_valid_raw = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\time_records.jsonl", "--spec", "examples\time_forward_spec.json", "--roles", (Join-Path $time_wasm_out "roles.jsonl"), "--format", "jsonl", "--report", "json"
) 0 "time-forward independent audit"
$time_audit_valid = $time_audit_valid_raw | ConvertFrom-Json
if (-not $time_audit_valid.valid) {
  throw "time-forward independent audit did not pass"
}
$time_audit_invalid_raw = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\time_records.jsonl", "--spec", "examples\time_forward_spec.json", "--roles", "examples\time_bad_roles.jsonl", "--format", "jsonl", "--report", "json"
) 3 "time-forward conflict audit failure"
$time_audit_invalid = $time_audit_invalid_raw | ConvertFrom-Json
if ($time_audit_invalid.valid -or -not (($time_audit_invalid.issues | ForEach-Object { $_.code }) -contains "temporal_component_leak")) {
  throw "time-forward audit did not detect component leakage"
}
Invoke-Expected wasm-gc @(
  "audit", "--data", "examples\time_records.jsonl", "--spec", "examples\time_forward_spec.json", "--assignments", "examples\v2_bad_assignments.jsonl", "--format", "jsonl"
) 2 "time-forward rejects assignments manifest"

$time_multi_wasm_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec.json", "--out", $time_multi_wasm_out, "--format", "jsonl"
) 0 "wasm-gc multi-window time-forward plan"
Assert-Contains $time_multi_wasm_log "files=8" "wasm-gc multi-window time-forward plan"
$time_multi_js_log = Invoke-Captured js @(
  "plan", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec.json", "--out", $time_multi_js_out, "--format", "jsonl"
) 0 "JS multi-window time-forward plan"
Assert-Contains $time_multi_js_log "files=8" "JS multi-window time-forward plan"
foreach ($name in $time_files) {
  $wasm_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_wasm_out $name)).Hash
  $js_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_js_out $name)).Hash
  if ($wasm_hash -ne $js_hash) {
    throw "multi-window time-forward $name differs between wasm-gc and JS"
  }
}
$time_multi_roles = @{}
foreach ($line in @(Get-Content -LiteralPath (Join-Path $time_multi_wasm_out "roles.jsonl"))) {
  $role = $line | ConvertFrom-Json
  $key = "$($role.fold_id)/$($role.id)"
  if ($time_multi_roles.ContainsKey($key)) {
    throw "multi-window roles.jsonl repeats $key"
  }
  $time_multi_roles[$key] = $role
}
if ($time_multi_roles.Count -ne 18) {
  throw "multi-window roles.jsonl does not contain one role per record and fold"
}
foreach ($expected in @(
  @("fold_0", "cutoff", "train", "historical"),
  @("fold_0", "duplicate_history", "excluded", "component_conflict"),
  @("fold_0", "touch_0", "excluded", "gap"),
  @("fold_0", "boundary_0", "excluded", "boundary_overlap"),
  @("fold_0", "future", "excluded", "future"),
  @("fold_1", "between", "train", "historical"),
  @("fold_1", "gap_1", "excluded", "gap"),
  @("fold_1", "validation_1", "validation", "validation_window")
)) {
  $key = "$($expected[0])/$($expected[1])"
  if (-not $time_multi_roles.ContainsKey($key)) {
    throw "multi-window roles.jsonl is missing $key"
  }
  $actual = $time_multi_roles[$key]
  if ($actual.role -ne $expected[2] -or $actual.reason -ne $expected[3]) {
    throw "multi-window role $key was $($actual.role)/$($actual.reason), expected $($expected[2])/$($expected[3])"
  }
}
$time_multi_audit_raw = Invoke-Captured wasm-gc @(
  "audit", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec.json", "--roles", (Join-Path $time_multi_wasm_out "roles.jsonl"), "--format", "jsonl", "--report", "json"
) 0 "multi-window time-forward independent audit"
$time_multi_audit = $time_multi_audit_raw | ConvertFrom-Json
if (-not $time_multi_audit.valid) {
  throw "multi-window time-forward independent audit did not pass"
}

$time_zero_gap_wasm_log = Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_zero_gap_spec.json", "--out", $time_zero_gap_wasm_out, "--format", "jsonl"
) 0 "wasm-gc zero-gap time-forward plan"
$time_zero_gap_js_log = Invoke-Captured js @(
  "plan", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_zero_gap_spec.json", "--out", $time_zero_gap_js_out, "--format", "jsonl"
) 0 "JS zero-gap time-forward plan"
foreach ($name in $time_files) {
  $wasm_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_zero_gap_wasm_out $name)).Hash
  $js_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_zero_gap_js_out $name)).Hash
  if ($wasm_hash -ne $js_hash) {
    throw "zero-gap time-forward $name differs between wasm-gc and JS"
  }
}
$zero_gap_touch = @(
  Get-Content -LiteralPath (Join-Path $time_zero_gap_wasm_out "roles.jsonl") |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { $_.fold_id -eq "fold_0" -and $_.id -eq "touch_0" }
)
if ($zero_gap_touch.Count -ne 1 -or $zero_gap_touch[0].role -ne "train" -or $zero_gap_touch[0].reason -ne "historical") {
  throw "zero-gap record ending at validation start was not historical training"
}

Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec.json", "--out", $time_multi_wasm_repeat_out, "--format", "jsonl"
) 0 "wasm-gc repeated multi-window time-forward plan" | Out-Null
Invoke-Captured js @(
  "plan", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec.json", "--out", $time_multi_js_repeat_out, "--format", "jsonl"
) 0 "JS repeated multi-window time-forward plan" | Out-Null
foreach ($name in $time_files) {
  $canonical_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_wasm_out $name)).Hash
  $wasm_repeat_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_wasm_repeat_out $name)).Hash
  $js_repeat_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_js_repeat_out $name)).Hash
  if ($canonical_hash -ne $wasm_repeat_hash -or $canonical_hash -ne $js_repeat_hash) {
    throw "repeated multi-window time-forward output differs for $name"
  }
}

$time_multi_reversed_records = Join-Path $root "time_multi_records_reversed.jsonl"
$time_multi_lines = @(Get-Content -LiteralPath "examples\time_multi_records.jsonl")
[array]::Reverse($time_multi_lines)
[System.IO.File]::WriteAllLines($time_multi_reversed_records, [string[]]$time_multi_lines, [System.Text.UTF8Encoding]::new($false))
Invoke-Captured wasm-gc @(
  "plan", "--data", $time_multi_reversed_records, "--spec", "examples\time_multi_spec.json", "--out", $time_multi_wasm_reversed_out, "--format", "jsonl"
) 0 "wasm-gc reversed multi-window time-forward plan" | Out-Null
Invoke-Captured js @(
  "plan", "--data", $time_multi_reversed_records, "--spec", "examples\time_multi_spec.json", "--out", $time_multi_js_reversed_out, "--format", "jsonl"
) 0 "JS reversed multi-window time-forward plan" | Out-Null
foreach ($name in $time_files) {
  $canonical_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_wasm_out $name)).Hash
  $wasm_reversed_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_wasm_reversed_out $name)).Hash
  $js_reversed_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_js_reversed_out $name)).Hash
  if ($canonical_hash -ne $wasm_reversed_hash -or $canonical_hash -ne $js_reversed_hash) {
    throw "reversed multi-window time-forward output differs for $name"
  }
}

Invoke-Captured wasm-gc @(
  "plan", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec_reordered.json", "--out", $time_multi_wasm_reordered_out, "--format", "jsonl"
) 0 "wasm-gc reordered-rule multi-window time-forward plan" | Out-Null
Invoke-Captured js @(
  "plan", "--data", "examples\time_multi_records.jsonl", "--spec", "examples\time_multi_spec_reordered.json", "--out", $time_multi_js_reordered_out, "--format", "jsonl"
) 0 "JS reordered-rule multi-window time-forward plan" | Out-Null
foreach ($name in $time_files) {
  $canonical_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_wasm_out $name)).Hash
  $wasm_reordered_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_wasm_reordered_out $name)).Hash
  $js_reordered_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $time_multi_js_reordered_out $name)).Hash
  if ($canonical_hash -ne $wasm_reordered_hash -or $canonical_hash -ne $js_reordered_hash) {
    throw "reordered-rule multi-window time-forward output differs for $name"
  }
}

Write-Host "check=ok artifacts=$root"
