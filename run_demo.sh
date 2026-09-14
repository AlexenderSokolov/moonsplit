#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
moon_bin="${MOON_BIN:-moon}"
out="examples/demo_$(date +%Y%m%d_%H%M%S_%N)_$$"
if [ -e "$out" ]; then
  echo "refusing to reuse output path: $out" >&2
  exit 1
fi
"$moon_bin" run cmd/moonsplit -- demo --out "$out"
echo "output: $out"
