#!/usr/bin/env bash
# /onboard test runner — runs every executable test under tests/integration/.
# Aggregates exit codes; non-zero if any test fails.
#
# Usage:
#   bash tests/run.sh              # run all
#   bash tests/run.sh plugin-install   # run a single test by basename
#
# Add a new test by dropping an executable .sh into tests/integration/.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$TESTS_DIR/integration"
FILTER="${1:-}"

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

if [ ! -d "$INTEGRATION_DIR" ]; then
  echo "ERROR: $INTEGRATION_DIR not found" >&2
  exit 2
fi

TOTAL=0
FAILED=0
FAILED_NAMES=()

for test in "$INTEGRATION_DIR"/*.sh; do
  [ -f "$test" ] || continue
  name="$(basename "$test" .sh)"
  if [ -n "$FILTER" ] && [ "$name" != "$FILTER" ]; then
    continue
  fi
  TOTAL=$((TOTAL+1))
  echo ""
  echo "$(c '1;35' "▶ tests/integration/$name.sh")"
  if bash "$test"; then
    echo "$(c '1;32' "✓ $name")"
  else
    rc=$?
    echo "$(c '1;31' "✗ $name (exit $rc)")"
    FAILED=$((FAILED+1))
    FAILED_NAMES+=("$name")
  fi
done

echo ""
echo "════════════════════════════════════════"
if [ "$TOTAL" -eq 0 ]; then
  if [ -n "$FILTER" ]; then
    echo "$(c '1;31' "✗ No test matched filter '$FILTER'")"
    exit 2
  fi
  echo "$(c '1;33' '⚠ no tests found')"
  exit 0
fi
echo "  tests run: $TOTAL"
echo "  failed:    $FAILED"
if [ "$FAILED" -gt 0 ]; then
  echo "  names:     ${FAILED_NAMES[*]}"
  echo "$(c '1;31' '✗ test run failed')"
  exit 1
fi
echo "$(c '1;32' '✓ all tests passed')"
