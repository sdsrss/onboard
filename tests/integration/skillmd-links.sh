#!/usr/bin/env bash
# Validates SKILL.md internal consistency to prevent drift between heading
# claims and actual content / between prose cross-refs and real files.
#
# Checks:
#   1. ### Iron Laws heading "N 条" claim matches actual numbered item count
#   2. ## 元规则 heading "N 条" claim matches actual numbered item count
#   3. All "Iron Law <N>" references in prose: N is in 1..(Iron Laws count)
#   4. All "元规则 <N>" / "Meta-rule <N>" references: N is in 1..(meta-rules count)
#   5. All hooks/<name>.sh references point to real files in skills/onboard/hooks/
#   6. All scripts/<name>.sh references point to real files in skills/onboard/scripts/
#   7. 4 required hook scripts are all referenced at least once in SKILL.md
#
# These are exactly the drift modes that bite when editors rename or
# renumber items but forget to update cross-references. Doesn't try to
# validate phase headers (the SKILL.md uses two parallel numberings —
# "Phase N · Title" and "## N. Output template title" — distinguishing
# them safely requires structural parsing, out of scope).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$SOURCE_REPO/skills/onboard/SKILL.md"
HOOKS_DIR="$SOURCE_REPO/skills/onboard/hooks"
SCRIPTS_DIR="$SOURCE_REPO/skills/onboard/scripts"
PHASES_DIR="$SOURCE_REPO/skills/onboard/phases"
REFS_DIR="$SOURCE_REPO/skills/onboard/references"
# v3.0 sub-file split (元规则 27): Phase 7 / Uninstall Mode / 状态文件结构
SUB_FILES=(
  "phases/phase-7.md"
  "phases/uninstall.md"
  "references/state-schema.md"
)
PASS=0
FAIL=0

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "  $(c '1;32' '✓ PASS') $*"; PASS=$((PASS+1)); }
fail() { echo "  $(c '1;31' '✗ FAIL') $*"; FAIL=$((FAIL+1)); }
info() { echo "$(c '1;34' '[step]') $*"; }
hdr()  { echo ""; echo "$(c '1;36' "═══ $* ═══")"; }

if [ ! -f "$SKILL" ]; then
  echo "ERROR: SKILL.md not found at $SKILL" >&2
  exit 2
fi

echo "SKILL.md: $SKILL"
echo "size:     $(wc -l <"$SKILL" | tr -d ' ') lines"

hdr "STEP 1: Iron Laws count consistency"
IRON_HEADING=$(grep -E "^### Iron Laws" "$SKILL" | head -1)
info "heading: $IRON_HEADING"
IRON_CLAIMED=$(echo "$IRON_HEADING" | grep -oE '[0-9]+ 条' | head -1 | grep -oE '[0-9]+' || echo "")
IRON_ACTUAL=$(awk '/^### Iron Laws/,/^### [^I]/' "$SKILL" | grep -cE '^[0-9]+\. ' || true)
if [ -n "$IRON_CLAIMED" ]; then
  pass "heading claims '$IRON_CLAIMED 条'"
else
  fail "heading missing 'N 条' marker"
fi
if [ "$IRON_CLAIMED" = "$IRON_ACTUAL" ]; then
  pass "actual count matches claim: $IRON_ACTUAL"
else
  fail "Iron Laws drift: heading=$IRON_CLAIMED actual=$IRON_ACTUAL"
fi

hdr "STEP 2: 元规则 count consistency"
META_HEADING=$(grep -E "^## 元规则" "$SKILL" | head -1)
info "heading: $META_HEADING"
META_CLAIMED=$(echo "$META_HEADING" | grep -oE '[0-9]+ 条' | head -1 | grep -oE '[0-9]+' || echo "")
META_ACTUAL=$(awk '/^## 元规则/,/^## [^元]/' "$SKILL" | grep -cE '^[0-9]+\. ' || true)
if [ -n "$META_CLAIMED" ]; then
  pass "heading claims '$META_CLAIMED 条'"
else
  fail "heading missing 'N 条' marker"
fi
if [ "$META_CLAIMED" = "$META_ACTUAL" ]; then
  pass "actual count matches claim: $META_ACTUAL"
else
  fail "元规则 drift: heading=$META_CLAIMED actual=$META_ACTUAL"
fi

hdr "STEP 3: Iron Law <N> cross-reference range"
BAD_IRON=()
while IFS= read -r n; do
  if [ "$n" -lt 1 ] || [ "$n" -gt "$IRON_ACTUAL" ]; then
    BAD_IRON+=("$n")
  fi
done < <(grep -oE 'Iron Law [0-9]+' "$SKILL" | grep -oE '[0-9]+' | sort -un)
if [ "${#BAD_IRON[@]}" -eq 0 ]; then
  pass "all 'Iron Law N' references in range 1..$IRON_ACTUAL"
else
  fail "out-of-range Iron Law refs: ${BAD_IRON[*]} (max is $IRON_ACTUAL)"
fi

