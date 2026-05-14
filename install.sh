#!/usr/bin/env bash
# /onboard universal installer — works without Claude Code's /plugin command.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash
#   curl -sSL .../install.sh | bash -s -- update
#   curl -sSL .../install.sh | bash -s -- uninstall
#   curl -sSL .../install.sh | bash -s -- doctor
#
# Local invocation:
#   ./install.sh [install|update|uninstall|doctor]
#
# Environment:
#   ONBOARD_REPO    git URL                (default: https://github.com/sdsrss/onboard.git)
#   ONBOARD_BRANCH  branch/tag             (default: main)
#   ONBOARD_TARGET  user | project         (default: user)
#   ONBOARD_ALLOW_DIRTY  1 to skip dirty-tree check on update
#
# Idempotent: install on an existing install errors out with "use update"; update on a
# missing install errors out with "run install first"; uninstall on a missing install
# is a no-op.

set -euo pipefail

REPO="${ONBOARD_REPO:-https://github.com/sdsrss/onboard.git}"
BRANCH="${ONBOARD_BRANCH:-main}"
TARGET="${ONBOARD_TARGET:-user}"
ACTION="${1:-install}"

case "$TARGET" in
  user)
    INSTALL_DIR="$HOME/.claude/skills/onboard"
    ;;
  project)
    : "${CLAUDE_PROJECT_DIR:=$(pwd)}"
    INSTALL_DIR="$CLAUDE_PROJECT_DIR/.claude/skills/onboard"
    ;;
  *)
    echo "ERROR: ONBOARD_TARGET must be 'user' or 'project' (got '$TARGET')" >&2
    exit 2
    ;;
esac

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info() { echo "$(c '1;34' '[onboard]') $*"; }
warn() { echo "$(c '1;33' '[onboard]') $*" >&2; }
err()  { echo "$(c '1;31' '[onboard]') $*" >&2; }
ok()   { echo "$(c '1;32' '[onboard]') $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; exit 1; }
}

check_deps() {
  require_cmd git
  require_cmd bash
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found on PATH — Phase 7 hooks need it at runtime."
    warn "install with: brew install jq | apt install jq | dnf install jq | pacman -S jq"
  fi
}

current_version() {
  local skill="$INSTALL_DIR/SKILL.md"
  [ -f "$skill" ] || { echo "none"; return; }
  grep -E "^# /onboard.*\(v[0-9]" "$skill" 2>/dev/null \
    | head -1 \
    | sed -E 's/.*\(v([0-9.]+).*/\1/' \
    || echo "unknown"
}

