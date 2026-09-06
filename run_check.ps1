$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
moon check --deny-warn
moon test --deny-warn
moon test --target js --deny-warn

moon info
moon fmt --check

$version = & moon run cmd/moonsplit -- --version
if ($version -ne "MoonSplit 0.1.1") {
  throw "--version printed '$version', expected 'MoonSplit 0.1.1'"
}

$version = & moon run cmd/moonsplit -- version
if ($version -ne "MoonSplit 0.1.1") {
  throw "version printed '$version', expected 'MoonSplit 0.1.1'"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$root = Join-Path $PSScriptRoot "artifacts\check_$stamp"
New-Item -ItemType Directory -Path $root -Force | Out-Null
$wasm_out = Join-Path $root "wasm_plan"
$js_out = Join-Path $root "js_plan"
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

Invoke-Expected wasm-gc @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--out", $wasm_out, "--format", "jsonl"
) 0 "wasm-gc plan"
Invoke-Expected js @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--out", $js_out, "--format", "jsonl"
) 0 "JS plan"

foreach ($name in @("plan.json", "assignments.jsonl", "components.jsonl", "report.md")) {
  $wasm_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $wasm_out $name)).Hash
  $js_hash = (Get-FileHash -Algorithm SHA256 (Join-Path $js_out $name)).Hash
  if ($wasm_hash -ne $js_hash) {
    throw "$name differs between wasm-gc and JS"
  }
}

Invoke-Expected wasm-gc @(
  "plan", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--out", $chinese_out, "--format", "jsonl"
) 0 "Chinese path with a space"
Invoke-Expected wasm-gc @(
  "audit", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--assignments", "$wasm_out\assignments.jsonl"
) 0 "independent audit"
Invoke-Expected wasm-gc @(
  "audit", "--data", "examples\voice_records.jsonl", "--spec", "examples\holdout_spec.json", "--assignments", "examples\bad_assignments.jsonl"
) 3 "audit failure"
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
