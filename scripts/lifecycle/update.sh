#!/usr/bin/env bash
# Plugin update lifecycle hook. Claude Code has already replaced plugin files
# with the new version before this runs.
# Job: re-set executable bits + tell user to run --update inside onboarded projects.

set -euo pipefail

PLUGIN_DIR="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
OLD_VERSION="${ONBOARD_PREVIOUS_VERSION:-unknown}"

chmod +x "$PLUGIN_DIR"/hooks/*.sh 2>/dev/null || true
chmod +x "$PLUGIN_DIR"/install.sh 2>/dev/null || true
chmod +x "$PLUGIN_DIR"/scripts/lifecycle/*.sh 2>/dev/null || true

NEW_VERSION=$(grep -E "^# /onboard.*\(v[0-9]" "$PLUGIN_DIR/SKILL.md" 2>/dev/null | head -1 | sed -E 's/.*\(v([0-9.]+).*/\1/')

cat <<MSG
[onboard plugin] updated ($OLD_VERSION → ${NEW_VERSION:-unknown})

For each project you've previously onboarded:
  cd <project> && /onboard --update

This triggers Phase 0.5 Migration to align the project's state file
with the new spec schema. Without this step, Doctor mode (--doctor)
will report drift on those projects.
MSG
