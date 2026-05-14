#!/usr/bin/env bash
# guard-edit.sh — PreToolUse hook for Edit/Write/MultiEdit tools
# Blocks edits to ANY path under confirmed forbidden zones.
# Output: exit 0 + stdout JSON.
#
# Env:
#   ONBOARD_FORBIDDEN_PATHS — colon-separated list of confirmed forbidden zones
#                             (relative paths, no leading "./", no trailing "/")
#
# Multi-path extraction: handles Edit (file_path), Write (file_path),
# MultiEdit (files[].file_path or edits[].file_path).
#
# Boundary-safe matching: "packages/legacy" does NOT match "packages/legacy-new".

set -euo pipefail

INPUT=$(cat)

# Normalize path: strip leading "./", trailing "/", collapse "//" → "/"
normalize_path() {
  local p="$1"
  p="${p#./}"
  p="${p%/}"
  printf '%s\n' "$p" | sed 's#//*#/#g'
}

# Extract all candidate paths from tool_input (Edit / Write / MultiEdit shapes)
PATHS=$(echo "$INPUT" | jq -r '
  [
    .tool_input.file_path?,
    .tool_input.path?,
    (.tool_input.files[]?.file_path?),
    (.tool_input.edits[]?.file_path?)
  ] | map(select(. != null and . != "")) | unique | .[]
')

[ -z "$PATHS" ] && exit 0

IFS=':' read -ra FORBIDDEN <<< "${ONBOARD_FORBIDDEN_PATHS:-}"

while IFS= read -r raw_path; do
  [ -z "$raw_path" ] && continue
  path=$(normalize_path "$raw_path")
  for raw_fz in "${FORBIDDEN[@]}"; do
    [ -z "$raw_fz" ] && continue
    fz=$(normalize_path "$raw_fz")
    # Exact boundary match: path must be fz itself or start with fz/
    case "$path" in
      "$fz"|"$fz"/*)
        jq -n --arg path "$path" --arg zone "$fz" '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: ("Forbidden zone (\($zone)): refuse to edit \($path)")
          }
        }'
        exit 0
        ;;
    esac
  done
done <<< "$PATHS"

exit 0
