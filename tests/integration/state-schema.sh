#!/usr/bin/env bash
# Tests scripts/validate-state.sh — the C2 runtime state-machine validator
# (audit Critical #2: spec was state machine on paper but not in code).
#
# Coverage:
#   - VALID fixture: every required field, mode+params consistent, phase
#     status enum all good → exit 0
#   - MISSING_VERSION: top-level field absence → exit 1, reason cited
#   - BAD_MODE: mode='something-else' → exit 1
#   - PARAMS_BOTH_TRUE: params.local_only=true AND params.share=true → exit 1
#   - PARAMS_BOTH_FALSE: neither true → exit 1
#   - MODE_MISMATCH: mode='share' but params.share=false → exit 1
#   - BAD_PHASE_STATUS: phases.3.status='completed' (not in allowed enum) → exit 1
#   - STACKS_NOT_ARRAY: stacks: {} → exit 1
#   - INVALID_JSON: malformed JSON → exit 1
#   - AUTO_FIND: invoked without arg from a project root with state file
#     in .claude/local-only/ → finds it

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$SOURCE_REPO/scripts/validate-state.sh"
SANDBOX="${SANDBOX:-/tmp/onboard-state-schema-sandbox}"
PASS=0
FAIL=0

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "  $(c '1;32' '✓ PASS') $*"; PASS=$((PASS+1)); }
fail() { echo "  $(c '1;31' '✗ FAIL') $*"; FAIL=$((FAIL+1)); }
hdr()  { echo ""; echo "$(c '1;36' "═══ $* ═══")"; }

if [ ! -f "$VALIDATOR" ]; then
  echo "ERROR: validator not found at $VALIDATOR" >&2
  exit 2
fi

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

# ──────────────────────────────────────────────────────────────────────────
# Fixture: minimal valid state file (mode=local-only, all required fields)
# ──────────────────────────────────────────────────────────────────────────
make_valid_state() {
  cat > "$1" <<'EOF'
{
  "version": "2.12.0",
  "mode": "local-only",
  "started_at": "2026-05-18T12:00:00Z",
  "params": {
    "dry_run": false,
    "strict": false,
    "update": false,
    "local_only": true,
    "share": false
  },
  "git_topology": {
    "is_submodule": false,
    "is_bare": false,
    "is_detached": false,
    "is_shallow": false,
    "is_worktree": false
  },
  "team_signals": {
    "score": 0,
    "classification": "solo"
  },
  "git_host": {
    "platform": "github",
    "cli_available": true
  },
  "stacks": [
    {
      "id": "ts-web",
      "language": "TypeScript",
      "paths": ["apps/web"]
    }
  ],
  "confirmed_forbidden_zones": ["packages/legacy-core"],
  "phases": {
    "0": { "status": "done" },
    "1": { "status": "done" },
    "3": { "status": "skipped" },
    "7": { "status": "deferred" }
  }
}
EOF
}

VALID="$SANDBOX/valid.json"
make_valid_state "$VALID"

hdr "VALID fixture → exit 0"
if bash "$VALIDATOR" "$VALID" >"$SANDBOX/valid.out" 2>&1; then
  pass "valid state exits 0"
else
  fail "valid state should exit 0, got $? (output: $(cat "$SANDBOX/valid.out"))"
fi
if grep -q '✓ state schema valid' "$SANDBOX/valid.out"; then
  pass "valid state prints success summary"
else
  fail "valid state missing success summary (output: $(cat "$SANDBOX/valid.out"))"
fi

hdr "MISSING_VERSION → exit 1"
MV="$SANDBOX/missing-version.json"
jq 'del(.version)' "$VALID" > "$MV"
if bash "$VALIDATOR" "$MV" >"$SANDBOX/mv.out" 2>"$SANDBOX/mv.err"; then
  fail "missing version should exit 1, got 0"
else
  pass "missing version exits non-zero"
fi
if grep -q "missing required top-level field: version" "$SANDBOX/mv.err"; then
  pass "missing version cites field by name in stderr"
else
  fail "missing version stderr does NOT cite field (got: $(cat "$SANDBOX/mv.err"))"
fi

hdr "BAD_MODE → exit 1"
BM="$SANDBOX/bad-mode.json"
jq '.mode = "production"' "$VALID" > "$BM"
if bash "$VALIDATOR" "$BM" >"$SANDBOX/bm.out" 2>"$SANDBOX/bm.err"; then
  fail "bad mode should exit 1"
else
  pass "bad mode exits non-zero"
fi
grep -q "mode must be 'local-only' or 'share'" "$SANDBOX/bm.err" \
  && pass "bad mode stderr cites allowed enum" \
  || fail "bad mode stderr missing enum hint (got: $(cat "$SANDBOX/bm.err"))"

hdr "PARAMS_BOTH_TRUE → exit 1 (mutex broken)"
PT="$SANDBOX/both-true.json"
jq '.params.local_only = true | .params.share = true' "$VALID" > "$PT"
if bash "$VALIDATOR" "$PT" >"$SANDBOX/pt.out" 2>"$SANDBOX/pt.err"; then
  fail "params both true should exit 1"
