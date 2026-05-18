# Phase 7 · Claude Code Hooks

> 本文件是 SKILL.md `## Phase 7` 章节的完整 spec（v3.0 起从 SKILL.md 拆出）。
> SKILL.md 原位置保留 sentinel + summary；进入此 phase 时 consumer Claude 必须 Read 本文件。
> 引用本文件 Iron Law / 元规则编号 → 见 SKILL.md 顶部 §0 总则与底部「元规则」段。
> 引用 hook 脚本 canonical 源 → `skills/onboard/hooks/<name>.sh`（与本文嵌入示例双向同步契约，per CLAUDE.md「示例脚本」failure mode）。

---

## Phase 7 · Claude Code Hooks

### 发布路径决策（v2.9 三种 install 来源 + 模式决策）

Phase 7 行为同时依两个维度决定：

#### 维度 1：install 来源（v2.9 新增 plugin 模式）

| 来源 | 检测信号 | hook 脚本位置 | hook 路径引用变量 |
|---|---|---|---|
| **Plugin**（`/plugin install onboard`） | 环境变量 `${CLAUDE_PLUGIN_ROOT}` 存在 + SKILL.md 路径含 `/.claude/plugins/cache/` | `${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks/*.sh`（plugin 缓存内，ephemeral；v2.10 起从根级 `hooks/` 移到 `skills/onboard/hooks/`） | 见下方 plugin 模式策略（默认走镜像，不写 ephemeral 路径） |
| **User-global Skill**（`install.sh install`） | SKILL.md 路径在 `~/.claude/skills/onboard/` | `${HOME}/.claude/skills/onboard/hooks/*.sh`（稳定，install.sh 管理） | `${HOME}/.claude/skills/onboard/hooks/<name>.sh` |
| **Project-shared Skill**（手动 `git clone` 到项目内） | SKILL.md 路径在 `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/` | 项目内 skill 目录 | `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks/<name>.sh` |
| **Command**（旧版兼容，`cp SKILL.md .claude/commands/onboard.md`） | 没有 skill 目录 + 有 commands 文件 | 命令运行时动态生成到 `${CLAUDE_PROJECT_DIR}/.claude/hooks/` | `${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh` |

**Plugin 模式特殊性**（v2.9）：
- `${CLAUDE_PLUGIN_ROOT}` 是 plugin 缓存目录，**每次 plugin update 会变路径**（`~/.claude/plugins/cache/onboard@<marketplace>@<ver>/`）
- 在 USER 项目的 `settings.json` 中硬编码该路径 → plugin 升级后路径失效
- **Phase 7 plugin 模式策略**：首次写 settings 时检测，问用户：
  - 选项 A（opt-in，直接引用）：用 `${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks/<name>.sh`（简洁，但 plugin 升级后 hook 短暂失效直到 Claude Code reload）
  - 选项 B（**默认**，镜像 + 执行，v2.10.1 起有 helper script）：调用 `${CLAUDE_PLUGIN_ROOT}/skills/onboard/scripts/mirror-hooks.sh` 把 4 个 hooks 镜像到稳定的 `${HOME}/.claude/onboard-runtime/hooks/`；settings 引用该镜像。脚本同时写 `${HOME}/.claude/onboard-runtime/.mirror-manifest.json` 记录 version/source/dest/mirrored_at/hooks 用于诊断；幂等，可在 plugin update 后重跑刷新。env override：`ONBOARD_MIRROR_SOURCE` / `ONBOARD_MIRROR_DEST`（测试 / 自定义部署用）
  - 默认选 B（更稳健，且 v2.10.1 起有可执行 helper 兜底）；用户显式选 A 才直接引用 ephemeral 路径

#### 维度 2：local-only vs share 模式（v2.6 新增）

| 模式 | settings 文件 | hook 路径选哪个 | .gitignore 改动 | .git/info/exclude 改动 |
|---|---|---|---|---|
| `--local-only`（默认） | `.claude/settings.local.json` | 按维度 1 install 来源选 | **不动** | 注入所有 hook 输出路径 + RUNTIME 路径 |
| `--share` | `.claude/settings.json` | 同上 | 修订（Case A/B） | 仅注入 RUNTIME 路径 |

