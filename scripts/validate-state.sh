#!/usr/bin/env bash
# validate-state.sh — schema validator for /onboard state files.
#
# Why this exists: SKILL.md:2317-2440 documents the state-file schema, but
# until now nothing actually enforced it at runtime. Consumer Claude could
# mark `phases.3.status: "done"` without producing any managed file and no
# script would surface the drift; only Doctor mode D1 grepped for "version"
# field existence. The audit (Critical C2) called this out: the spec is a
# state machine on paper but not in code. This script is the missing checker.
#
# What it validates (per SKILL.md state schema v2.9):
#   - JSON is well-formed
#   - Required top-level fields exist
#   - `mode` ∈ {local-only, share}
#   - `params.local_only` XOR `params.share` (exactly one)
#   - `mode` consistent with `params.{local_only, share}`
#   - Each `phases.<n>.status` is in the allowed enum
#   - `stacks` is an array, `confirmed_forbidden_zones` is an array
#   - `version` matches /^[0-9]+\.[0-9]+(\.[0-9]+)?$/
#
# Exit:
#   0 = state schema valid
#   1 = schema violations found (printed to stderr)
#   2 = invocation / parse error
#
# Usage:
#   bash scripts/validate-state.sh <state.json>
#   bash scripts/validate-state.sh                      # auto-find via PWD
#
# Auto-find paths (tried in order):
#   .claude/local-only/onboarding-state.json
#   .claude/onboarding-state.json

set -uo pipefail

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
ok()   { echo "  $(c '1;32' '✓') $*"; }
err()  { echo "  $(c '1;31' '✗') $*" >&2; ERR=1; }
info() { echo "$(c '1;34' '[validate-state]') $*"; }

STATE="${1:-}"
if [ -z "$STATE" ]; then
  for cand in .claude/local-only/onboarding-state.json .claude/onboarding-state.json; do
    if [ -f "$cand" ]; then STATE="$cand"; break; fi
  done
fi

if [ -z "$STATE" ]; then
  echo "usage: $0 <state.json>" >&2
  echo "  or run from a project root with an existing onboarding state file" >&2
  exit 2
fi
if [ ! -f "$STATE" ]; then
  echo "ERROR: state file not found: $STATE" >&2
  exit 2
fi

info "validating: $STATE"

if ! jq empty "$STATE" 2>/dev/null; then
  err "not valid JSON"
  echo "$(c '1;31' '✗ schema violations found')" >&2
  exit 1
fi
ok "valid JSON"

ERR=0

# ──────────────────────────────────────────────────────────────────────────
# Required top-level fields (SKILL.md:2323-2380)
# ──────────────────────────────────────────────────────────────────────────
REQUIRED_TOP=(version mode started_at params git_topology team_signals git_host stacks phases)
for f in "${REQUIRED_TOP[@]}"; do
  v=$(jq --arg f "$f" 'has($f)' "$STATE")
  if [ "$v" = "true" ]; then
    ok "field present: $f"
  else
    err "missing required top-level field: $f"
  fi
done

# ──────────────────────────────────────────────────────────────────────────
# version pattern
# ──────────────────────────────────────────────────────────────────────────
VER=$(jq -r '.version // empty' "$STATE")
if [ -z "$VER" ]; then
  err "version missing or empty"
elif ! echo "$VER" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
  err "version does not match /^N.N(.N)?$/: '$VER'"
else
  ok "version format valid: $VER"
fi

# ──────────────────────────────────────────────────────────────────────────
# mode enum + params XOR + consistency
# ──────────────────────────────────────────────────────────────────────────
MODE=$(jq -r '.mode // empty' "$STATE")
case "$MODE" in
  local-only|share)
    ok "mode valid: $MODE"
    ;;
  "")
    err "mode missing"
    ;;
  *)
    err "mode must be 'local-only' or 'share', got '$MODE'"
    ;;
esac

LO=$(jq -r '.params.local_only // false' "$STATE")
SH=$(jq -r '.params.share // false' "$STATE")

