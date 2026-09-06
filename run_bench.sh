#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
moon run cmd/moonsplit -- bench --records 100000 --speakers 20000
