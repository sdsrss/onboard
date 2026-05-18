#!/usr/bin/env bash
# release-preflight.sh — runs three pre-commit hygiene checks bundled
# together. Built from three feedback memories that each captured a separate
# class of release-time drift in /onboard v2.10.x → v2.11.x:
#
#   1. feedback_cross_cutting_grep.md  →  bumped version label sometimes
#      gets left behind in docs / templates / settings _comment
#   2. feedback_git_index_chmod_on_new_sh.md  →  new .sh files added in a
#      release commit consistently land with git index mode 100644 (FS
#      mode +x doesn't propagate); needs explicit `git update-index --chmod=+x`
#   3. (and) `scripts/verify-counts.sh` — actual `tests/integration/*.sh`
#      pass counts vs CLAUDE.md + CHANGELOG claims
#
# Plus a fourth: staged-file sanity (warn on working-tree-only diffs or
# untracked files that the next `git commit` would silently miss).
#
# Usage:
#   bash scripts/release-preflight.sh                  # auto-derives NEW + OLD
#   bash scripts/release-preflight.sh 2.11.1           # OLD_VERSION explicit
#   bash scripts/release-preflight.sh 2.11.1 2.11.2    # both explicit
#
# Position in workflow: run AFTER `git add -A`, BEFORE `git commit`.
# The chmod step mutates the git index, so staging must happen first.
#
# Exit:
#   0 = ready to commit (informational warnings may still print)
#   1 = blocking drift (verify-counts mismatch, version-bump incomplete)
#   2 = invocation / parse error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "$(c '1;32' '✓') $*"; }
fail() { echo "$(c '1;31' '✗') $*" >&2; }
warn() { echo "$(c '1;33' '!') $*" >&2; }
info() { echo "$(c '1;34' '[preflight]') $*"; }
hdr()  { echo ""; echo "$(c '1;36' "═══ $* ═══")"; }

# Derive NEW_VERSION (current after bump) from plugin.json.
NEW_VERSION="$(jq -r '.version' .claude-plugin/plugin.json 2>/dev/null || echo "")"
if [ -z "$NEW_VERSION" ] || [ "$NEW_VERSION" = "null" ]; then
  fail "could not read .claude-plugin/plugin.json version"
  exit 2
fi

# Derive OLD_VERSION: optional arg 1, else parse from CHANGELOG.md (second
# `## v` header — the one PRIOR to the current section being committed).
OLD_VERSION="${1:-}"
if [ -z "$OLD_VERSION" ]; then
  OLD_VERSION="$(awk '
    /^## v/{c++; if(c==2){sub(/^## v/,""); split($0,a," "); print a[1]; exit}}
  ' CHANGELOG.md)"
fi

# NEW_VERSION can also be overridden via arg 2 (rarely needed).
NEW_VERSION="${2:-$NEW_VERSION}"

info "NEW_VERSION: $NEW_VERSION"
info "OLD_VERSION: ${OLD_VERSION:-<unknown>}"

BLOCKING=0
WARNINGS=0

# ──────────────────────────────────────────────────────────────────────────
# Step 1: version-bump completeness — current-state pinned locations must
# show NEW_VERSION, not OLD_VERSION. Positive check (avoids the false-positive
# spiral of pure grep against OLD_VERSION since historical refs are legitimate).
# ──────────────────────────────────────────────────────────────────────────
hdr "Step 1: version-bump completeness"

# Each entry: <file>::<grep-pattern-that-must-match>
#   - The pattern is a regex that MUST appear in the file with NEW_VERSION substituted.
#   - "$V" placeholder is replaced with NEW_VERSION at check time.
PIN_RULES=(
  '.claude-plugin/plugin.json::"version": "$V"'
  '.claude-plugin/marketplace.json::"version": "$V"'
  'skills/onboard/SKILL.md::^# /onboard.*\(v$V\)'
  'skills/onboard/settings.template.json::"_onboard_version": "$V"'
  'skills/onboard/settings.local.template.json::"_onboard_version": "$V"'
  'CLAUDE.md::current version: v$V'
  'README.md::Current version: \*\*v$V\*\*'
  'README.zh-CN.md::当前版本：\*\*v$V\*\*'
)

for rule in "${PIN_RULES[@]}"; do
  file="${rule%%::*}"
  pat="${rule#*::}"
  pat="${pat//\$V/$NEW_VERSION}"
  if [ ! -f "$file" ]; then
    fail "pin-check file missing: $file"
    BLOCKING=1
    continue
  fi
  if grep -qE "$pat" "$file"; then
    pass "$file → matches NEW_VERSION pin"
  else
    fail "$file → does NOT match pattern '$pat' (likely needs bump from $OLD_VERSION → $NEW_VERSION)"
    BLOCKING=1
  fi
done

