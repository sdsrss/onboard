#!/usr/bin/env bash
# post-edit-check.sh — PostToolUse hook for Edit/Write/MultiEdit
# Always exits 0 (PostToolUse cannot block; enforcement happens at Stop).
#
# Responsibilities:
#   1. Append edited file path to ONBOARD_TOUCHED_LOG (drives Stop hook's
#      incremental mode).
#   2. Multi-stack dispatch: pick the format_check_cmd of the stack whose
#      `extensions` list contains this file's extension, run it lightly,
#      emit stderr warning on failure (Claude sees it but operation proceeds).
#
# Env:
#   ONBOARD_TOUCHED_LOG    — path to RUNTIME touched-files log
#   ONBOARD_STACKS_FILE    — path to JSON describing stacks (see SKILL.md Phase 7)
#   ONBOARD_LOG_DIR        — RUNTIME log directory; differs by mode
#                             (share: .claude/onboarding-logs / local-only:
#                             .claude/local-only/onboarding-logs). Falling back
#                             to the share path would leak local-only state
#                             into the PROJECT working tree.

set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Cross-platform timeout shim (v2.5): macOS lacks `timeout` by default.
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    timeout() { gtimeout "$@"; }
  else
    timeout() { shift; "$@"; }
  fi
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Record edited file for Stop hook incremental mode
if [ -n "${ONBOARD_TOUCHED_LOG:-}" ]; then
  mkdir -p "$(dirname "$ONBOARD_TOUCHED_LOG")"
  echo "$FILE_PATH" >> "$ONBOARD_TOUCHED_LOG"
fi

LOG_DIR="${ONBOARD_LOG_DIR:-.claude/onboarding-logs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/post-edit-check.log"

# Multi-stack dispatch: find matching stack by extension
if [ -n "${ONBOARD_STACKS_FILE:-}" ] && [ -f "$ONBOARD_STACKS_FILE" ]; then
  EXT=".${FILE_PATH##*.}"
  CMD=$(jq -r --arg ext "$EXT" '
    .[] | select(.extensions | index($ext)) | .format_check_cmd // empty
  ' "$ONBOARD_STACKS_FILE" 2>/dev/null | head -1)
  # Per-stack format-check timeout (v2.12.0). Default 10s; Python `black --check`
  # cold start has been observed at 5-8s, so 10s is a tight default — projects
  # with slow formatters can override via stacks.json `format_check_timeout_sec`.
  FMT_CHECK_TO=$(jq -r --arg ext "$EXT" '
    .[] | select(.extensions | index($ext)) | .format_check_timeout_sec // 10
  ' "$ONBOARD_STACKS_FILE" 2>/dev/null | head -1)
  [ -z "$FMT_CHECK_TO" ] && FMT_CHECK_TO=10

  if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
    if ! timeout "$FMT_CHECK_TO" bash -lc "$CMD" >"$LOG" 2>&1; then
      echo "Post-edit warning: $EXT format check failed for $FILE_PATH. Stop hook will enforce later." >&2
    fi
  fi
fi

exit 0
