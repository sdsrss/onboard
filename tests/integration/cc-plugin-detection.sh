#!/usr/bin/env bash
# SKILL.md spec assertions for P-A1 (v2.11): Claude Code plugin as target
# project must be recognized — Phase 1 detection signal, Phase 1 forbidden
# zone candidate, Phase 1.7 A8 recipe extension, Phase 3 conditional layout.
#
# Pure grep tests — consumer Claude isn't invoked. They lock the spec text
# in place; any future edit that drops these signals fails CI and forces
# the editor to consciously decide whether to remove plugin-as-target support.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL="$SOURCE_REPO/skills/onboard/SKILL.md"
PASS=0
FAIL=0

c() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
pass() { echo "  $(c '1;32' '✓ PASS') $*"; PASS=$((PASS+1)); }
fail() { echo "  $(c '1;31' '✗ FAIL') $*"; FAIL=$((FAIL+1)); }
hdr()  { echo ""; echo "$(c '1;36' "═══ $* ═══")"; }

if [ ! -f "$SKILL" ]; then
  echo "ERROR: SKILL.md not found at $SKILL" >&2
  exit 2
fi

hdr "P-A1 · Phase 1 detection matrix recognizes .claude-plugin/"
if grep -qE '根级.*\.claude-plugin/plugin\.json' "$SKILL"; then
  pass "Phase 1 矩阵含 '.claude-plugin/plugin.json' 根级 signal row"
else
  fail "Phase 1 矩阵缺 '.claude-plugin/plugin.json' 信号"
fi

if grep -qE 'CC plugin 栈.*v2\.11.*cc_plugin: true' "$SKILL"; then
  pass "Phase 1 矩阵描述 'CC plugin 栈' + cc_plugin 标志"
else
  fail "Phase 1 矩阵缺 'CC plugin 栈' / cc_plugin 标志描述"
fi

hdr "P-A1 · Phase 1 forbidden zone candidate (item 5)"
if grep -qE '^5\. \*\*CC plugin 项目\*\*.*cc_plugin: true.*marketplace\.json' "$SKILL"; then
  pass "Phase 1 forbidden zone candidate item 5 含 marketplace.json + cc_plugin 触发"
else
  fail "Phase 1 forbidden zone candidate item 5 缺失或形式不对"
fi

hdr "P-A1 · Phase 1.7 A8 recipe extension"
if grep -qE '\| A8 \|.*CC plugin 项目.*v2\.11.*plugin,marketplace' "$SKILL"; then
  pass "Phase 1.7 A8 recipe 含 CC plugin manifests 扩展"
else
  fail "Phase 1.7 A8 recipe 缺 CC plugin 扩展（grep 'A8.*CC plugin'）"
fi

hdr "P-A1 · Phase 3 template ## Plugin section"
if grep -qE '^## Plugin \(仅 CC plugin 项目' "$SKILL"; then
  pass "Phase 3 模板含 conditional '## Plugin' section header"
else
  fail "Phase 3 模板缺 '## Plugin' section"
fi

if grep -qE '^- Manifests:.*plugin\.json' "$SKILL"; then
  pass "## Plugin section 含 Manifests 行"
else
  fail "## Plugin section 缺 Manifests 行"
fi

if grep -qE '^- Install topology:.*plugin marketplace add' "$SKILL"; then
  pass "## Plugin section 含 Install topology 行"
else
  fail "## Plugin section 缺 Install topology 行"
fi

hdr "P-A1 · Phase 3 verification requires Plugin section for cc-plugin projects"
if grep -qE 'CC plugin 项目.*v2\.11.*## Plugin.*必须出现' "$SKILL"; then
  pass "Phase 3 验证规则强制 '## Plugin' for cc_plugin 栈"
else
  fail "Phase 3 验证缺 cc_plugin → '## Plugin' 必须出现 规则"
fi

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ cc-plugin-detection surfaced FAILURES.')"
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