do_install() {
  check_deps
  info "target: $TARGET → $INSTALL_DIR"

  if [ -d "$INSTALL_DIR" ]; then
    local v
    v=$(current_version)
    warn "/onboard already installed (v$v) at $INSTALL_DIR"
    warn "to refresh: $0 update"
    warn "to reinstall clean: $0 uninstall && $0 install"
    exit 0
  fi

  mkdir -p "$(dirname "$INSTALL_DIR")"
  info "cloning $REPO @ $BRANCH"
  if ! git clone --depth 1 --branch "$BRANCH" "$REPO" "$INSTALL_DIR" >/dev/null 2>&1; then
    err "git clone failed. Check ONBOARD_REPO / ONBOARD_BRANCH and network."
    exit 1
  fi

  chmod +x "$INSTALL_DIR"/hooks/*.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR"/install.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR"/scripts/lifecycle/*.sh 2>/dev/null || true

  local v
  v=$(current_version)
  ok "installed /onboard v$v"
  echo ""
  echo "Next:"
  echo "  • In any git project, run:  /onboard"
  echo "  • Default mode is --local-only (zero team pollution)"
  echo "  • Full docs:  $INSTALL_DIR/README.md"
}

do_update() {
  check_deps
  if [ ! -d "$INSTALL_DIR" ]; then
    err "not installed at $INSTALL_DIR"
    err "run first:  $0 install"
    exit 1
  fi
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    err "$INSTALL_DIR exists but is not a git checkout"
    err "remove it manually then run:  $0 install"
    exit 1
  fi

  local old_v
  old_v=$(current_version)
  info "updating from v$old_v"

  pushd "$INSTALL_DIR" >/dev/null

  if [ "${ONBOARD_ALLOW_DIRTY:-0}" != "1" ]; then
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
      popd >/dev/null
      err "uncommitted local changes in $INSTALL_DIR"
      err "either commit/stash them, or rerun with ONBOARD_ALLOW_DIRTY=1 to overwrite"
      exit 1
    fi
  fi

  git fetch --depth 1 origin "$BRANCH" >/dev/null 2>&1
  git reset --hard "origin/$BRANCH" >/dev/null 2>&1

  popd >/dev/null

  chmod +x "$INSTALL_DIR"/hooks/*.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR"/install.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR"/scripts/lifecycle/*.sh 2>/dev/null || true

  local new_v
  new_v=$(current_version)
  ok "updated /onboard ($old_v → $new_v)"
  echo ""
  echo "Per-project state files in projects you've onboarded are unchanged."
  echo "To align a project with the new spec version:"
  echo "  cd <project> && /onboard --update"
}

do_uninstall() {
  if [ ! -d "$INSTALL_DIR" ]; then
    warn "/onboard not installed at $INSTALL_DIR — nothing to remove"
    exit 0
  fi

  info "uninstall plan"
  echo "  • Will remove: $INSTALL_DIR (global skill files)"
  echo ""
  warn "Per-project state in projects you've onboarded will NOT be touched."
  warn "For per-project cleanup, run inside each project before this uninstall:"
  warn "  /onboard --uninstall"
  echo ""

  if [ -t 0 ]; then
    read -r -p "Proceed with global uninstall? [y/N] " ans
  else
    ans="${ONBOARD_CONFIRM_UNINSTALL:-n}"
  fi

  case "$ans" in
    y|Y|yes|YES)
      rm -rf "$INSTALL_DIR"
      ok "/onboard global skill files removed"
      ;;
    *)
      info "aborted"
      exit 0
      ;;
  esac
}

do_doctor() {
  echo "── /onboard installer doctor ──"
  echo ""
  echo "Global skill install:"
  if [ -d "$INSTALL_DIR" ]; then
    local v
    v=$(current_version)
    echo "  ✓ installed   v$v"
    echo "                $INSTALL_DIR"
    local exec_count
    exec_count=$(find "$INSTALL_DIR"/hooks -name "*.sh" -perm -u+x 2>/dev/null | wc -l | tr -d ' ')
    echo "  hooks exec    $exec_count/4"
  else
    echo "  ✗ not installed at $INSTALL_DIR"
    echo "    install with: $0 install"
  fi
  echo ""
  echo "Required commands on PATH:"
  for cmd in git bash jq; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "  ✓ $cmd  ($(command -v "$cmd"))"
    else
      echo "  ✗ $cmd  missing"
    fi
  done
  echo ""
  echo "Optional commands (Phase 0 detection):"
  for cmd in gh glab tea make gtimeout mise asdf; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "  ✓ $cmd"
    else
      echo "  - $cmd  (not installed)"
    fi
  done
  echo ""
  echo "For per-project diagnosis:  cd <project> && /onboard --doctor"
}

case "$ACTION" in
  install)   do_install ;;
  update)    do_update ;;
  uninstall) do_uninstall ;;
  doctor)    do_doctor ;;
  -h|--help|help)
    cat <<'HELP'
Usage: install.sh [install|update|uninstall|doctor]

Actions:
  install     Clone the skill into ~/.claude/skills/onboard (default)
  update      Pull latest changes from origin (refuses on dirty tree)
  uninstall   Remove the global skill install (asks for confirmation)
  doctor      Diagnose installer state + dependency availability

Environment overrides:
  ONBOARD_REPO        git URL of the skill repository
  ONBOARD_BRANCH      branch or tag to install/update (default: main)
  ONBOARD_TARGET      'user' (default, ~/.claude/skills) or 'project' (./.claude/skills)
  ONBOARD_ALLOW_DIRTY 1 to skip dirty-tree check on update
  ONBOARD_CONFIRM_UNINSTALL  set to 'yes' for non-interactive uninstall

Per-project cleanup is a separate operation (do BEFORE global uninstall):
  cd <project> && /onboard --uninstall
HELP
    ;;
  *)
    err "unknown action: $ACTION"
    err "valid: install | update | uninstall | doctor | help"
    exit 2
    ;;
esac