# Informational grep for OLD_VERSION in current-state files. CHANGELOG.md
# entries about prior versions are excluded by convention.
if [ -n "$OLD_VERSION" ]; then
  hdr "Step 1b: informational OLD_VERSION grep (CHANGELOG excluded)"
  STALE="$(grep -rnE "v?$OLD_VERSION([^0-9]|$)" \
    --include='*.md' --include='*.sh' --include='*.json' \
    --exclude-dir='.git' --exclude='CHANGELOG.md' . 2>/dev/null || true)"
  if [ -z "$STALE" ]; then
    pass "no $OLD_VERSION references outside CHANGELOG"
  else
    LINE_COUNT="$(echo "$STALE" | wc -l | tr -d ' ')"
    warn "$LINE_COUNT lingering '$OLD_VERSION' refs — review each (historical facts like 'vX.Y added Z' are usually OK):"
    echo "$STALE" | sed 's/^/  /' >&2
    WARNINGS=$((WARNINGS+1))
  fi
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 2: chmod +x on newly-added .sh files in the index
# ──────────────────────────────────────────────────────────────────────────
hdr "Step 2: git index +x on newly-added .sh files"

NEW_SH="$(git diff --cached --name-only --diff-filter=A 2>/dev/null | grep '\.sh$' || true)"
if [ -z "$NEW_SH" ]; then
  info "no new .sh files in staging — skipping chmod step"
else
  NEEDED=0
  while IFS= read -r f; do
    mode="$(git ls-files --stage -- "$f" 2>/dev/null | awk '{print $1}')"
    if [ "$mode" = "100644" ]; then
      info "  upgrading $f: 100644 → 100755"
      git update-index --chmod=+x "$f"
      NEEDED=1
    else
      pass "  $f already 100755"
    fi
  done <<<"$NEW_SH"
  if [ "$NEEDED" -eq 1 ]; then
    info "ran git update-index --chmod=+x — re-stage NOT needed; commit will carry the new mode"
  fi
fi

# Also catch mode-only changes to existing .sh that crept in:
MODE_CHANGED="$(git diff --cached --summary 2>/dev/null | grep 'mode change' || true)"
if [ -n "$MODE_CHANGED" ]; then
  info "existing mode changes already staged:"
  echo "$MODE_CHANGED" | sed 's/^/  /'
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 3: verify-counts.sh (blocking)
# ──────────────────────────────────────────────────────────────────────────
hdr "Step 3: verify-counts.sh"

if [ ! -x "$SCRIPT_DIR/verify-counts.sh" ] && [ ! -f "$SCRIPT_DIR/verify-counts.sh" ]; then
  warn "scripts/verify-counts.sh missing — skipping count check (consider adding it)"
  WARNINGS=$((WARNINGS+1))
else
  if bash "$SCRIPT_DIR/verify-counts.sh" >/tmp/onboard-preflight-verify.log 2>&1; then
    pass "verify-counts.sh all green"
  else
    fail "verify-counts.sh reported drift:"
    cat /tmp/onboard-preflight-verify.log >&2
    BLOCKING=1
  fi
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 4: staged-file sanity — warn on working-tree-only edits or untracked.
# These won't fail the preflight but the user usually wants to know.
# ──────────────────────────────────────────────────────────────────────────
hdr "Step 4: staged-file sanity"

STATUS="$(git status --short 2>/dev/null || true)"
WT_ONLY="$(echo "$STATUS" | grep -E '^.[MD]' || true)"
UNTRACKED="$(echo "$STATUS" | grep -E '^\?\?' || true)"

if [ -z "$STATUS" ]; then
  info "nothing staged — preflight running on a clean tree?"
else
  STAGED_COUNT="$(echo "$STATUS" | grep -cE '^[MAD]' || true)"
  info "staged entries: $STAGED_COUNT"
fi

if [ -n "$WT_ONLY" ]; then
  warn "working-tree-only edits (NOT in next commit unless you re-stage):"
  echo "$WT_ONLY" | sed 's/^/  /' >&2
  WARNINGS=$((WARNINGS+1))
fi
if [ -n "$UNTRACKED" ]; then
  warn "untracked files (NOT in next commit unless added):"
  echo "$UNTRACKED" | sed 's/^/  /' >&2
  WARNINGS=$((WARNINGS+1))
fi

# ──────────────────────────────────────────────────────────────────────────
# FINAL
# ──────────────────────────────────────────────────────────────────────────
hdr "FINAL"

if [ "$BLOCKING" -ne 0 ]; then
  fail "BLOCKING issues — do NOT commit until resolved"
  exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo "$(c '1;33' "⚠ preflight passed with $WARNINGS warning(s) — review above before commit")"
else
  echo "$(c '1;32' '✓ preflight all green — ready to commit')"
fi
exit 0
