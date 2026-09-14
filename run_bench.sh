#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
moon_bin="${MOON_BIN:-moon}"
"$moon_bin" run cmd/moonsplit -- bench --mode exact --records 100000 --speakers 20000
"$moon_bin" run cmd/moonsplit -- bench --mode interval --records 100000
for count in 1000 5000 10000; do
  "$moon_bin" run cmd/moonsplit -- bench --mode text --records "$count"
done