else
  pass "params both true exits non-zero"
fi
grep -q "mutually exclusive" "$SANDBOX/pt.err" \
  && pass "mutex violation explicitly named" \
  || fail "mutex violation NOT named (got: $(cat "$SANDBOX/pt.err"))"

hdr "PARAMS_BOTH_FALSE → exit 1"
PF="$SANDBOX/both-false.json"
jq '.params.local_only = false | .params.share = false' "$VALID" > "$PF"
if bash "$VALIDATOR" "$PF" >"$SANDBOX/pf.out" 2>"$SANDBOX/pf.err"; then
  fail "params both false should exit 1"
else
  pass "params both false exits non-zero"
fi

hdr "MODE_MISMATCH → exit 1 (mode=share but params.share=false)"
MM="$SANDBOX/mode-mismatch.json"
jq '.mode = "share"' "$VALID" > "$MM"
# Now mode=share but params.local_only still true & params.share still false
if bash "$VALIDATOR" "$MM" >"$SANDBOX/mm.out" 2>"$SANDBOX/mm.err"; then
  fail "mode/params mismatch should exit 1"
else
  pass "mode/params mismatch exits non-zero"
fi
grep -q "mode='share' but params.share is not true" "$SANDBOX/mm.err" \
  && pass "mode mismatch precisely named" \
  || fail "mode mismatch error message imprecise (got: $(cat "$SANDBOX/mm.err"))"

hdr "BAD_PHASE_STATUS → exit 1 ('completed' not in allowed enum)"
BPS="$SANDBOX/bad-phase.json"
jq '.phases."3".status = "completed"' "$VALID" > "$BPS"
if bash "$VALIDATOR" "$BPS" >"$SANDBOX/bps.out" 2>"$SANDBOX/bps.err"; then
  fail "bad phase status should exit 1"
else
  pass "bad phase status exits non-zero"
fi
grep -q "phases.3.status = 'completed' not in allowed enum" "$SANDBOX/bps.err" \
  && pass "bad phase status cites phase + value" \
  || fail "bad phase status message imprecise (got: $(cat "$SANDBOX/bps.err"))"

hdr "STACKS_NOT_ARRAY → exit 1"
SNA="$SANDBOX/stacks-obj.json"
jq '.stacks = {}' "$VALID" > "$SNA"
if bash "$VALIDATOR" "$SNA" >"$SANDBOX/sna.out" 2>"$SANDBOX/sna.err"; then
  fail "stacks=object should exit 1"
else
  pass "stacks=object exits non-zero"
fi
grep -q "stacks must be array" "$SANDBOX/sna.err" \
  && pass "stacks-type error cites expected type" \
  || fail "stacks-type error imprecise (got: $(cat "$SANDBOX/sna.err"))"

hdr "INVALID_JSON → exit 1"
IJ="$SANDBOX/invalid.json"
echo "not valid json" > "$IJ"
if bash "$VALIDATOR" "$IJ" >"$SANDBOX/ij.out" 2>"$SANDBOX/ij.err"; then
  fail "invalid JSON should exit 1"
else
  pass "invalid JSON exits non-zero"
fi
grep -q "not valid JSON" "$SANDBOX/ij.err" \
  && pass "invalid JSON cited" \
  || fail "invalid JSON message missing (got: $(cat "$SANDBOX/ij.err"))"

hdr "AUTO_FIND from project root (local-only path)"
AF="$SANDBOX/auto-find"
mkdir -p "$AF/.claude/local-only"
make_valid_state "$AF/.claude/local-only/onboarding-state.json"
pushd "$AF" >/dev/null
if bash "$VALIDATOR" >"$SANDBOX/af.out" 2>&1; then
  pass "auto-find from PWD locates .claude/local-only/onboarding-state.json"
else
  fail "auto-find should succeed (output: $(cat "$SANDBOX/af.out"))"
fi
popd >/dev/null
grep -q "valid JSON" "$SANDBOX/af.out" \
  && pass "auto-find ran full validation pipeline" \
  || fail "auto-find didn't run validation (output: $(cat "$SANDBOX/af.out"))"

hdr "NO_ARG + NO_STATE_FILE → exit 2 (invocation error)"
EMPTY="$SANDBOX/empty-dir"
mkdir -p "$EMPTY"
pushd "$EMPTY" >/dev/null
if bash "$VALIDATOR" >"$SANDBOX/noarg.out" 2>&1; then
  fail "no-arg-no-file should exit 2"
else
  rc=$?
  [ "$rc" = "2" ] && pass "no-arg-no-file exits 2 (invocation err)" \
    || fail "no-arg-no-file exit != 2 (got $rc)"
fi
popd >/dev/null

hdr "BAD_VERSION_FORMAT → exit 1"
BV="$SANDBOX/bad-version.json"
jq '.version = "v2"' "$VALID" > "$BV"
if bash "$VALIDATOR" "$BV" >"$SANDBOX/bv.out" 2>"$SANDBOX/bv.err"; then
  fail "bad version format should exit 1"
else
  pass "bad version format exits non-zero"
fi

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ state-schema surfaced FAILURES.')"
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
