param(
  [string]$MoonExe = "moon"
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
& $MoonExe run cmd/moonsplit -- bench --mode exact --records 100000 --speakers 20000
if ($LASTEXITCODE -ne 0) { throw "exact benchmark failed" }
& $MoonExe run cmd/moonsplit -- bench --mode interval --records 100000
if ($LASTEXITCODE -ne 0) { throw "interval benchmark failed" }
foreach ($count in @(1000, 5000, 10000)) {
  & $MoonExe run cmd/moonsplit -- bench --mode text --records $count
  if ($LASTEXITCODE -ne 0) { throw "text benchmark failed for $count records" }
}
