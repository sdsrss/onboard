#!/usr/bin/env bash
# verify-counts.sh — guard against drift between integration-test assertion
# counts and the claims documented in CLAUDE.md + CHANGELOG.md.
#
# Why this exists: in v2.10.x and v2.11.0 the per-test pass counts in
# CLAUDE.md's repo-inventory line drifted from reality across three releases.
# `feedback_cross_cutting_grep.md` lesson: cross-cutting drift class needs
# a mechanical check, not heroic discipline. This is that check.
#
# What it does:
#   1. Invokes each tests/integration/*.sh directly (NOT via run.sh — that
#      would recurse if this script were wired in as a test).
#   2. Captures the "pass: N" line from each test, sums into TOTAL_ACTUAL.
#   3. Reads CLAUDE.md inventory line, parses headline "N assertions across
#      M integration tests" and per-test claims `<name>.sh <count>`.
#   4. Reads latest CHANGELOG.md section, checks TOTAL_ACTUAL appears.
#
# Exit:
#   0 = all counts agree
#   1 = drift detected (printed to stderr)
#   2 = invocation / parse error
#
# Usage: run manually at release time, or invoke from a pre-commit hook /
#        CI step. NOT wired into tests/run.sh to avoid recursion.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "$(c '1;32' '✓') $*"; }
fail() { echo "$(c '1;31' '✗') $*" >&2; }
info() { echo "$(c '1;34' '[verify-counts]') $*"; }

# Discover integration tests
TESTS=()
for t in "$ROOT/tests/integration"/*.sh; do
  [ -f "$t" ] || continue
  TESTS+=("$t")
done
TEST_COUNT="${#TESTS[@]}"

if [ "$TEST_COUNT" -eq 0 ]; then
  fail "no tests under tests/integration/ — refusing to verify"
  exit 2
fi

info "running $TEST_COUNT integration tests to harvest counts"

# Run each test directly, capture per-test pass count.
declare -A PER_TEST
TOTAL_ACTUAL=0
ANY_FAIL=0

for t in "${TESTS[@]}"; do
  name="$(basename "$t" .sh)"
  out="$(bash "$t" 2>&1 || true)"
  pcount="$(echo "$out" | grep -E '^  pass: [0-9]+$' | head -1 | awk '{print $2}')"
  fcount="$(echo "$out" | grep -E '^  fail: [0-9]+$' | head -1 | awk '{print $2}')"
  if [ -z "$pcount" ]; then
    fail "$name produced no 'pass: N' line — output format drift"
    ANY_FAIL=1
    PER_TEST["$name"]=0
    continue
  fi
  if [ "${fcount:-0}" != "0" ]; then
    fail "$name has ${fcount} failing assertions — fix before verifying counts"
    ANY_FAIL=1
  fi
  PER_TEST["$name"]="$pcount"
  TOTAL_ACTUAL=$((TOTAL_ACTUAL + pcount))
  info "  $name: $pcount"
done

[ "$ANY_FAIL" -eq 1 ] && exit 2

info "total: $TOTAL_ACTUAL across $TEST_COUNT tests"
echo ""

# Verify CLAUDE.md
CLAUDE_MD="$ROOT/CLAUDE.md"
if [ ! -f "$CLAUDE_MD" ]; then
  fail "CLAUDE.md missing at $CLAUDE_MD"
  exit 2
fi

CLAUDE_LINE="$(grep -E 'assertions across [0-9]+ integration tests' "$CLAUDE_MD" | head -1)"
if [ -z "$CLAUDE_LINE" ]; then
  fail "CLAUDE.md missing 'N assertions across M integration tests' inventory line"
  exit 1
fi

CLAUDE_TOTAL="$(echo "$CLAUDE_LINE" | grep -oE '[0-9]+ assertions' | head -1 | grep -oE '[0-9]+')"
CLAUDE_TESTS="$(echo "$CLAUDE_LINE" | grep -oE 'across [0-9]+ integration' | grep -oE '[0-9]+')"

DRIFT=0
if [ "$CLAUDE_TOTAL" = "$TOTAL_ACTUAL" ]; then
  pass "CLAUDE.md headline: $CLAUDE_TOTAL assertions matches actual"
else
  fail "CLAUDE.md headline drift: claims $CLAUDE_TOTAL, actual $TOTAL_ACTUAL"
  DRIFT=1
fi
if [ "$CLAUDE_TESTS" = "$TEST_COUNT" ]; then
  pass "CLAUDE.md test-count: $CLAUDE_TESTS matches actual"
else
  fail "CLAUDE.md test-count drift: claims $CLAUDE_TESTS, actual $TEST_COUNT"
  DRIFT=1
fi

# Per-test counts — match by extracting <name>.sh followed by non-digit chars then digits.
# Avoids fragile backtick escaping in shell regex.
for name in "${!PER_TEST[@]}"; do
  expected="${PER_TEST[$name]}"
  # Replace dots in $name with literal escapes for grep -E.
  esc="$(echo "$name" | sed 's/\./\\./g')"
  match="$(echo "$CLAUDE_LINE" | grep -oE "${esc}\\.sh[^0-9]+[0-9]+" | head -1)"
  if [ -z "$match" ]; then
    fail "CLAUDE.md per-test count missing for $name.sh"
    DRIFT=1
    continue
  fi
  claimed="$(echo "$match" | grep -oE '[0-9]+$')"
  if [ "$claimed" = "$expected" ]; then
    pass "CLAUDE.md per-test: $name.sh = $claimed matches actual"
  else
    fail "CLAUDE.md per-test drift: $name.sh claims $claimed, actual $expected"
    DRIFT=1
  fi
done

# Verify CHANGELOG.md latest section mentions TOTAL_ACTUAL
CHANGELOG="$ROOT/CHANGELOG.md"
if [ ! -f "$CHANGELOG" ]; then
  fail "CHANGELOG.md missing"
  exit 2
fi

# Extract latest section (between first "## " header and next "## " header)
LATEST="$(awk '/^## /{c++; if(c==2)exit} c==1' "$CHANGELOG")"
if echo "$LATEST" | grep -qE "(\\b${TOTAL_ACTUAL}\\b.*(assertions|passed|PASS))|→ ${TOTAL_ACTUAL}\\b"; then
  pass "CHANGELOG.md latest section references $TOTAL_ACTUAL"
else
  fail "CHANGELOG.md latest section doesn't reference total $TOTAL_ACTUAL"
  DRIFT=1
fi

# Verify README badges. The shields.io badge URL hardcodes the count and was
# missed by prior preflight runs — added after v3.0.1 dogfood found stale 214.
for readme in "$ROOT/README.md" "$ROOT/README.zh-CN.md"; do
  [ -f "$readme" ] || continue
  name="$(basename "$readme")"
  badge_n="$(grep -oE 'tests-[0-9]+%20passing' "$readme" | head -1 | grep -oE '[0-9]+' | head -1)"
  if [ -z "$badge_n" ]; then
    fail "$name missing tests-N%20passing badge"
    DRIFT=1
    continue
  fi
  if [ "$badge_n" = "$TOTAL_ACTUAL" ]; then
    pass "$name tests badge: $badge_n matches actual"
  else
    fail "$name tests badge drift: claims $badge_n, actual $TOTAL_ACTUAL"
    DRIFT=1
  fi
done

if [ "$DRIFT" -ne 0 ]; then
  fail "drift detected — fix counts in CLAUDE.md / CHANGELOG.md / README badges before committing"
  exit 1
fi

echo ""
echo "$(c '1;32' '✓ all count claims agree with actual test output')"
exit 0
