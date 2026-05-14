#!/usr/bin/env bash
# Tests skills/onboard/scripts/mirror-hooks.sh:
#   1. script exists + executable
#   2. fresh mirror: dest created, 4 hooks present, manifest written
#   3. all 4 mirrored hooks have +x
#   4. manifest is valid JSON with version/source/dest/mirrored_at/hooks
#   5. idempotency: re-run from same source → hook content unchanged
#   6. plugin-update simulation: re-run from a different source path → manifest.source updates
#   7. auto-detect: invoke without ONBOARD_MIRROR_SOURCE → uses script-sibling hooks/
#   8. error: missing source dir → exit non-zero
#   9. error: source dir missing a required hook → exit non-zero

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIRROR_SCRIPT="$SOURCE_REPO/skills/onboard/scripts/mirror-hooks.sh"
REAL_HOOKS="$SOURCE_REPO/skills/onboard/hooks"
SANDBOX="${SANDBOX:-/tmp/onboard-mirror-sandbox}"
PASS=0
FAIL=0

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "  $(c '1;32' '✓ PASS') $*"; PASS=$((PASS+1)); }
fail() { echo "  $(c '1;31' '✗ FAIL') $*"; FAIL=$((FAIL+1)); }
info() { echo "$(c '1;34' '[step]') $*"; }
hdr()  { echo ""; echo "$(c '1;36' "═══ $* ═══")"; }

# Portability: GNU coreutils ships `sha256sum`; macOS ships `shasum -a 256`.
# Output format is identical (`<hash>  <filename>`), so cut -d' ' -f1 works for both.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum
  else shasum -a 256
  fi
}

echo "Source repo:   $SOURCE_REPO"
echo "Mirror script: $MIRROR_SCRIPT"
echo "Sandbox root:  $SANDBOX"

hdr "STEP 0: script smoke"
if [ -f "$MIRROR_SCRIPT" ]; then pass "mirror-hooks.sh exists"; else fail "mirror-hooks.sh missing"; exit 1; fi
if [ -x "$MIRROR_SCRIPT" ]; then pass "mirror-hooks.sh executable"; else fail "mirror-hooks.sh not executable"; fi
bash -n "$MIRROR_SCRIPT" && pass "mirror-hooks.sh syntax OK" || fail "mirror-hooks.sh syntax error"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

