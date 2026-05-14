#!/usr/bin/env bash
# Plugin uninstall lifecycle hook. Claude Code removes plugin files AFTER this script.
# Job: warn user about per-project state that will NOT be auto-cleaned.

set -euo pipefail

PLUGIN_DIR="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"

cat <<'MSG' >&2
[onboard plugin] uninstalling

IMPORTANT — what this uninstall does NOT do:
  • Per-project state (.claude/onboarding-state.json or .claude/local-only/) is NOT removed
  • Per-project hook entries in settings.json / settings.local.json are NOT removed
  • CLAUDE.md / CLAUDE.local.md content written by onboard is NOT removed
  • .gitignore / .git/info/exclude lines written by onboard are NOT removed

To clean a single project BEFORE this uninstall (recommended):
  cd <project>
  /onboard --uninstall

After this plugin uninstall, the /onboard command will be gone, so per-project
cleanup must happen FIRST. If you forgot, you can manually clean each project:

  # local-only mode projects
  rm -rf .claude/local-only
  # remove between '# >>> /onboard' and '# <<< /onboard' markers in:
  #   .git/info/exclude

  # share mode projects
  # remove between markers in:
  #   .gitignore
  #   CLAUDE.md
  # remove entries with "_onboard_managed": true from:
  #   .claude/settings.json
MSG