hdr "STEP 4: 元规则 / Meta-rule <N> cross-reference range"
BAD_META=()
while IFS= read -r n; do
  [ -z "$n" ] && continue
  if [ "$n" -lt 1 ] || [ "$n" -gt "$META_ACTUAL" ]; then
    BAD_META+=("$n")
  fi
done < <(grep -oE '(元规则|Meta-rule) [0-9]+' "$SKILL" | grep -oE '[0-9]+' | sort -un)
if [ "${#BAD_META[@]}" -eq 0 ]; then
  pass "all '元规则/Meta-rule N' references in range 1..$META_ACTUAL"
else
  fail "out-of-range meta-rule refs: ${BAD_META[*]} (max is $META_ACTUAL)"
fi

hdr "STEP 5: hooks/<name>.sh references resolve"
HOOKS_MISSING=()
HOOKS_CHECKED=0
while IFS= read -r ref; do
  HOOKS_CHECKED=$((HOOKS_CHECKED+1))
  name="${ref#hooks/}"
  if [ ! -f "$HOOKS_DIR/$name" ]; then
    HOOKS_MISSING+=("$ref")
  fi
done < <(grep -oE 'hooks/[a-z-]+\.sh' "$SKILL" | sort -u)
if [ "$HOOKS_CHECKED" -eq 0 ]; then
  fail "no hooks/*.sh references found in SKILL.md (expected at least 4)"
elif [ "${#HOOKS_MISSING[@]}" -eq 0 ]; then
  pass "$HOOKS_CHECKED distinct hooks/*.sh references all resolve to real files"
else
  fail "missing hook files: ${HOOKS_MISSING[*]}"
fi

hdr "STEP 6: scripts/<name>.sh references resolve"
# Two valid locations: skill-bundled (skills/onboard/scripts/, e.g. mirror-hooks.sh)
# and repo-root utilities (scripts/, e.g. validate-state.sh / verify-counts.sh /
# release-preflight.sh — maintainer tools, not shipped with installed skill).
SCRIPTS_MISSING=()
SCRIPTS_CHECKED=0
while IFS= read -r ref; do
  SCRIPTS_CHECKED=$((SCRIPTS_CHECKED+1))
  name="${ref#scripts/}"
  if [ -f "$SCRIPTS_DIR/$name" ] || [ -f "$SOURCE_REPO/scripts/$name" ]; then
    :
  else
    SCRIPTS_MISSING+=("$ref")
  fi
done < <(grep -oE 'scripts/[a-z-]+\.sh' "$SKILL" | sort -u)
if [ "$SCRIPTS_CHECKED" -eq 0 ]; then
  fail "no scripts/*.sh references found in SKILL.md"
elif [ "${#SCRIPTS_MISSING[@]}" -eq 0 ]; then
  pass "$SCRIPTS_CHECKED distinct scripts/*.sh references all resolve (skill-bundled or repo-root)"
else
  fail "missing script files: ${SCRIPTS_MISSING[*]}"
fi

hdr "STEP 7: 4 required hooks all referenced"
REQUIRED_HOOKS=(guard-bash.sh guard-edit.sh post-edit-check.sh stop-verify.sh)
UNREFERENCED=()
for h in "${REQUIRED_HOOKS[@]}"; do
  if ! grep -qE "hooks/$h" "$SKILL"; then
    UNREFERENCED+=("$h")
  fi
done
if [ "${#UNREFERENCED[@]}" -eq 0 ]; then
  pass "all 4 required hooks referenced in SKILL.md"
else
  fail "required hooks not referenced: ${UNREFERENCED[*]}"
fi

hdr "STEP 8: v3.0 sub-file split contract (元规则 27)"
# Sub-file existence
for sub in "${SUB_FILES[@]}"; do
  if [ -f "$SOURCE_REPO/skills/onboard/$sub" ]; then
    pass "sub-file exists: skills/onboard/$sub"
  else
    fail "sub-file missing: skills/onboard/$sub"
  fi
done
# Each sub-file has frontmatter prose ("本文件是 SKILL.md")
for sub in "${SUB_FILES[@]}"; do
  if head -10 "$SOURCE_REPO/skills/onboard/$sub" 2>/dev/null | grep -qE '^> 本文件是 SKILL\.md'; then
    pass "sub-file has frontmatter prose: $sub"
  else
    fail "sub-file missing frontmatter '本文件是 SKILL.md ...' prose: $sub"
  fi
done
# SKILL.md sentinel block links each sub-file
for sub in "${SUB_FILES[@]}"; do
  if grep -qE "$(echo "$sub" | sed 's/\./\\./g')" "$SKILL"; then
    pass "SKILL.md sentinel links sub-file: $sub"
  else
    fail "SKILL.md missing sentinel link to: $sub"
  fi
done
# SKILL.md sentinel headers preserved at known anchor names
for h in '^## Phase 7 · Claude Code Hooks' '^## Uninstall Mode' '^## 状态文件结构'; do
  hits=$(grep -cE "$h" "$SKILL")
  if [ "$hits" -eq 1 ]; then
    pass "SKILL.md sentinel header (exactly 1 hit): $h"
  else
    fail "SKILL.md sentinel header count != 1 (got $hits): $h"
  fi
done

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ skillmd-links surfaced FAILURES.')"
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
