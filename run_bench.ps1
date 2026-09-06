$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
moon run cmd/moonsplit -- bench --records 100000 --speakers 20000
