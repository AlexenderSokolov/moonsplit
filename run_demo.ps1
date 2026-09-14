param(
  [string]$MoonExe = "moon"
)

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
$out = "examples/demo_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff") + "_$PID"
if (Test-Path -LiteralPath $out) {
  throw "refusing to reuse output path: $out"
}
& $MoonExe run cmd/moonsplit -- demo --out $out
if ($LASTEXITCODE -ne 0) { throw "demo failed" }
Write-Host "output: $out"