# Simulate two ephemeral plugin-cache snapshots with same content (different paths)
SNAP1="$SANDBOX/plugin-cache/abc/skills/onboard/hooks"
SNAP2="$SANDBOX/plugin-cache/xyz/skills/onboard/hooks"
mkdir -p "$SNAP1" "$SNAP2"
cp "$REAL_HOOKS"/*.sh "$SNAP1/"
cp "$REAL_HOOKS"/*.sh "$SNAP2/"
chmod +x "$SNAP1"/*.sh "$SNAP2"/*.sh

DEST="$SANDBOX/runtime/hooks"
MANIFEST="$SANDBOX/runtime/.mirror-manifest.json"

hdr "STEP 1: fresh mirror from SNAP1"
if ONBOARD_MIRROR_SOURCE="$SNAP1" ONBOARD_MIRROR_DEST="$DEST" "$MIRROR_SCRIPT" >/dev/null 2>&1; then
  pass "exit 0 on fresh mirror"
else
  fail "fresh mirror failed (exit $?)"
fi

[ -d "$DEST" ] && pass "dest dir created" || fail "dest dir not created"
[ -f "$MANIFEST" ] && pass "manifest written at $(basename "$MANIFEST")" || fail "manifest not written"

for h in guard-bash.sh guard-edit.sh post-edit-check.sh stop-verify.sh; do
  [ -f "$DEST/$h" ] && pass "hook present: $h" || fail "hook missing: $h"
  [ -x "$DEST/$h" ] && pass "hook executable: $h" || fail "hook not executable: $h"
done

hdr "STEP 2: manifest schema"
if jq empty "$MANIFEST" 2>/dev/null; then
  pass "manifest is valid JSON"
else
  fail "manifest is not valid JSON"
fi

for field in version source dest mirrored_at; do
  v=$(jq -r --arg f "$field" '.[$f] // ""' "$MANIFEST" 2>/dev/null)
  [ -n "$v" ] && pass "manifest.$field present: $v" || fail "manifest.$field missing"
done

hooks_count=$(jq -r '.hooks | length' "$MANIFEST" 2>/dev/null)
[ "$hooks_count" = "4" ] && pass "manifest.hooks has 4 entries" || fail "manifest.hooks count != 4 (got $hooks_count)"

hdr "STEP 3: idempotency (same SOURCE, second invocation)"
HOOKS_SHA_BEFORE=$(find "$DEST" -type f -name '*.sh' | sort | xargs cat | sha256_of | cut -d' ' -f1)
ONBOARD_MIRROR_SOURCE="$SNAP1" ONBOARD_MIRROR_DEST="$DEST" "$MIRROR_SCRIPT" >/dev/null 2>&1
HOOKS_SHA_AFTER=$(find "$DEST" -type f -name '*.sh' | sort | xargs cat | sha256_of | cut -d' ' -f1)
if [ "$HOOKS_SHA_BEFORE" = "$HOOKS_SHA_AFTER" ]; then
  pass "hook content sha256 unchanged on re-run"
else
  fail "hook content differs on re-run (before=$HOOKS_SHA_BEFORE after=$HOOKS_SHA_AFTER)"
fi

hdr "STEP 4: plugin-update simulation (new ephemeral path, same content)"
PREV_SOURCE=$(jq -r '.source' "$MANIFEST")
[ "$PREV_SOURCE" = "$SNAP1" ] && pass "pre-update manifest.source = SNAP1" || fail "pre-update manifest.source mismatch (got $PREV_SOURCE)"

ONBOARD_MIRROR_SOURCE="$SNAP2" ONBOARD_MIRROR_DEST="$DEST" "$MIRROR_SCRIPT" >/dev/null 2>&1
NEW_SOURCE=$(jq -r '.source' "$MANIFEST")
[ "$NEW_SOURCE" = "$SNAP2" ] && pass "post-update manifest.source updated to SNAP2" || fail "manifest.source did not update (got $NEW_SOURCE)"

hdr "STEP 5: auto-detect source from script-sibling hooks/"
DEST_AUTO="$SANDBOX/runtime-auto/hooks"
unset ONBOARD_MIRROR_SOURCE 2>/dev/null || true
if ONBOARD_MIRROR_DEST="$DEST_AUTO" "$MIRROR_SCRIPT" >/dev/null 2>&1; then
  pass "auto-detect mirror succeeded (no ONBOARD_MIRROR_SOURCE env)"
else
  fail "auto-detect mirror failed"
fi
[ -f "$DEST_AUTO/guard-bash.sh" ] && pass "auto-detect placed real hooks" || fail "auto-detect did not place hooks"

hdr "STEP 6: error paths"
if ONBOARD_MIRROR_SOURCE="$SANDBOX/nonexistent" ONBOARD_MIRROR_DEST="$DEST" "$MIRROR_SCRIPT" >/dev/null 2>&1; then
  fail "should exit non-zero on missing source dir"
else
  pass "exits non-zero on missing source dir"
fi

PARTIAL="$SANDBOX/partial/hooks"
mkdir -p "$PARTIAL"
cp "$REAL_HOOKS/guard-bash.sh" "$PARTIAL/"  # only 1 of 4
if ONBOARD_MIRROR_SOURCE="$PARTIAL" ONBOARD_MIRROR_DEST="$SANDBOX/runtime-partial/hooks" "$MIRROR_SCRIPT" >/dev/null 2>&1; then
  fail "should exit non-zero when source missing required hook"
else
  pass "exits non-zero when source missing required hook"
fi

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ Mirror test surfaced FAILURES.')"
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
