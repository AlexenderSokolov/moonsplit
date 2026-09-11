$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
moon check --deny-warn
moon test --deny-warn
moon test --target js --deny-warn

moon info
moon fmt --check

$version = & moon run cmd/moonsplit -- --version
if ($version -ne "MoonSplit 0.2.0") {
  throw "--version printed '$version', expected 'MoonSplit 0.2.0'"
}

$version = & moon run cmd/moonsplit -- version
if ($version -ne "MoonSplit 0.2.0") {
  throw "version printed '$version', expected 'MoonSplit 0.2.0'"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$root = Join-Path $PSScriptRoot "artifacts\check_$stamp"
New-Item -ItemType Directory -Path $root -Force | Out-Null
$wasm_out = Join-Path $root "wasm_plan"
$js_out = Join-Path $root "js_plan"
$kfold_wasm_out = Join-Path $root "wasm_kfold"
$kfold_js_out = Join-Path $root "js_kfold"
$multikey_out = Join-Path $root "multikey_plan"
$label_out = Join-Path $root "label_plan"
$chinese_out = Join-Path $root "中文 路径"
$missing_out = Join-Path $root "missing_parent\plan"

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

Write-Host "check=ok artifacts=$root"
