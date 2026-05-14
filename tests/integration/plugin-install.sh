#!/usr/bin/env bash
# Sandbox simulation of:
#   /plugin marketplace add sdsrss/onboard
#   /plugin install onboard
#
# Walks through what Claude Code WOULD do based on official docs:
#   https://code.claude.com/docs/en/plugin-marketplaces
#   https://code.claude.com/docs/en/plugins-reference
# Verifies every assertion the real plugin system enforces.
#
# 24 assertions. Exit 0 on full pass, non-zero on any FAIL.
# Sandbox lives under $SANDBOX (default /tmp/onboard-plugin-sandbox), cleaned on each run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SANDBOX="${SANDBOX:-/tmp/onboard-plugin-sandbox}"
PASS=0
FAIL=0
WARN=0

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "  $(c '1;32' '✓ PASS') $*"; PASS=$((PASS+1)); }
fail() { echo "  $(c '1;31' '✗ FAIL') $*"; FAIL=$((FAIL+1)); }
warn() { echo "  $(c '1;33' '⚠ WARN') $*"; WARN=$((WARN+1)); }
info() { echo "$(c '1;34' '[step]') $*"; }
hdr()  { echo ""; echo "$(c '1;36' "═══ $* ═══")"; }

if [ ! -d "$SOURCE_REPO/.claude-plugin" ]; then
  echo "ERROR: SOURCE_REPO=$SOURCE_REPO does not look like the onboard repo (.claude-plugin/ missing)" >&2
  echo "       Run this script from inside the onboard repo tree." >&2
  exit 2
fi

for cmd in jq rsync; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not on PATH" >&2
    exit 2
  fi
done

echo "Source repo:  $SOURCE_REPO"
echo "Sandbox root: $SANDBOX"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

FAKE_HOME="$SANDBOX/fake-home"
mkdir -p "$FAKE_HOME/.claude/plugins/cache"
mkdir -p "$FAKE_HOME/.claude/plugins/marketplaces"

hdr "STEP 1: /plugin marketplace add sdsrss/onboard"
info "Simulating: clone GitHub repo to marketplace dir"

MARKETPLACE_DIR="$FAKE_HOME/.claude/plugins/marketplaces/sdsrss-onboard"
# Simulate clone-from-working-tree (post-push state) using rsync of tracked files +
# uncommitted changes. Mimics what `/plugin marketplace add` will see after we commit.
mkdir -p "$MARKETPLACE_DIR"
rsync -a --exclude='.git' --exclude='.code-graph' --exclude='node_modules' "$SOURCE_REPO/" "$MARKETPLACE_DIR/" 2>/dev/null
pass "working-tree snapshot → $MARKETPLACE_DIR"

MARKETPLACE_JSON="$MARKETPLACE_DIR/.claude-plugin/marketplace.json"
if [ -f "$MARKETPLACE_JSON" ]; then
  pass "marketplace.json found at .claude-plugin/marketplace.json"
else
  fail "marketplace.json NOT found at expected path .claude-plugin/marketplace.json"
  echo "BLOCKING: /plugin marketplace add fails here."
  exit 1
fi

if jq empty "$MARKETPLACE_JSON" 2>/dev/null; then
  pass "marketplace.json is valid JSON"
else
  fail "marketplace.json is not valid JSON"
  exit 1
fi

info "Validating marketplace schema (per docs)"
NAME=$(jq -r '.name // empty' "$MARKETPLACE_JSON")
OWNER_NAME=$(jq -r '.owner.name // empty' "$MARKETPLACE_JSON")
PLUGINS_LEN=$(jq -r '.plugins | length' "$MARKETPLACE_JSON" 2>/dev/null || echo 0)

[ -n "$NAME" ] && pass "name: $NAME" || fail "name field missing/empty (REQUIRED)"
[ -n "$OWNER_NAME" ] && pass "owner.name: $OWNER_NAME" || fail "owner.name missing (REQUIRED)"
[ "$PLUGINS_LEN" -ge 1 ] && pass "plugins[]: $PLUGINS_LEN entry" || fail "plugins[] must have ≥1"

case "$NAME" in
  claude-code-marketplace|claude-code-plugins|claude-plugins-official|anthropic-marketplace|anthropic-plugins|agent-skills|knowledge-work-plugins|life-sciences)
    fail "marketplace name '$NAME' is reserved by Anthropic"
    ;;
  *) pass "marketplace name not reserved" ;;
esac

# kebab-case check
if echo "$NAME" | grep -qE '^[a-z][a-z0-9-]*$'; then
  pass "marketplace name is valid kebab-case"
else
  fail "marketplace name must be kebab-case: got '$NAME'"
fi