**关键细节**：
- **plugin 模式 + local-only**（推荐默认组合）：settings.local.json 引用 `${HOME}/.claude/onboard-runtime/hooks/`（hook 镜像，默认；通过 `${CLAUDE_PLUGIN_ROOT}/skills/onboard/scripts/mirror-hooks.sh` 建立）或 `${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks/`（直接引用，opt-in）
- **install.sh 安装 + local-only**：settings.local.json 引用 `${HOME}/.claude/skills/onboard/hooks/`（最稳健）
- **share + project skill**：settings.json 引用 `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks/`，团队成员 git pull 后即可用
- `.claude/settings.local.json` 是 Claude Code 原生 per-user 配置文件，约定不入仓——业界标准做法

### Hook 深度合并策略（v2.4 关键规则，处理第三方 hook 共存）

`.claude/settings.json` 已有 hooks 时，**深度合并采用"独立 matcher 块"策略**：

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "/usr/local/bin/acme-secret-scan", "timeout": 10 }
        ]
      },
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/post-edit-check.sh", "timeout": 15 }
        ]
      }
    ]
  }
}
```

规则：
1. **不合并到同一 matcher 块的 `hooks` 数组**——避免互相影响 stdin/stderr
2. **新增独立 matcher 块**，加在已有块之后
3. Claude Code 评估事件时所有 matcher 块都触发，故障域隔离

### 第三方 hook 共存约束（Iron Law 边界）

注入的 onboard hook 必须满足：

1. **deny 优先语义**：onboard hook **不试图覆盖**第三方 hook 的 deny 决策——按 Claude Code 官方语义，任一 hook 返回 deny 整个操作就被拒，这是预期行为
2. **故障静默**：onboard hook 自身失败（如 ruff 不可用、jq 缺失）必须 **exit 0 + stderr warning**，**不能** exit 1 误阻断（Iron Law 19）
3. **只读 stdin**：onboard hook 不修改 stdin 内容，只读 `tool_input.file_path` / `tool_input.command` 等字段
4. **日志隔离**：onboard hook 写自己的 log 到 `.claude/onboarding-logs/`，不污染全局
5. **幂等且交换**：onboard hook 与第三方 hook 之间的运行顺序不影响结果

合并冲突记入状态文件 `phase_7.hook_merge_conflicts`，最终报告告知用户。

### 完整 settings.json 模板

```json
{
  "env": {
    "ONBOARD_FORBIDDEN_PATHS": "<冒号分隔 confirmed list>",
    "ONBOARD_FORBIDDEN_COMMANDS": "<换行分隔 grep -qE regex list；v2.12.0 新增>",
    "ONBOARD_TOUCHED_LOG": "${CLAUDE_PROJECT_DIR}/.claude/onboarding-logs/touched-files.txt",
    "ONBOARD_LOG_DIR": "${CLAUDE_PROJECT_DIR}/.claude/onboarding-logs",
    "ONBOARD_STOP_MODE": "light",
    "ONBOARD_STACKS_FILE": "${CLAUDE_PROJECT_DIR}/.claude/onboarding-logs/stacks.json"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "<hook 路径>/guard-bash.sh", "args": [], "timeout": 5 }
        ]
      },
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "<hook 路径>/guard-edit.sh", "args": [], "timeout": 5 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "<hook 路径>/post-edit-check.sh", "args": [], "timeout": 15 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "<hook 路径>/stop-verify.sh", "args": [], "timeout": 60 }
        ]
      }
    ]
  }
}
```

`<hook 路径>` 按发布路径决策替换（4 种 install 来源对应 4 个路径；与"维度 1"表一一对应）：
- Plugin（默认 plugin 模式镜像，**推荐**）：`${HOME}/.claude/onboard-runtime/hooks`（通过 `mirror-hooks.sh` 建立的稳定镜像）
- Plugin（opt-in，直接引用 ephemeral 路径）：`${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks`
- User-global Skill（`install.sh install`）：`${HOME}/.claude/skills/onboard/hooks`
- Project-shared Skill（`--share` 模式手动 clone）：`${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks`
- Command（旧版兼容，动态生成）：`${CLAUDE_PROJECT_DIR}/.claude/hooks`

`ONBOARD_LOG_DIR` 按模式取值（mode-aware）：share = `${CLAUDE_PROJECT_DIR}/.claude/onboarding-logs`；local-only = `${CLAUDE_PROJECT_DIR}/.claude/local-only/onboarding-logs`。hook 用此 env 决定 `stop-lint-*.log` / `post-edit-check.log` 等运行期日志的归宿——hardcode `.claude/onboarding-logs/` 会让 local-only 模式的日志泄漏到 PROJECT 工作树。

`ONBOARD_FORBIDDEN_COMMANDS`（v2.12.0 新增）：guard-bash.sh 读此 env 作 project-level command deny。**换行**分隔的 `grep -qE` (ERE) 正则列表——选换行而非冒号是为了 POSIX 字符类 `[[:space:]]` / `[[:alpha:]]` 等可以原样使用而不被分隔符撕碎。JSON 里写 `\n` 转义即可（解码后是真换行字节，bash `while read` 正确处理）。空值（默认）= 不做 project-level command 拦截，只跑 guard-bash 内置 7 条全局 deny。补足了 Iron Law 16 历史上"forbidden zones 有 global 机制，forbidden commands 没有"的对称性缺口。

### 多栈配置文件（v2.4 新增；v2.12.0 加 per-stack timeout）

多语言项目把栈配置落到 `.claude/onboarding-logs/stacks.json`（RUNTIME）：

```json
[
  {
    "id": "ts-web",
    "paths": ["apps/web"],
    "extensions": [".ts", ".tsx", ".js", ".jsx"],
    "lint_cmd": "pnpm -s lint",
    "typecheck_cmd": "pnpm -s typecheck",
    "format_check_cmd": "pnpm -s format:check"
  },
  {
    "id": "py-api",
    "paths": ["apps/api"],
    "extensions": [".py"],
    "lint_cmd": "poetry run ruff check",
    "typecheck_cmd": "poetry run mypy",
    "format_check_cmd": "poetry run ruff format --check",
    "typecheck_timeout_sec": 120
  }
]
```

hook 脚本通过 `ONBOARD_STACKS_FILE` env 读取此 JSON。

**v2.12.0 per-stack timeout 字段**（可选，缺省落回历史默认）：

| 字段 | 用在 | 默认 | 用途 |
|---|---|---|---|
| `lint_timeout_sec` | stop-verify.sh 全模式 | 30 | large monorepo 单栈 `pnpm -s lint` cold 时常 > 30s 触发 Stop block，按栈调高 |
| `typecheck_timeout_sec` | stop-verify.sh standard/strict | 45 | `mypy` / `tsc --noEmit` 冷启动经常 60-120s，medium+ 项目几乎必须调 |
| `format_timeout_sec` | stop-verify.sh strict | 30 | 全量 `prettier --check` / `ruff format --check` |
| `format_check_timeout_sec` | post-edit-check.sh | 10 | 每次 Edit 同步跑——`black --check` 冷启 5-8s，10s 默认偏紧 |

历史硬编码的 30/45/30/10s 是从 small/medium 项目的常见耗时倒推的，large 项目几乎必须覆盖。Iron Law 19（warn-only must exit 0）仍生效——超时本身不写 stderr 阻断，只走 Stop hook 的 `decision: "block"` JSON 协议。

### Stop hook 模式策略

| mode | 跑什么 | 推荐项目规模 |
|---|---|---|
| `light` | 仅对 touched files 跑 lint（按栈分发） | medium / large |
| `standard` | touched files lint + 全量 typecheck（按栈分发） | small |
| `strict` | 全量 lint + 全量 typecheck + format:check | 仅特殊场景 |

### 示例脚本 1：`guard-bash.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

BLOCK_PATTERNS=(
  'rm -rf /'
  'rm -rf ~'
  'rm -rf \$HOME'
  'chmod -R 777'
  'git push --force.*origin (main|master)'
  '> *\.env'
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
```

### 示例脚本 2：`guard-edit.sh`（多路径 + 路径边界标准化）

```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)

normalize_path() {
  local p="$1"
  p="${p#./}"
  p="${p%/}"
  printf '%s\n' "$p" | sed 's#//*#/#g'
}

PATHS=$(echo "$INPUT" | jq -r '
  [
    .tool_input.file_path?,
    .tool_input.path?,
    (.tool_input.files[]?.file_path?),
    (.tool_input.edits[]?.file_path?)
  ] | map(select(. != null and . != "")) | unique | .[]
')

[ -z "$PATHS" ] && exit 0

IFS=':' read -ra FORBIDDEN <<< "${ONBOARD_FORBIDDEN_PATHS:-}"

while IFS= read -r raw_path; do
  path=$(normalize_path "$raw_path")
  for raw_fz in "${FORBIDDEN[@]}"; do
    [ -z "$raw_fz" ] && continue
    fz=$(normalize_path "$raw_fz")
    case "$path" in
      "$fz"|"$fz"/*)
        jq -n --arg path "$path" --arg zone "$fz" '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: ("Forbidden zone (\($zone)): refuse to edit \($path)")
          }
        }'
        exit 0
        ;;
    esac
  done
done <<< "$PATHS"

exit 0
```

### 示例脚本 3：`post-edit-check.sh`（多栈分发）

> 这里是**示意**版本。生产中按 `hooks/post-edit-check.sh` 为准（含 v2.5 跨平台
> timeout shim、v2.10.2 mode-aware `ONBOARD_LOG_DIR`）。Command-mode fallback
> 重生时按 canonical 文件复制，不要按本片段重抄。

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 跨平台 timeout shim（macOS 默认无 `timeout`，有 `gtimeout`；都没就退化为直接执行）
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    timeout() { gtimeout "$@"; }
  else
    timeout() { shift; "$@"; }
  fi
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# 记录本轮触及的文件
if [ -n "${ONBOARD_TOUCHED_LOG:-}" ]; then
  mkdir -p "$(dirname "$ONBOARD_TOUCHED_LOG")"
  echo "$FILE_PATH" >> "$ONBOARD_TOUCHED_LOG"
fi

# Mode-aware 日志目录：share = .claude/onboarding-logs；local-only =
# .claude/local-only/onboarding-logs。fallback 为 share-默认保持向后兼容。
LOG_DIR="${ONBOARD_LOG_DIR:-.claude/onboarding-logs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/post-edit-check.log"

# 多栈分发：按扩展名找对应 stack 的 format_check_cmd
if [ -n "${ONBOARD_STACKS_FILE:-}" ] && [ -f "$ONBOARD_STACKS_FILE" ]; then
  EXT=".${FILE_PATH##*.}"
  CMD=$(jq -r --arg ext "$EXT" '
    .[] | select(.extensions | index($ext)) | .format_check_cmd // empty
  ' "$ONBOARD_STACKS_FILE" 2>/dev/null | head -1)

  if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
    if ! timeout 10 bash -lc "$CMD" >"$LOG" 2>&1; then
      echo "Post-edit warning: $EXT format check failed for $FILE_PATH. Stop hook will enforce later." >&2
    fi
  fi
fi

exit 0
```

### 示例脚本 4：`stop-verify.sh`（多栈分发 + 模式分支）

> 这里是**示意**版本。生产中按 `hooks/stop-verify.sh` 为准（含 v2.5 跨平台 timeout
> shim、v2.10 strict-mode `format_check_cmd` 分支、v2.10.2 mode-aware
> `ONBOARD_LOG_DIR`、v2.10.2 空格安全的 array+`printf %q` 文件名分发）。Command-mode
> fallback 重生时按 canonical 文件复制，不要按本片段重抄。

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 跨平台 timeout shim（同 post-edit-check.sh）
if ! command -v timeout >/dev/null 2>&1; then
  if command -v gtimeout >/dev/null 2>&1; then
    timeout() { gtimeout "$@"; }
  else
    echo "stop-verify: no timeout/gtimeout found, running without time limits" >&2
    timeout() { shift; "$@"; }
  fi
fi

MODE="${ONBOARD_STOP_MODE:-light}"
STACKS_FILE="${ONBOARD_STACKS_FILE:-}"
TOUCHED_LOG="${ONBOARD_TOUCHED_LOG:-}"

# 防死循环
INPUT=$(cat 2>/dev/null || echo '{}')
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
[ "$ACTIVE" = "true" ] && exit 0

LOG_DIR="${ONBOARD_LOG_DIR:-.claude/onboarding-logs}"
mkdir -p "$LOG_DIR"
FAILED=()

# 读取栈配置
if [ -z "$STACKS_FILE" ] || [ ! -f "$STACKS_FILE" ]; then
  echo "stop-verify: no stacks config, skipping" >&2
  exit 0
fi

# NL-safe 读：把 touched 文件读进数组（空格文件名不会被 word-split 拆碎）
TOUCHED_FILES=()
if [ -n "$TOUCHED_LOG" ] && [ -f "$TOUCHED_LOG" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && TOUCHED_FILES+=("$line")
  done < <(sort -u "$TOUCHED_LOG")
fi

# 没改任何文件且非 strict 模式 → 放行
if [ "${#TOUCHED_FILES[@]}" -eq 0 ] && [ "$MODE" != "strict" ]; then
  exit 0
fi

# 按栈分发
STACK_IDS=$(jq -r '.[].id' "$STACKS_FILE")
for stack_id in $STACK_IDS; do
  EXTS=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .extensions[]' "$STACKS_FILE")
  LINT_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .lint_cmd // empty' "$STACKS_FILE")
  TC_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .typecheck_cmd // empty' "$STACKS_FILE")
  FMT_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .format_check_cmd // empty' "$STACKS_FILE")

  # 筛出本栈的 touched files；用 printf %q 对每条 quote，跨 bash -lc 边界保形
  STACK_FILES_QUOTED=""
  HAVE_STACK_FILES=0
  for f in "${TOUCHED_FILES[@]}"; do
    for ext in $EXTS; do
      if [[ "$f" == *"$ext" ]]; then
        STACK_FILES_QUOTED+=" $(printf '%q' "$f")"
        HAVE_STACK_FILES=1
        break
      fi
    done
  done

  case "$MODE" in
    light)
      [ "$HAVE_STACK_FILES" -eq 0 ] && continue
      if [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD$STACK_FILES_QUOTED" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 || FAILED+=("lint:$stack_id")
      fi
      ;;
    standard)
      if [ "$HAVE_STACK_FILES" -eq 1 ] && [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD$STACK_FILES_QUOTED" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 || FAILED+=("lint:$stack_id")
      fi
      if [ -n "$TC_CMD" ] && [ "$TC_CMD" != "null" ]; then
        timeout 45 bash -lc "$TC_CMD" >"$LOG_DIR/stop-typecheck-$stack_id.log" 2>&1 || FAILED+=("typecheck:$stack_id")
      fi
      ;;
    strict)
      # strict 跑全量 lint + typecheck + format:check
      if [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 || FAILED+=("lint:$stack_id")
      fi
      if [ -n "$TC_CMD" ] && [ "$TC_CMD" != "null" ]; then
        timeout 45 bash -lc "$TC_CMD" >"$LOG_DIR/stop-typecheck-$stack_id.log" 2>&1 || FAILED+=("typecheck:$stack_id")
      fi
      if [ -n "$FMT_CMD" ] && [ "$FMT_CMD" != "null" ]; then
        timeout 30 bash -lc "$FMT_CMD" >"$LOG_DIR/stop-format-$stack_id.log" 2>&1 || FAILED+=("format:$stack_id")
      fi
      ;;
  esac
done

# 清理触及清单
[ -n "$TOUCHED_LOG" ] && [ -f "$TOUCHED_LOG" ] && : > "$TOUCHED_LOG"

if [ ${#FAILED[@]} -gt 0 ]; then
  REASON="Stop blocked [mode=$MODE]: failing checks — ${FAILED[*]}. See $LOG_DIR/"
  jq -n --arg reason "$REASON" '{
    decision: "block",
    reason: $reason
  }'
fi
exit 0
```

### 自动验证

1. `jq empty < .claude/settings.json`
2. `bash -n` 所有 hook 脚本
3. guard-bash.sh 对危险命令返回 deny
4. guard-edit.sh 对禁区路径返回 deny
5. guard-edit.sh 边界匹配不误伤（`packages/legacy` 不匹 `packages/legacy-new`）
6. guard-edit.sh 支持 MultiEdit 多路径
7. post-edit-check.sh 写入 touched-files.txt 且对失败发出 stderr warning
8. **第三方 hook 共存**（v2.4 新增）：若合并前已有 hook，验证合并后两个 matcher 块都存在且不冲突

### 人工验证

- `/hooks` 查看配置加载
- 新会话试编辑禁区文件 → 期望 guard-edit 拦截
- 新会话写一个 lint 错误 → 期望 Stop hook 按 mode 拦截
- 新会话触发第三方 hook 的禁区（如 acme-secret-scan）→ 期望被第三方拦截（onboard hook 不影响）

---

