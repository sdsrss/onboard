#!/usr/bin/env bash
# stop-verify.sh — Stop hook
# Enforces lint / typecheck / format:check before Claude finishes responding.
# Operates in three modes via ONBOARD_STOP_MODE:
#   - light    (default for medium/large projects): incremental lint only,
#              skips typecheck (handled by pre-push instead)
#   - standard (default for small projects): incremental lint + full typecheck
#   - strict   (opt-in): full lint + full typecheck + full format:check
#
# Output: emits `{decision: "block", reason: ...}` JSON if any check fails;
# always exits 0 so JSON is honored (Iron Law 15: never mix exit 2 with JSON).
#
# Multi-stack: reads ONBOARD_STACKS_FILE (JSON), runs per-stack commands on
# files matching each stack's extensions. Touched-files log resets each turn.

set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Cross-platform timeout shim (v2.5): macOS lacks `timeout` by default.
# Prefers GNU `gtimeout` (from coreutils); falls back to no-op if neither
# exists so the hook never breaks just because the binary is missing.
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    timeout() { gtimeout "$@"; }
  else
    echo "stop-verify: no timeout/gtimeout found, running without time limits" >&2
    timeout() { shift; "$@"; }
  fi
fi

MODE="${ONBOARD_STOP_MODE:-light}"
STACKS_FILE="${ONBOARD_STACKS_FILE:-}"
TOUCHED_LOG="${ONBOARD_TOUCHED_LOG:-}"

# Prevent infinite Stop loop (Claude Code sets stop_hook_active on retry)
INPUT=$(cat 2>/dev/null || echo '{}')
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
[ "$ACTIVE" = "true" ] && exit 0

LOG_DIR=".claude/onboarding-logs"
mkdir -p "$LOG_DIR"
FAILED=()

# No stack config → can't do anything sensible, exit gracefully
if [ -z "$STACKS_FILE" ] || [ ! -f "$STACKS_FILE" ]; then
  echo "stop-verify: no stacks config (ONBOARD_STACKS_FILE unset or missing), skipping" >&2
  exit 0
fi

# Collect touched files (deduped); empty in non-strict mode → fast path
TOUCHED_FILES=""
if [ -n "$TOUCHED_LOG" ] && [ -f "$TOUCHED_LOG" ]; then
  TOUCHED_FILES=$(sort -u "$TOUCHED_LOG" | tr '\n' ' ')
fi

if [ -z "$TOUCHED_FILES" ] && [ "$MODE" != "strict" ]; then
  exit 0
fi

# Iterate stacks
STACK_IDS=$(jq -r '.[].id' "$STACKS_FILE")
for stack_id in $STACK_IDS; do
  EXTS=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .extensions[]' "$STACKS_FILE")
  LINT_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .lint_cmd // empty' "$STACKS_FILE")
  TC_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .typecheck_cmd // empty' "$STACKS_FILE")
  FMT_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .format_check_cmd // empty' "$STACKS_FILE")

  # Filter touched files belonging to this stack (by extension)
  STACK_FILES=""
  for f in $TOUCHED_FILES; do
    for ext in $EXTS; do
      [[ "$f" == *"$ext" ]] && STACK_FILES="$STACK_FILES $f"
    done
  done
  STACK_FILES="${STACK_FILES# }"

  case "$MODE" in
    light)
      # Incremental lint only
      [ -z "$STACK_FILES" ] && continue
      if [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD $STACK_FILES" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 \
          || FAILED+=("lint:$stack_id")
      fi
      ;;

    standard)
      # Incremental lint + full typecheck
      if [ -n "$STACK_FILES" ] && [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD $STACK_FILES" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 \
          || FAILED+=("lint:$stack_id")
      fi
      if [ -n "$TC_CMD" ] && [ "$TC_CMD" != "null" ]; then
        timeout 45 bash -lc "$TC_CMD" >"$LOG_DIR/stop-typecheck-$stack_id.log" 2>&1 \
          || FAILED+=("typecheck:$stack_id")
      fi
      ;;

    strict)
      # Full lint + full typecheck + full format:check
      if [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 \
          || FAILED+=("lint:$stack_id")
      fi
      if [ -n "$TC_CMD" ] && [ "$TC_CMD" != "null" ]; then
        timeout 45 bash -lc "$TC_CMD" >"$LOG_DIR/stop-typecheck-$stack_id.log" 2>&1 \
          || FAILED+=("typecheck:$stack_id")
      fi
      if [ -n "$FMT_CMD" ] && [ "$FMT_CMD" != "null" ]; then
        timeout 30 bash -lc "$FMT_CMD" >"$LOG_DIR/stop-format-$stack_id.log" 2>&1 \
          || FAILED+=("format:$stack_id")
      fi
      ;;
  esac
done

# Clear touched-files log for next turn
if [ -n "$TOUCHED_LOG" ] && [ -f "$TOUCHED_LOG" ]; then
  : > "$TOUCHED_LOG"
fi

if [ ${#FAILED[@]} -gt 0 ]; then
  REASON="Stop blocked [mode=$MODE]: failing checks — ${FAILED[*]}. See $LOG_DIR/"
  jq -n --arg reason "$REASON" '{
    decision: "block",
    reason: $reason
  }'
fi

exit 0
