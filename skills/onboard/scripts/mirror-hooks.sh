#!/usr/bin/env bash
# Mirror /onboard hook scripts to a stable path so user settings.json doesn't
# depend on the ephemeral ${CLAUDE_PLUGIN_ROOT} (which changes each plugin update).
#
# Default flow (plugin mode):
#   ~/.claude/plugins/cache/onboard@<mkt>@<sha>/skills/onboard/hooks/*.sh
#     → cp →
#   ~/.claude/onboard-runtime/hooks/*.sh  (stable, referenced by user settings)
#
# Usage:
#   mirror-hooks.sh                       # auto-detect source via script location
#   ONBOARD_MIRROR_SOURCE=/path/to/hooks mirror-hooks.sh
#   ONBOARD_MIRROR_DEST=/path/to/dest mirror-hooks.sh
#
# Exit codes:
#   0  mirror succeeded (4 hooks copied, manifest written)
#   1  failed (missing source / missing required hook / write error)
#
# Idempotent: re-run with same source = same content; re-run with new source =
# refresh (manifest.source updates). Safe to invoke from Phase 7 every onboard run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_SOURCE=""
if [ -d "$SCRIPT_DIR/../hooks" ]; then
  DEFAULT_SOURCE="$(cd "$SCRIPT_DIR/../hooks" && pwd)"
fi

SOURCE="${ONBOARD_MIRROR_SOURCE:-$DEFAULT_SOURCE}"
DEST="${ONBOARD_MIRROR_DEST:-$HOME/.claude/onboard-runtime/hooks}"

REQUIRED_HOOKS=(guard-bash.sh guard-edit.sh post-edit-check.sh stop-verify.sh)

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info() { echo "$(c '1;34' '[mirror]') $*"; }
warn() { echo "$(c '1;33' '[mirror]') $*" >&2; }
err()  { echo "$(c '1;31' '[mirror]') $*" >&2; }
ok()   { echo "$(c '1;32' '[mirror]') $*"; }

if [ -z "$SOURCE" ] || [ ! -d "$SOURCE" ]; then
  err "source hooks directory not found"
  err "  tried:       $SOURCE"
  err "  auto-detect: $DEFAULT_SOURCE"
  err "set ONBOARD_MIRROR_SOURCE to override"
  exit 1
fi

VERSION="unknown"
SKILL_FILE="$SCRIPT_DIR/../SKILL.md"
if [ -f "$SKILL_FILE" ]; then
  v=$(grep -E "^# /onboard.*\(v[0-9]" "$SKILL_FILE" 2>/dev/null | head -1 | sed -E 's/.*\(v([0-9.]+).*/\1/')
  [ -n "$v" ] && VERSION="$v"
fi

info "source:  $SOURCE"
info "dest:    $DEST"
info "version: $VERSION"

missing=()
for h in "${REQUIRED_HOOKS[@]}"; do
  [ -f "$SOURCE/$h" ] || missing+=("$h")
done
if [ "${#missing[@]}" -gt 0 ]; then
  err "missing required hook(s) in source: ${missing[*]}"
  exit 1
fi

if ! mkdir -p "$DEST" 2>/dev/null; then
  err "could not create mirror dest directory: $DEST"
  err "  parent may be unwritable, path may collide with a regular file,"
  err "  or filesystem may be read-only."
  err "  override with ONBOARD_MIRROR_DEST=<path> (default: \$HOME/.claude/onboard-runtime/hooks)"
  exit 1
fi

# Idempotent fast path (v2.11.3): cmp -s before cp; skip both copy and manifest
# rewrite when source content and version match what's already at dest. Makes
# the "no-op re-run" case observable in the log (default Phase 7 invocation
# fires this script every onboard run, so the savings add up).
mirrored=0
unchanged=0
for h in "${REQUIRED_HOOKS[@]}"; do
  if [ -f "$DEST/$h" ] && cmp -s "$SOURCE/$h" "$DEST/$h"; then
    # Content matches; ensure +x is still set without touching mtime.
    [ -x "$DEST/$h" ] || chmod +x "$DEST/$h"
    unchanged=$((unchanged+1))
  else
    cp "$SOURCE/$h" "$DEST/$h"
    chmod +x "$DEST/$h"
    mirrored=$((mirrored+1))
  fi
done

MANIFEST_DIR="$(dirname "$DEST")"
MANIFEST="$MANIFEST_DIR/.mirror-manifest.json"

# Skip manifest rewrite when nothing changed AND the prior manifest already
# records the current source + version. mirrored_at left stale on purpose —
# that field reflects "last actual mirror operation", not "last invocation".
SKIP_MANIFEST=0
if [ "$mirrored" -eq 0 ] && [ -f "$MANIFEST" ]; then
  prev_source=$(jq -r '.source // empty' "$MANIFEST" 2>/dev/null || echo "")
  prev_version=$(jq -r '.version // empty' "$MANIFEST" 2>/dev/null || echo "")
  if [ "$prev_source" = "$SOURCE" ] && [ "$prev_version" = "$VERSION" ]; then
    SKIP_MANIFEST=1
  fi
fi

if [ "$SKIP_MANIFEST" -eq 1 ]; then
  ok "no changes — all $unchanged hooks already current (v$VERSION) at $DEST"
else
  cat > "$MANIFEST" <<EOF
{
  "version": "$VERSION",
  "source": "$SOURCE",
  "dest": "$DEST",
  "mirrored_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hooks": ["guard-bash.sh", "guard-edit.sh", "post-edit-check.sh", "stop-verify.sh"]
}
EOF
  if [ "$mirrored" -gt 0 ]; then
    ok "mirrored $mirrored hooks (v$VERSION) → $DEST ($unchanged unchanged)"
  else
    ok "refreshed manifest (v$VERSION) → $DEST (all $unchanged hooks already current)"
  fi
  info "manifest: $MANIFEST"
fi
