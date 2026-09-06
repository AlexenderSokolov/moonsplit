$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
$out = "examples/demo_" + (Get-Date -Format "yyyyMMdd_HHmmss")
moon run cmd/moonsplit -- demo --out $out
Write-Host "output: $out"
