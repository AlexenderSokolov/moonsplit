#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
out="examples/demo_$(date +%Y%m%d_%H%M%S)"
moon run cmd/moonsplit -- demo --out "$out"
echo "output: $out"
