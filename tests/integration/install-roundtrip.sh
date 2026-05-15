#!/usr/bin/env bash
# Tests install.sh universal installer round-trip:
#   1. fresh install: dest populated, hooks +x, scripts +x, stage has .git
#   2. install-when-installed: warns + exits 0 (no clobber)
#   3. doctor on installed: exit 0, prints version + 4/4 hooks
#   4. update: drift in INSTALL_DIR gets overwritten from stage
#   5. uninstall: INSTALL_DIR + STAGE_DIR removed (ONBOARD_CONFIRM_UNINSTALL=yes)
#   6. doctor on uninstalled: exit 0, prints "not installed"
#   7. re-install after uninstall: round-trip works
#   8. error paths: invalid ONBOARD_TARGET, invalid action → exit 2
#
# Sandbox: $HOME redirected to $SANDBOX/fake-home; source repo cloned via
# file:// URL into the sandbox-side stage, so $SOURCE_REPO is never written to.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$SOURCE_REPO/install.sh"
SANDBOX="${SANDBOX:-/tmp/onboard-install-sandbox}"
PASS=0
FAIL=0

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "  $(c '1;32' '✓ PASS') $*"; PASS=$((PASS+1)); }
fail() { echo "  $(c '1;31' '✗ FAIL') $*"; FAIL=$((FAIL+1)); }
info() { echo "$(c '1;34' '[step]') $*"; }
hdr()  { echo ""; echo "$(c '1;36' "═══ $* ═══")"; }

if [ ! -f "$INSTALL_SH" ]; then
  echo "ERROR: install.sh not found at $INSTALL_SH" >&2
  exit 2
fi

for cmd in jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not on PATH" >&2
    exit 2
  fi
done

echo "Source repo:  $SOURCE_REPO"
echo "install.sh:   $INSTALL_SH"
echo "Sandbox root: $SANDBOX"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

FAKE_HOME="$SANDBOX/fake-home"
mkdir -p "$FAKE_HOME"

INSTALL_DIR="$FAKE_HOME/.claude/skills/onboard"
STAGE_DIR="$FAKE_HOME/.claude/.cache/onboard-source"

# Run install.sh under a sandboxed HOME, cloning from local repo via file://
# so the test doesn't hit the network and doesn't depend on github state.
run_installer() {
  HOME="$FAKE_HOME" \
  ONBOARD_REPO="file://$SOURCE_REPO" \
  ONBOARD_BRANCH=main \
  ONBOARD_TARGET=user \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_SYSTEM=/dev/null \
  bash "$INSTALL_SH" "$@"
}

hdr "STEP 1: fresh install"
info "running: install.sh install (HOME=$FAKE_HOME, repo=file://$SOURCE_REPO)"
if run_installer install >"$SANDBOX/install.log" 2>&1; then
  pass "fresh install exits 0"
else
  fail "fresh install failed (exit $?). log: $SANDBOX/install.log"
  cat "$SANDBOX/install.log" >&2
  exit 1
fi

[ -d "$INSTALL_DIR" ] && pass "INSTALL_DIR created" || fail "INSTALL_DIR not created at $INSTALL_DIR"
[ -f "$INSTALL_DIR/SKILL.md" ] && pass "SKILL.md present in INSTALL_DIR" || fail "SKILL.md missing"
[ -d "$STAGE_DIR/.git" ] && pass "STAGE_DIR has .git (re-clonable)" || fail "STAGE_DIR/.git missing"

# 4 hooks, all +x
HOOK_X_COUNT=$(find "$INSTALL_DIR/hooks" -maxdepth 1 -name '*.sh' -perm -u+x 2>/dev/null | wc -l | tr -d ' ')
[ "$HOOK_X_COUNT" = "4" ] && pass "4/4 hooks executable" || fail "hooks executable count != 4 (got $HOOK_X_COUNT)"

# scripts/mirror-hooks.sh +x (v2.10.1+)
if [ -x "$INSTALL_DIR/scripts/mirror-hooks.sh" ]; then
  pass "scripts/mirror-hooks.sh executable"
else
  fail "scripts/mirror-hooks.sh missing or not +x"
fi

# Version detected from SKILL.md
INSTALLED_V=$(grep -E "^# /onboard.*\(v[0-9]" "$INSTALL_DIR/SKILL.md" | head -1 | sed -E 's/.*\(v([0-9.]+).*/\1/' || echo "")
if [ -n "$INSTALLED_V" ]; then
  pass "version detected from installed SKILL.md: v$INSTALLED_V"
else
  fail "could not detect version from installed SKILL.md"
fi

hdr "STEP 2: install when already installed"
if run_installer install >"$SANDBOX/install-second.log" 2>&1; then
  pass "second install exits 0 (no clobber)"
else
  fail "second install failed (exit $?)"
fi
if grep -q "already installed" "$SANDBOX/install-second.log"; then
  pass "second install warns 'already installed'"
else
  fail "second install missing 'already installed' warning"