if [ "$LO" = "true" ] && [ "$SH" = "true" ]; then
  err "params.local_only AND params.share both true (mutually exclusive)"
elif [ "$LO" != "true" ] && [ "$SH" != "true" ]; then
  err "neither params.local_only nor params.share set (one must be true)"
else
  ok "params.local_only XOR params.share holds"
fi

if [ "$MODE" = "local-only" ] && [ "$LO" != "true" ]; then
  err "mode='local-only' but params.local_only is not true"
fi
if [ "$MODE" = "share" ] && [ "$SH" != "true" ]; then
  err "mode='share' but params.share is not true"
fi

# ──────────────────────────────────────────────────────────────────────────
# stacks is array; each stack has id + language + paths
# ──────────────────────────────────────────────────────────────────────────
STACKS_TYPE=$(jq -r '.stacks | type' "$STATE" 2>/dev/null || echo "null")
if [ "$STACKS_TYPE" != "array" ]; then
  err "stacks must be array, got $STACKS_TYPE"
else
  ok "stacks is array (length: $(jq -r '.stacks | length' "$STATE"))"
  # Per-stack required fields
  N=$(jq -r '.stacks | length' "$STATE")
  for i in $(seq 0 $((N-1))); do
    [ "$i" -ge 5 ] && { ok "...(stack 5+ skipped, only first 5 spot-checked)"; break; }
    for sf in id language paths; do
      v=$(jq -r --argjson i "$i" --arg f "$sf" '.stacks[$i] | has($f)' "$STATE")
      if [ "$v" = "true" ]; then
        ok "stacks[$i].$sf present"
      else
        err "stacks[$i] missing required field: $sf"
      fi
    done
  done
fi

# ──────────────────────────────────────────────────────────────────────────
# confirmed_forbidden_zones is array (default empty acceptable)
# ──────────────────────────────────────────────────────────────────────────
if jq -e 'has("confirmed_forbidden_zones")' "$STATE" >/dev/null; then
  FZ_TYPE=$(jq -r '.confirmed_forbidden_zones | type' "$STATE")
  if [ "$FZ_TYPE" != "array" ]; then
    err "confirmed_forbidden_zones must be array, got $FZ_TYPE"
  else
    ok "confirmed_forbidden_zones is array (length: $(jq -r '.confirmed_forbidden_zones | length' "$STATE"))"
  fi
fi

# ──────────────────────────────────────────────────────────────────────────
# phases.<n>.status enum check
# ──────────────────────────────────────────────────────────────────────────
ALLOWED_STATUS="done skipped failed dry-run blocked deferred verification_skipped migrated not_triggered placeholder in_progress"

PHASES_TYPE=$(jq -r '.phases | type' "$STATE" 2>/dev/null || echo "null")
if [ "$PHASES_TYPE" != "object" ]; then
  err "phases must be object, got $PHASES_TYPE"
else
  # Iterate phase keys
  for phase_key in $(jq -r '.phases | keys[]' "$STATE"); do
    has_status=$(jq -r --arg k "$phase_key" '.phases[$k] | has("status")' "$STATE")
    if [ "$has_status" != "true" ]; then
      err "phases.$phase_key missing status field"
      continue
    fi
    status=$(jq -r --arg k "$phase_key" '.phases[$k].status' "$STATE")
    found=0
    for allowed in $ALLOWED_STATUS; do
      [ "$status" = "$allowed" ] && found=1 && break
    done
    if [ "$found" = "1" ]; then
      ok "phases.$phase_key.status = $status (valid)"
    else
      err "phases.$phase_key.status = '$status' not in allowed enum: $ALLOWED_STATUS"
    fi
  done
fi

# ──────────────────────────────────────────────────────────────────────────
# Final
# ──────────────────────────────────────────────────────────────────────────
echo ""
if [ "$ERR" -eq 0 ]; then
  echo "$(c '1;32' '✓ state schema valid')"
  exit 0
else
  echo "$(c '1;31' '✗ schema violations found')" >&2
  exit 1
fi
