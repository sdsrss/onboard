#!/usr/bin/env bash
# SKILL.md spec assertion for P-A3 (v2.11): Phase 1.7 A6 (behavioral_donts)
# must list `scripts/sync-version*` / `scripts/version-bump*` writing to ≥2
# manifests as a signal — the sync targets become `## Don't` entries because
# hand-edits are clobbered by the next sync run.

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

hdr "P-A3 · Phase 1.7 A6 recipe includes sync-version signal"
if grep -qE 'A6.*v2\.11.*sync-version.*同步目标' "$SKILL"; then
  pass "Phase 1.7 A6 含 v2.11 标记 + sync-version signal + 同步目标 don't-edit outcome"
else
  fail "Phase 1.7 A6 缺 sync-version / version-bump 检测项"
fi

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ sync-versions-detection surfaced FAILURES.')"
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