fi

hdr "STEP 3: doctor on installed state"
if run_installer doctor >"$SANDBOX/doctor.log" 2>&1; then
  pass "doctor exits 0 on installed state"
else
  fail "doctor failed (exit $?)"
fi
if grep -q "installed   v" "$SANDBOX/doctor.log"; then
  pass "doctor reports installed version"
else
  fail "doctor missing version line"
fi
if grep -qE "hooks exec    4/4" "$SANDBOX/doctor.log"; then
  pass "doctor reports 4/4 hooks executable"
else
  fail "doctor hooks exec line missing or wrong"
  grep -E "hooks exec" "$SANDBOX/doctor.log" >&2 || true
fi

hdr "STEP 4: update overwrites drift in INSTALL_DIR"
# Simulate drift: corrupt an installed hook
DRIFT_FILE="$INSTALL_DIR/hooks/guard-bash.sh"
ORIG_SHA=$(sha256sum "$DRIFT_FILE" | cut -d' ' -f1)
echo "# drift injected by test" >>"$DRIFT_FILE"
DRIFTED_SHA=$(sha256sum "$DRIFT_FILE" | cut -d' ' -f1)
[ "$ORIG_SHA" != "$DRIFTED_SHA" ] && pass "drift injected (sha changed)" || fail "drift inject failed (sha unchanged)"

if run_installer update >"$SANDBOX/update.log" 2>&1; then
  pass "update exits 0"
else
  fail "update failed (exit $?). log: $SANDBOX/update.log"
  cat "$SANDBOX/update.log" >&2
fi
RECOVERED_SHA=$(sha256sum "$DRIFT_FILE" | cut -d' ' -f1)
if [ "$RECOVERED_SHA" = "$ORIG_SHA" ]; then
  pass "update overwrote drifted hook (sha matches pre-drift)"
else
  fail "update did not overwrite drift (sha still=$RECOVERED_SHA, expected=$ORIG_SHA)"
fi

hdr "STEP 5: uninstall (ONBOARD_CONFIRM_UNINSTALL=yes)"
if HOME="$FAKE_HOME" ONBOARD_CONFIRM_UNINSTALL=yes \
   GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
   bash "$INSTALL_SH" uninstall </dev/null >"$SANDBOX/uninstall.log" 2>&1; then
  pass "uninstall exits 0"
else
  fail "uninstall failed (exit $?). log: $SANDBOX/uninstall.log"
fi
[ ! -d "$INSTALL_DIR" ] && pass "INSTALL_DIR removed" || fail "INSTALL_DIR still exists"
[ ! -d "$STAGE_DIR" ] && pass "STAGE_DIR removed" || fail "STAGE_DIR still exists"

hdr "STEP 6: doctor on uninstalled state"
if run_installer doctor >"$SANDBOX/doctor-empty.log" 2>&1; then
  pass "doctor on uninstalled state exits 0"
else
  fail "doctor on uninstalled state failed (exit $?)"
fi
if grep -q "not installed" "$SANDBOX/doctor-empty.log"; then
  pass "doctor reports 'not installed'"
else
  fail "doctor missing 'not installed' message"
fi

hdr "STEP 7: re-install after uninstall (full round-trip)"
if run_installer install >"$SANDBOX/reinstall.log" 2>&1; then
  pass "re-install after uninstall exits 0"
else
  fail "re-install failed (exit $?). log: $SANDBOX/reinstall.log"
fi
[ -f "$INSTALL_DIR/SKILL.md" ] && pass "re-install: SKILL.md present" || fail "re-install: SKILL.md missing"
REINSTALL_X_COUNT=$(find "$INSTALL_DIR/hooks" -maxdepth 1 -name '*.sh' -perm -u+x 2>/dev/null | wc -l | tr -d ' ')
[ "$REINSTALL_X_COUNT" = "4" ] && pass "re-install: 4/4 hooks executable" || fail "re-install: hooks count != 4 (got $REINSTALL_X_COUNT)"

hdr "STEP 8: error paths"
# Invalid ONBOARD_TARGET
if HOME="$FAKE_HOME" ONBOARD_TARGET=bogus \
   GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
   bash "$INSTALL_SH" install >"$SANDBOX/bad-target.log" 2>&1; then
  fail "invalid ONBOARD_TARGET should exit non-zero"
else
  rc=$?
  [ "$rc" = "2" ] && pass "invalid ONBOARD_TARGET exits 2" || fail "invalid ONBOARD_TARGET exit code != 2 (got $rc)"
fi

# Invalid action
if HOME="$FAKE_HOME" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
   bash "$INSTALL_SH" bogus-action >"$SANDBOX/bad-action.log" 2>&1; then
  fail "invalid action should exit non-zero"
else
  rc=$?
  [ "$rc" = "2" ] && pass "invalid action exits 2" || fail "invalid action exit code != 2 (got $rc)"
fi

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ install-roundtrip surfaced FAILURES.')"
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