hdr "STEP 2: /plugin install onboard"
info "Looking up plugin 'onboard' in marketplace"

PLUGIN_NAME="onboard"
PLUGIN_ENTRY=$(jq -c --arg n "$PLUGIN_NAME" '.plugins[] | select(.name == $n)' "$MARKETPLACE_JSON")
if [ -n "$PLUGIN_ENTRY" ]; then
  pass "plugin 'onboard' found in marketplace catalog"
else
  fail "plugin 'onboard' NOT in marketplace.plugins[]"
  exit 1
fi

SOURCE=$(echo "$PLUGIN_ENTRY" | jq -r '.source')
info "Resolving plugin source: $SOURCE"

case "$SOURCE" in
  "./"|".")
    PLUGIN_ROOT_IN_MKT="$MARKETPLACE_DIR"
    pass "source './' → plugin = marketplace root"
    ;;
  ./*)
    PLUGIN_ROOT_IN_MKT="$MARKETPLACE_DIR/${SOURCE#./}"
    if [ -d "$PLUGIN_ROOT_IN_MKT" ]; then
      pass "source '$SOURCE' resolves to $PLUGIN_ROOT_IN_MKT"
    else
      fail "source '$SOURCE' does NOT exist at $PLUGIN_ROOT_IN_MKT"
      exit 1
    fi
    ;;
  *)
    fail "source format not supported by sandbox: $SOURCE"
    exit 1
    ;;
esac

info "Validating plugin.json at plugin root"
PLUGIN_JSON="$PLUGIN_ROOT_IN_MKT/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
  pass "plugin.json at $PLUGIN_JSON"
else
  fail "plugin.json missing at $PLUGIN_JSON"
  exit 1
fi

jq empty "$PLUGIN_JSON" >/dev/null && pass "plugin.json is valid JSON" || fail "plugin.json invalid JSON"

P_NAME=$(jq -r '.name // empty' "$PLUGIN_JSON")
P_VER=$(jq -r '.version // empty' "$PLUGIN_JSON")
P_DESC=$(jq -r '.description // empty' "$PLUGIN_JSON")
[ -n "$P_NAME" ] && pass "plugin.name: $P_NAME" || fail "plugin.name missing"
[ -n "$P_DESC" ] && pass "plugin.description present" || warn "plugin.description recommended but missing"
[ -n "$P_VER" ] && pass "plugin.version: $P_VER (explicit)" || warn "no version → will use commit SHA"

if [ "$P_NAME" = "$PLUGIN_NAME" ]; then
  pass "plugin.json name matches marketplace entry name"
else
  fail "name mismatch: marketplace='$PLUGIN_NAME' vs plugin.json='$P_NAME'"
fi

info "Simulating: copy plugin to ~/.claude/plugins/cache/"
PLUGIN_CACHE_NAME="${PLUGIN_NAME}@${NAME}"
PLUGIN_CACHE="$FAKE_HOME/.claude/plugins/cache/$PLUGIN_CACHE_NAME"
mkdir -p "$(dirname "$PLUGIN_CACHE")"
cp -r "$PLUGIN_ROOT_IN_MKT" "$PLUGIN_CACHE"
pass "plugin cached to $PLUGIN_CACHE"

hdr "STEP 3: Component auto-discovery (CRITICAL)"
info "Claude Code scans plugin root for skills/, commands/, agents/, hooks/, .mcp.json, .lsp.json"
info "(Per docs: 'these directories must be at the plugin root level, NOT inside .claude-plugin/')"

# Test 1: skills/ directory discovery
if [ -d "$PLUGIN_CACHE/skills" ]; then
  pass "skills/ directory exists at plugin root"
  SKILLS_FOUND=0
  for skill_dir in "$PLUGIN_CACHE/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    if [ -f "$skill_dir/SKILL.md" ]; then
      pass "skill discovered: skills/$skill_name/SKILL.md → /$P_NAME:$skill_name"
      SKILLS_FOUND=$((SKILLS_FOUND+1))
    else
      warn "skills/$skill_name/ has no SKILL.md"
    fi
  done
  if [ "$SKILLS_FOUND" -eq 0 ]; then
    fail "skills/ exists but contains no <name>/SKILL.md → no slash commands registered"
  fi
else
  fail "skills/ directory MISSING at plugin root — Claude Code will not discover any skills"
fi

# Test 2: Root-level SKILL.md (NOT a standard location per docs)
if [ -f "$PLUGIN_CACHE/SKILL.md" ]; then
  warn "SKILL.md exists at plugin ROOT — this is NOT a Claude Code plugin convention"
  warn "  Standard: skills/<name>/SKILL.md OR commands/<name>.md"
  warn "  Root SKILL.md will be IGNORED by plugin discovery"
fi

# Test 3: commands/ directory
if [ -d "$PLUGIN_CACHE/commands" ]; then
  pass "commands/ directory present"
  for cmd in "$PLUGIN_CACHE/commands"/*.md; do
    [ -f "$cmd" ] || continue
    pass "  command: $(basename "$cmd" .md) → /$P_NAME:$(basename "$cmd" .md)"
  done
else
  info "commands/ not present (skills/ is preferred for new plugins per docs)"
fi

# Test 4: hooks/hooks.json (PLUGIN-level event handlers)
if [ -f "$PLUGIN_CACHE/hooks/hooks.json" ]; then
  pass "hooks/hooks.json present (plugin event handlers)"
else
  info "hooks/hooks.json not present (plugin doesn't auto-register event handlers — fine for /onboard)"
fi

# Test 5: hook scripts as skill assets (skills/onboard/hooks/, referenced by SKILL.md, NOT auto-registered)
SKILL_HOOKS_DIR="$PLUGIN_CACHE/skills/onboard/hooks"
if [ -d "$SKILL_HOOKS_DIR" ]; then
  HOOK_COUNT=$(find "$SKILL_HOOKS_DIR" -maxdepth 1 -name "*.sh" -type f | wc -l | tr -d ' ')
  if [ "$HOOK_COUNT" -eq 4 ]; then
    pass "skills/onboard/hooks/ has 4 .sh asset scripts (referenced by SKILL.md, not auto-registered)"
  else
    warn "expected 4 .sh asset scripts in skills/onboard/hooks/, found $HOOK_COUNT"
  fi
fi

# Test 6: MCP / LSP / agents
[ -f "$PLUGIN_CACHE/.mcp.json" ] && pass ".mcp.json found (MCP servers will be registered)" || info ".mcp.json not present (no MCP servers)"
[ -d "$PLUGIN_CACHE/agents" ] && pass "agents/ found" || info "agents/ not present"
[ -d "$PLUGIN_CACHE/monitors" ] && pass "monitors/ found" || info "monitors/ not present"

hdr "STEP 4: \${CLAUDE_PLUGIN_ROOT} resolution + hook script behavior"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_CACHE"
info "CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT"

# Simulate skill referring to a hook script via env var (v2.10 layout: skills/onboard/hooks/)
HOOK="${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks/guard-bash.sh"
if [ -x "$HOOK" ]; then
  pass "guard-bash.sh executable at \${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks/"
else
  # Check if it's a permission-only issue (file exists but not +x)
  if [ -f "$HOOK" ]; then
    fail "guard-bash.sh exists but not executable — git mode missing (need git update-index --chmod=+x)"
    chmod +x "$HOOK"  # auto-fix for remaining smoke tests
  else
    fail "guard-bash.sh not found at $HOOK"
    exit 1
  fi
fi

# Smoke test: safe + dangerous command via the hook
SAFE_RESULT=$(echo '{"tool_input":{"command":"ls -la"}}' | "$HOOK" 2>&1 || echo "_failed_")
if [ -z "$SAFE_RESULT" ] || ! echo "$SAFE_RESULT" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1; then
  pass "guard-bash.sh allows safe command 'ls -la'"
else
  fail "guard-bash.sh wrongly denied safe command"
fi

DANGER_RESULT=$(echo '{"tool_input":{"command":"rm -rf /"}}' | "$HOOK" 2>&1)
if echo "$DANGER_RESULT" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null 2>&1; then
  pass "guard-bash.sh denies 'rm -rf /'"
else
  fail "guard-bash.sh did NOT deny 'rm -rf /' (got: $DANGER_RESULT)"
fi

hdr "STEP 5: Slash command resolution"
info "Per docs, plugin skills are ALWAYS namespaced: /<plugin-name>:<skill-name>"

if [ -d "$PLUGIN_CACHE/skills/onboard" ] && [ -f "$PLUGIN_CACHE/skills/onboard/SKILL.md" ]; then
  pass "user would invoke: /onboard:onboard (plugin namespace) or /onboard if disambiguated"
elif [ -f "$PLUGIN_CACHE/SKILL.md" ]; then
  fail "skill at WRONG location — root SKILL.md isn't discovered by Claude Code"
  fail "user runs '/onboard:onboard' → command not found"
else
  fail "no skill anywhere — plugin install succeeds but command unusable"
fi

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo "  warn: $WARN"
echo ""
echo "Plugin cache: $PLUGIN_CACHE"
echo "  $(du -sh "$PLUGIN_CACHE" | cut -f1) in $(find "$PLUGIN_CACHE" -type f | wc -l | tr -d ' ') files"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ Sandbox test surfaced FAILURES.') Real /plugin install would not work as-is."
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
