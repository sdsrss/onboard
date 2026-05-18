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

# Dangerous command patterns (extend cautiously; each addition is a deny).
# The rm patterns are anchored so the deletion TARGET is exactly the root /
# (or ~ / $HOME) — without anchoring, `rm -rf /` matches as a substring of
# `rm -rf /tmp/foo`, which is a false-positive that blocks legitimate cleanup.
# `[;&|]` end-marker also catches chained forms like `rm -rf / && ...`.
# The `.env` pattern is anchored at the trailing token boundary so legitimate
# variants (`.env.local`, `.env.example`, `.envrc`, `.env_backup`) are allowed
# while `cat secret > .env`, `> .env && ...`, `>> .env 2>&1` are denied.
BLOCK_PATTERNS=(
  'rm[[:space:]]+-rf[[:space:]]+/[[:space:]]*($|[;&|])'
  'rm[[:space:]]+-rf[[:space:]]+~[[:space:]]*($|[;&|])'
  'rm[[:space:]]+-rf[[:space:]]+\$HOME[[:space:]]*($|[;&|])'
  'chmod -R 777'
  'git push --force.*origin (main|master)'
  '>[[:space:]]*\.env([^.a-zA-Z0-9_-]|$)'
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
