#!/usr/bin/env bash
# guard-bash.sh — PreToolUse hook for Bash tool
# Intercepts dangerous shell command patterns before execution.
# Output: exit 0 + stdout JSON (Iron Law 15 in /onboard SKILL.md).
#
# stdin: Claude Code PreToolUse JSON payload
# behavior:
#   - command matching any pattern in BLOCK_PATTERNS → return permissionDecision: deny
#   - otherwise → exit 0 silently (allow)

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Dangerous command patterns (extend cautiously; each addition is a deny)
BLOCK_PATTERNS=(
  'rm -rf /'
  'rm -rf ~'
  'rm -rf \$HOME'
  'chmod -R 777'
  'git push --force.*origin (main|master)'
  '> *\.env'
  'curl .* \| (ba)?sh'
)

for pat in "${BLOCK_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pat"; then
    jq -n --arg reason "Blocked dangerous pattern: $pat" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
  fi
done

exit 0
