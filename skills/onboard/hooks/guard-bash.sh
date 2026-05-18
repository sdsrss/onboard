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

# Project-level command deny (v2.12.0): newline-separated regex list from env.
# Symmetric to ONBOARD_FORBIDDEN_PATHS in guard-edit.sh — addresses the
# asymmetry the audit flagged (Iron Law 16 had global zones for paths but no
# equivalent for commands; users couldn't say "this repo forbids prod migrations
# from a local shell"). Newline (NOT colon) is the separator so POSIX char
# classes `[[:space:]]` / `[[:alpha:]]` / etc work freely inside patterns —
# the colon-split form would fragment `[[:space:]]` into 3 broken pieces.
# JSON shorthand: write `\n` in settings.json strings, which decodes to a
# real newline byte before the env var hits this hook. Patterns are
# `grep -qE` (ERE) regex; empty lines (incl. leading/trailing) skipped.
if [ -n "${ONBOARD_FORBIDDEN_COMMANDS:-}" ]; then
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if echo "$COMMAND" | grep -qE "$pat"; then
      jq -n --arg reason "Blocked by ONBOARD_FORBIDDEN_COMMANDS pattern: $pat" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $reason
        }
      }'
      exit 0
    fi
  done <<< "$ONBOARD_FORBIDDEN_COMMANDS"
fi

exit 0
