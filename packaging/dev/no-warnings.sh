#!/bin/bash
# Run a build or test command and fail if it prints any warning, so CI keeps
# `make simulator` and `make test` clean. Usage: no-warnings.sh make simulator
set -uo pipefail
log=$(mktemp)
trap 'rm -f "$log"' EXIT
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
[ "$status" -eq 0 ] || exit "$status"
if grep -E '(^|[^a-z])warning: ' "$log" >/dev/null; then
    echo "Warnings above: fix them so this build stays clean." >&2
    exit 1
fi
