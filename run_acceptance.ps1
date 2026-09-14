param(
  [string]$MoonExe = "moon"
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$root = Join-Path $PSScriptRoot "artifacts\acceptance_${stamp}_$PID"
if (Test-Path -LiteralPath $root) {
  throw "refusing to reuse output path: $root"
}
New-Item -ItemType Directory -Path $root | Out-Null

function Write-Utf8File {
  param([string]$Path, [string]$Content)
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Benchmark {
  param([string]$Mode, [int]$Records)
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $lines = @(& $MoonExe run cmd/moonsplit -- bench --mode $Mode --records "$Records" 2>&1)
  $exitCode = $LASTEXITCODE
  $stopwatch.Stop()
  $text = [string]::Join("`n", ($lines | ForEach-Object { $_.ToString() }))
  $path = Join-Path $root "bench_${Mode}_${Records}.log"
  Write-Utf8File $path ($text + "`n")
  if ($exitCode -ne 0) {
    throw "benchmark $Mode/$Records exited with $exitCode`n$text"
  }
  [pscustomobject]@{
    mode = $Mode
    records = $Records
    elapsed_ms = $stopwatch.ElapsedMilliseconds
    exit_code = $exitCode
    log = [System.IO.Path]::GetFileName($path)
    output = $text
  }
}

function Get-InputHash {
  param([string]$Path)
  [pscustomobject]@{
    path = $Path
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  }
}

function Invoke-MoonCommand {
  param(
    [string[]]$CommandArgs,
    [string]$Label
  )
  $lines = @(& $MoonExe @CommandArgs 2>&1)
  $exitCode = $LASTEXITCODE
  $text = [string]::Join("`n", ($lines | ForEach-Object { $_.ToString() }))
  if ($exitCode -ne 0) {
    throw "$Label exited with $exitCode`n$text"
  }
  $text
}

$checkLog = Join-Path $root "run_check.log"
try {
  & .\run_check.ps1 -MoonExe $MoonExe *>&1 | Tee-Object -LiteralPath $checkLog
} catch {
  throw "run_check.ps1 failed; see $checkLog`n$($_.Exception.Message)"
}

$optimizerOut = Join-Path $root "optimizer_plan"
$optimizerStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$optimizerLines = @(& $MoonExe run cmd/moonsplit -- plan --data examples\optimizer_case.json --spec examples\optimizer_case_spec.json --out $optimizerOut --format json 2>&1)
$optimizerExit = $LASTEXITCODE
$optimizerStopwatch.Stop()
$optimizerText = [string]::Join("`n", ($optimizerLines | ForEach-Object { $_.ToString() }))
Write-Utf8File (Join-Path $root "optimizer_plan.log") ($optimizerText + "`n")
if ($optimizerExit -ne 0) {
  throw "optimizer comparison plan exited with $optimizerExit`n$optimizerText"
}
$optimizerPlan = Get-Content -LiteralPath (Join-Path $optimizerOut "plan.json") -Raw | ConvertFrom-Json

# Independent exhaustive reference for the fixed four-component fixture.
$components = @(
  [pscustomobject]@{ size = 5; a = 1; b = 4 },
  [pscustomobject]@{ size = 4; a = 4; b = 0 },
  [pscustomobject]@{ size = 3; a = 2; b = 1 },
  [pscustomobject]@{ size = 1; a = 0; b = 1 }
)
$bestObjective = [bigint]::Parse("999999999999")
for ($mask = 1; $mask -lt 15; $mask++) {
  $size = @([bigint]0, [bigint]0)
  $a = @([bigint]0, [bigint]0)
  $b = @([bigint]0, [bigint]0)
  for ($index = 0; $index -lt $components.Count; $index++) {
    $partition = (($mask -shr $index) -band 1)
    $size[$partition] += [bigint]$components[$index].size
    $a[$partition] += [bigint]$components[$index].a
    $b[$partition] += [bigint]$components[$index].b
  }
  $objective = [bigint]0
  for ($partition = 0; $partition -lt 2; $partition++) {
    $objective += (2 * $size[$partition] - 13) * (2 * $size[$partition] - 13)
    $objective += (2 * $a[$partition] - 7) * (2 * $a[$partition] - 7)
    $objective += (2 * $b[$partition] - 6) * (2 * $b[$partition] - 6)
  }
  if ($objective -lt $bestObjective) {
    $bestObjective = $objective
  }
}
$optimizerObjective = [bigint]::Parse([string]$optimizerPlan.objective)
$optimizerInitial = [bigint]::Parse([string]$optimizerPlan.initial_objective)
$optimizerEvidence = [pscustomobject]@{
  initial_objective = $optimizerInitial.ToString()
  optimized_objective = $optimizerObjective.ToString()
  exhaustive_optimum = $bestObjective.ToString()
  optimality_gap = ($optimizerObjective - $bestObjective).ToString()
  optimization_rounds = $optimizerPlan.optimization_rounds
  elapsed_ms = $optimizerStopwatch.ElapsedMilliseconds
}
if ($optimizerObjective -gt $optimizerInitial -or $optimizerObjective -ne $bestObjective) {
  throw "optimizer evidence violates the fixed-case acceptance predicate"
}
$optimizerEvidence | ConvertTo-Json -Depth 3 | ForEach-Object {
  Write-Utf8File (Join-Path $root "optimizer_reference.json") ($_ + "`n")
}

$v2GroupedOut = Join-Path $root "v2_grouped_plan"
$v2GroupedLog = Invoke-MoonCommand -CommandArgs @(
  "run", "cmd/moonsplit", "--", "plan", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--out", $v2GroupedOut, "--format", "jsonl"
) -Label "v2 grouped acceptance plan"
Write-Utf8File (Join-Path $root "v2_grouped_plan.log") ($v2GroupedLog + "`n")
$v2GroupedAudit = Invoke-MoonCommand -CommandArgs @(
  "run", "cmd/moonsplit", "--", "audit", "--data", "examples\v2_rule_records.jsonl", "--spec", "examples\v2_rule_spec.json", "--assignments", (Join-Path $v2GroupedOut "assignments.jsonl"), "--format", "jsonl", "--report", "json"
) -Label "v2 grouped independent audit"
Write-Utf8File (Join-Path $root "v2_grouped_audit_recheck.json") ($v2GroupedAudit + "`n")

$timeForwardOut = Join-Path $root "time_forward_plan"
$timeForwardLog = Invoke-MoonCommand -CommandArgs @(
  "run", "cmd/moonsplit", "--", "plan", "--data", "examples\time_records.jsonl", "--spec", "examples\time_forward_spec.json", "--out", $timeForwardOut, "--format", "jsonl"
) -Label "time-forward acceptance plan"
Write-Utf8File (Join-Path $root "time_forward_plan.log") ($timeForwardLog + "`n")
$timeForwardAudit = Invoke-MoonCommand -CommandArgs @(
  "run", "cmd/moonsplit", "--", "audit", "--data", "examples\time_records.jsonl", "--spec", "examples\time_forward_spec.json", "--roles", (Join-Path $timeForwardOut "roles.jsonl"), "--format", "jsonl", "--report", "json"
) -Label "time-forward independent audit"
Write-Utf8File (Join-Path $root "time_forward_audit_recheck.json") ($timeForwardAudit + "`n")

$commandLines = @(
  "# MoonSplit v0.3.0 acceptance commands; executed from $PSScriptRoot",
  ".\\run_acceptance.ps1 -MoonExe `"$MoonExe`"",
  ".\\run_check.ps1 -MoonExe `"$MoonExe`"",
  "& `"$MoonExe`" run cmd/moonsplit -- plan --data examples\\optimizer_case.json --spec examples\\optimizer_case_spec.json --out `"$optimizerOut`" --format json",
  "# Exhaustive fixed-fixture reference is evaluated by this runner before the acceptance predicate.",
  "& `"$MoonExe`" run cmd/moonsplit -- plan --data examples\\v2_rule_records.jsonl --spec examples\\v2_rule_spec.json --out `"$v2GroupedOut`" --format jsonl",
  "& `"$MoonExe`" run cmd/moonsplit -- audit --data examples\\v2_rule_records.jsonl --spec examples\\v2_rule_spec.json --assignments `"$(Join-Path $v2GroupedOut 'assignments.jsonl')`" --format jsonl --report json",
  "& `"$MoonExe`" run cmd/moonsplit -- plan --data examples\\time_records.jsonl --spec examples\\time_forward_spec.json --out `"$timeForwardOut`" --format jsonl",
  "& `"$MoonExe`" run cmd/moonsplit -- audit --data examples\\time_records.jsonl --spec examples\\time_forward_spec.json --roles `"$(Join-Path $timeForwardOut 'roles.jsonl')`" --format jsonl --report json",
  "& `"$MoonExe`" run cmd/moonsplit -- bench --mode exact --records 100000",
  "& `"$MoonExe`" run cmd/moonsplit -- bench --mode interval --records 100000",
  "& `"$MoonExe`" run cmd/moonsplit -- bench --mode text --records 1000",
  "& `"$MoonExe`" run cmd/moonsplit -- bench --mode text --records 5000",
  "& `"$MoonExe`" run cmd/moonsplit -- bench --mode text --records 10000"
)
Write-Utf8File (Join-Path $root "commands.txt") (($commandLines -join "`n") + "`n")

$benchmarks = @(
  Invoke-Benchmark "exact" 100000
  Invoke-Benchmark "interval" 100000
  Invoke-Benchmark "text" 1000
  Invoke-Benchmark "text" 5000
  Invoke-Benchmark "text" 10000
)

$moonVersionLines = @(& $MoonExe --version 2>&1)
if ($LASTEXITCODE -ne 0) { throw "moon --version failed with exit code $LASTEXITCODE" }
$moonVersion = [string]::Join("`n", ($moonVersionLines | ForEach-Object { $_.ToString() }))
$moonVersionShort = ($moonVersion -split "`r?`n")[0]
$moonInfoLines = @(& $MoonExe info 2>&1)
if ($LASTEXITCODE -ne 0) { throw "moon info failed with exit code $LASTEXITCODE" }
$moonInfo = [string]::Join("`n", ($moonInfoLines | ForEach-Object { $_.ToString() }))
$gitShaLines = @(& git -c "safe.directory=$PSScriptRoot" rev-parse HEAD 2>&1)
if ($LASTEXITCODE -ne 0) { throw "git rev-parse HEAD failed with exit code $LASTEXITCODE" }
$gitSha = [string]::Join("", ($gitShaLines | ForEach-Object { $_.ToString() })).Trim()
if ($gitSha -eq "") { throw "git rev-parse HEAD returned an empty SHA" }
$gitStatusLines = @(& git -c "safe.directory=$PSScriptRoot" status --short 2>&1)
if ($LASTEXITCODE -ne 0) { throw "git status failed with exit code $LASTEXITCODE" }
# A clean worktree produces no pipeline object in PowerShell. `-join` maps
# that case to an empty string, while .NET String.Join receives null and
# aborts the formal evidence run.
$gitStatus = ($gitStatusLines | ForEach-Object { $_.ToString() }) -join "`n"
# Do not require a privileged WMI/CIM query merely to capture provenance.  The
# environment APIs are available in restricted CI and desktop sessions alike.
$processorName = [System.Environment]::GetEnvironmentVariable("PROCESSOR_IDENTIFIER")
if ([string]::IsNullOrWhiteSpace($processorName)) { $processorName = "unavailable" }
$machine = [pscustomobject]@{
  probe = "environment-api"
  os = [System.Environment]::OSVersion.VersionString
  powershell = $PSVersionTable.PSVersion.ToString()
  process_is_64bit = [System.Environment]::Is64BitProcess
  processor = $processorName
  logical_processors = [System.Environment]::ProcessorCount
  memory_bytes = $null
}
$inputs = @(
  Get-InputHash "examples\v2_rule_records.jsonl"
  Get-InputHash "examples\v2_rule_spec.json"
  Get-InputHash "examples\v2_kfold_spec.json"
  Get-InputHash "examples\v2_text_only_bad_assignments.jsonl"
  Get-InputHash "examples\v2_interval_only_bad_assignments.jsonl"
  Get-InputHash "examples\time_records.jsonl"
  Get-InputHash "examples\time_forward_spec.json"
  Get-InputHash "examples\time_multi_records.jsonl"
  Get-InputHash "examples\time_multi_spec.json"
  Get-InputHash "examples\time_multi_spec_reordered.json"
  Get-InputHash "examples\time_zero_gap_spec.json"
  Get-InputHash "examples\optimizer_case.json"
  Get-InputHash "examples\optimizer_case_spec.json"
)
$metadata = [pscustomobject]@{
  schema_version = 1
  status = "candidate_evidence"
  generated_at_local = (Get-Date).ToString("o")
  git_sha = $gitSha
  working_tree_status = $gitStatus
  moon_version = $moonVersion
  moon_info = $moonInfo
  machine = $machine
  checks = "run_check.ps1 passed"
  commands_manifest = "commands.txt"
  input_hashes = $inputs
  optimizer = $optimizerEvidence
  benchmarks = $benchmarks
}
$metadata | ConvertTo-Json -Depth 6 | ForEach-Object { Write-Utf8File (Join-Path $root "metadata.json") ($_ + "`n") }

$benchmarkRows = ($benchmarks | ForEach-Object {
  "| $($_.mode) | $($_.records) | $($_.elapsed_ms) | $($_.output -replace "`n", "; ") |"
}) -join "`n"
$report = @"
# MoonSplit v0.3.0 候选验收证据

- 状态：自动化候选证据已生成；官方验收状态仍为“未通过”，本文件不替代官方结论。
- Git SHA：$gitSha
- MoonBit：$moonVersionShort
- 检查：run_check.ps1 已通过，完整日志为 run_check.log。

## 固定优化对照

| 指标 | 值 |
| --- | ---: |
| 贪心初始化目标 | $($optimizerEvidence.initial_objective) |
| 局部优化目标 | $($optimizerEvidence.optimized_objective) |
| 穷举最优目标 | $($optimizerEvidence.exhaustive_optimum) |
| 最优值差距 | $($optimizerEvidence.optimality_gap) |
| 局部移动轮数 | $($optimizerEvidence.optimization_rounds) |

## 规模运行（机器相关）

| 模型 | 记录数 | 耗时 ms | 命令输出 |
| --- | ---: | ---: | --- |
$benchmarkRows

完整命令见 commands.txt；输入 SHA-256、工具链、机器环境、命令输出和所有运行时间见 metadata.json 与各 bench_*.log；固定用例的独立穷举结果见 optimizer_reference.json。v2_grouped_plan 和 time_forward_plan 含可直接复核的产品文件及独立 audit 重检结果；artifact_hashes.sha256 覆盖本证据包的全部文件（不含自身）。产品输出的字节一致性由 run_check.ps1 的 wasm-gc/JS 比对验证，时间和机器信息未写入产品输出。
"@
Write-Utf8File (Join-Path $root "acceptance.md") $report

$artifactHashLines = @()
Get-ChildItem -LiteralPath $root -Recurse -File |
  Where-Object { $_.Name -ne "artifact_hashes.sha256" } |
  Sort-Object FullName |
  ForEach-Object {
    $relative = ($_.FullName.Substring($root.Length) -replace '^[\\/]+', '') -replace '\\', '/'
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    $artifactHashLines += "$hash  $relative"
  }
Write-Utf8File (Join-Path $root "artifact_hashes.sha256") (($artifactHashLines -join "`n") + "`n")

Write-Host "acceptance=ok artifacts=$root"
