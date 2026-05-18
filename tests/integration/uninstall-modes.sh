#!/usr/bin/env bash
# SKILL.md spec + install.sh integration assertions for v2.11 uninstall redesign:
#   P-A6: `/onboard --uninstall[=skill|all]` parameterization, 3-layer model
#   P-A7: local-only mode hook localization to .claude/onboard-keeper/
#   P-A10: non-interactive convention (ONBOARD_CONFIRM_UNINSTALL=yes by caller)
#
# install.sh-level env validation (skill/all/bogus) lives in install-roundtrip.sh
# step 5b — this file locks down the SKILL.md spec contract that consumer Claude
# executes.

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

hdr "P-A6 · argument-hint declares --uninstall[=skill|all]"
if grep -qE 'argument-hint:.*--uninstall\[=skill\|all\]' "$SKILL"; then
  pass "frontmatter argument-hint 含 '--uninstall[=skill|all]'"
else
  fail "frontmatter argument-hint 缺 '--uninstall[=skill|all]'"
fi

hdr "P-A6 · 参数解析 documents skill vs all + backward-compat"
if grep -qE -- '--uninstall\[=skill\|all\].*v2\.8 新增.*v2\.11 参数化' "$SKILL"; then
  pass "参数解析 line 含 v2.8 新增 + v2.11 参数化标记"
else
  fail "参数解析 line 缺 v2.8/v2.11 双版本标记"
fi
if grep -qE '裸 .*--uninstall.* 等价.*向后兼容' "$SKILL"; then
  pass "参数解析显式声明裸 --uninstall 向后兼容（≡ =all）"
else
  fail "参数解析缺 '裸 --uninstall ≡ =all' 向后兼容声明"
fi

hdr "P-A6 · Uninstall Mode section was rewritten (v2.11 three-layer)"
if grep -qE '^## Uninstall Mode.*v2\.11 三层模型' "$SKILL"; then
  pass "Uninstall Mode 章节 header 标 'v2.11 三层模型'"
else
  fail "Uninstall Mode 章节 header 未标 v2.11 三层模型 重写"
fi
if grep -qE '^### 三层状态模型' "$SKILL"; then
  pass "三层状态模型 sub-section 存在"
else
  fail "三层状态模型 sub-section 缺失"
fi
for layer in 'L1 user-global' 'L2 project-config' 'L3 project-files'; do
  if grep -qE "\\*\\*$layer\\*\\*" "$SKILL"; then
    pass "三层模型含 '$layer'"
  else
    fail "三层模型缺 '$layer'"
  fi
done

hdr 'P-A6 · =skill and =all flows both documented'
if grep -qE '模式 1.*--uninstall=skill.* 流程' "$SKILL"; then
  pass "模式 1 (=skill) 流程章节存在"
else
  fail "模式 1 (=skill) 流程章节缺失"
fi
if grep -qE '模式 2.*--uninstall=all.* 流程' "$SKILL"; then
  pass "模式 2 (=all) 流程章节存在"
else
  fail "模式 2 (=all) 流程章节缺失"
fi

hdr "P-A6 · 默认值约定 (v2.11 backward-compat)"
if grep -qE '^### 默认值约定.*v2\.11' "$SKILL"; then
  pass "默认值约定 sub-section 存在 + 标 v2.11"
else
  fail "默认值约定 sub-section 缺失或未标 v2.11"
fi

hdr "P-A7 · local-only hook localization → .claude/onboard-keeper/"
if grep -qE 'onboard-keeper/hooks/' "$SKILL"; then
  pass "Uninstall Mode 引用 .claude/onboard-keeper/hooks/ 路径"
else
  fail "Uninstall Mode 缺 .claude/onboard-keeper/ keeper 路径"
fi
if grep -qE 'jq atomic.*tmp.*mv' "$SKILL" || grep -qE 'jq.*tmp \+ mv' "$SKILL"; then
  pass "Uninstall Mode 含 atomic jq edit (tmp + mv) 说明"
else
  fail "Uninstall Mode 缺 atomic jq edit (tmp + mv) 说明"
fi
if grep -qE 'snapshot.*元规则 21|元规则 21.*snapshot' "$SKILL"; then
  pass "Uninstall Mode 引用 元规则 21（snapshot before edit）"
else
  fail "Uninstall Mode 缺 元规则 21 snapshot 引用"
fi

hdr "P-A7 · Mode model table row (keeper)"
if grep -qE 'Skill 卸载后保留的 hook 脚本副本.*v2\.11.*onboard-keeper' "$SKILL"; then
  pass "Mode model 文件归宿表含 keeper 行 + v2.11 标记"
else
  fail "Mode model 文件归宿表缺 keeper 行"
fi

hdr "P-A6/P-A7 · new 元规则 24/25/26"
if grep -qE '^24\. \*\*（v2\.11）uninstall 三层语义' "$SKILL"; then
  pass "元规则 24 存在（uninstall 三层语义）"
else
  fail "元规则 24 缺失或形式不对"
fi
if grep -qE '^25\. \*\*（v2\.11）uninstall 分层各自 hard AUTH' "$SKILL"; then
  pass "元规则 25 存在（分层各自 hard AUTH）"
else
  fail "元规则 25 缺失或形式不对"
fi
if grep -qE '^26\. \*\*（v2\.11）skill 卸载必须保 hook 路径连续性' "$SKILL"; then
  pass "元规则 26 存在（skill 卸载 hook 路径连续性）"
else
  fail "元规则 26 缺失或形式不对"
fi

hdr "P-A6 · 元规则 22 updated for skill|all split"
if grep -qE '^22\. \*\*（v2\.8 / v2\.11 修订）卸载是单方向不可逆操作\*\*' "$SKILL"; then
  pass "元规则 22 标 'v2.8 / v2.11 修订'"
else
  fail "元规则 22 未标 v2.11 修订（应说明 =all vs =skill AUTH 颗粒度差异）"
fi

hdr "P-A6 · 元规则 header bumped to v2.11 共 26 条"
if grep -qE '^## 元规则.*v2\.11 共 26 条' "$SKILL"; then
  pass "元规则 header 标 'v2.11 共 26 条'"
else
  fail "元规则 header 仍是旧版（未 bump 到 v2.11 共 26 条）"
fi

hdr "P-A10 · non-interactive convention documented"
if grep -qE 'ONBOARD_CONFIRM_UNINSTALL=yes.*ONBOARD_UNINSTALL_MODE=skill' "$SKILL"; then
  pass "Uninstall Mode 含非交互调用 install.sh 的命令样例"
else
  fail "Uninstall Mode 缺 ONBOARD_CONFIRM_UNINSTALL + ONBOARD_UNINSTALL_MODE 调用样例"
fi

hdr "FINAL REPORT"
echo "  pass: $PASS"
echo "  fail: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "$(c '1;31' '✗ uninstall-modes surfaced FAILURES.')"
  exit 1
else
  echo "$(c '1;32' '✓ All checks passed.')"
fi
