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

# ONBOARD_LOG_DIR is mode-aware (set by settings.template.json /
# settings.local.template.json); fallback matches the share-mode default for
# backwards compatibility with v2.10.1-and-earlier installs that predate this env.
LOG_DIR="${ONBOARD_LOG_DIR:-.claude/onboarding-logs}"
mkdir -p "$LOG_DIR"
FAILED=()

# No stack config → can't do anything sensible, exit gracefully
if [ -z "$STACKS_FILE" ] || [ ! -f "$STACKS_FILE" ]; then
  echo "stop-verify: no stacks config (ONBOARD_STACKS_FILE unset or missing), skipping" >&2
  exit 0
fi

# Collect touched files (deduped) into a NUL-safe array — read NL-delimited so
# filenames containing whitespace survive intact. Earlier versions space-joined
# the list and word-split it back, which corrupted `src/has space.ts` into two
# bogus paths (`has`, `space.ts`) before lint ever saw it.
TOUCHED_FILES=()
if [ -n "$TOUCHED_LOG" ] && [ -f "$TOUCHED_LOG" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && TOUCHED_FILES+=("$line")
  done < <(sort -u "$TOUCHED_LOG")
fi

if [ "${#TOUCHED_FILES[@]}" -eq 0 ] && [ "$MODE" != "strict" ]; then
  exit 0
fi

# Iterate stacks
STACK_IDS=$(jq -r '.[].id' "$STACKS_FILE")
for stack_id in $STACK_IDS; do
  EXTS=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .extensions[]' "$STACKS_FILE")
  LINT_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .lint_cmd // empty' "$STACKS_FILE")
  TC_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .typecheck_cmd // empty' "$STACKS_FILE")
  FMT_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .format_check_cmd // empty' "$STACKS_FILE")

  # Filter touched files belonging to this stack (by extension).
  # Quote each match with %q so paths with whitespace / shell metachars stay
  # intact when handed to `bash -lc "$LINT_CMD $STACK_FILES_QUOTED"`.
  STACK_FILES_QUOTED=""
  HAVE_STACK_FILES=0
  for f in "${TOUCHED_FILES[@]}"; do
    for ext in $EXTS; do
      if [[ "$f" == *"$ext" ]]; then
        STACK_FILES_QUOTED+=" $(printf '%q' "$f")"
        HAVE_STACK_FILES=1
        break
      fi
    done
  done

  case "$MODE" in
    light)
      # Incremental lint only
      [ "$HAVE_STACK_FILES" -eq 0 ] && continue
      if [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD$STACK_FILES_QUOTED" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 \
          || FAILED+=("lint:$stack_id")
      fi
      ;;

    standard)
      # Incremental lint + full typecheck
      if [ "$HAVE_STACK_FILES" -eq 1 ] && [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD$STACK_FILES_QUOTED" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 \
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
