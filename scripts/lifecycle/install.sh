#!/usr/bin/env bash
# Plugin install lifecycle hook (Claude Code calls this after copying plugin files).
# This script does NOT clone or fetch — files are already in place.
# Job: validate, chmod executables, print first-run guidance.

set -euo pipefail

PLUGIN_DIR="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"

for required in "$PLUGIN_DIR/SKILL.md" "$PLUGIN_DIR/hooks/guard-bash.sh" "$PLUGIN_DIR/hooks/guard-edit.sh" "$PLUGIN_DIR/hooks/post-edit-check.sh" "$PLUGIN_DIR/hooks/stop-verify.sh"; do
  if [ ! -f "$required" ]; then
    echo "[onboard install] ERROR: missing required file: $required" >&2
    exit 1
  fi
done

chmod +x "$PLUGIN_DIR"/hooks/*.sh 2>/dev/null || true
chmod +x "$PLUGIN_DIR"/install.sh 2>/dev/null || true
chmod +x "$PLUGIN_DIR"/scripts/lifecycle/*.sh 2>/dev/null || true

if ! command -v jq >/dev/null 2>&1; then
  echo "[onboard install] WARN: jq not on PATH — Phase 7 hooks require it at runtime" >&2
  echo "[onboard install]       install: brew install jq | apt install jq | dnf install jq" >&2
fi

VERSION=$(grep -E "^# /onboard.*\(v[0-9]" "$PLUGIN_DIR/SKILL.md" 2>/dev/null | head -1 | sed -E 's/.*\(v([0-9.]+).*/\1/')

cat <<MSG
[onboard plugin] installed (v${VERSION:-unknown})

Next:
  • In any git project, run:  /onboard
  • Default mode is --local-only (zero team pollution)
  • Project-level config: .claude/settings.local.json
  • Full docs: ${PLUGIN_DIR}/README.md
MSG
