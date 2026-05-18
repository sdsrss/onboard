#!/usr/bin/env bash
# SKILL.md spec assertion for P-A2 (v2.11): Phase 6 hook framework selection
# must recognize `package.json scripts.prepare` writing into `.git/hooks/`
# as an existing third-party hook installer (e.g. ad-hoc symlink), so onboard
# does NOT collide with the user's existing scheme.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$SOURCE_REPO/skills/onboard/SKILL.md"
PASS=0
FAIL=0

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "  $(c '1;32' '✓ PASS') $*"; PASS=$((PASS+1)); }
fail() { echo "  $(c '1;31' '✗ FAIL') $*"; FAIL=$((FAIL+1)); }
hdr()  { echo ""; echo "$(c '1;36' "═══ $* ═══")"; }

if [ ! -f "$SKILL" ]; then
  echo "ERROR: SKILL.md not found at $SKILL" >&2
  exit 2
fi

hdr "P-A2 · Phase 6 detects scripts.prepare → .git/hooks/ writer"
if grep -qE 'scripts\.prepare.*\.git/hooks/.*v2\.11' "$SKILL"; then
  pass "Phase 6 框架选型含 scripts.prepare + .git/hooks/ 信号 + v2.11 标记"
else
  fail "Phase 6 框架选型缺 scripts.prepare → .git/hooks/ 检测项"
fi

if grep -qE 'hook-prepare-script.*third-party 共存' "$SKILL"; then
  pass "Phase 6 给出 hook-prepare-script 标签 + third-party 共存策略"
else
  fail "Phase 6 缺 hook-prepare-script third-party 共存策略"
fi

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ prepare-script-detection surfaced FAILURES.')"
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
