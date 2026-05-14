# /onboard Skill — Legacy Project Onboarding Protocol

旧项目接入 Claude Code 的标准化引导流程，**Skill 形式发布版**。

- 版本：v2.4（v2 系列收官版本）
- 入口命令：`/onboard`
- 形式：Skill（含 SKILL.md + 4 个预制 hook 脚本作为 supporting files）

完整流程定义见 [`SKILL.md`](./SKILL.md)。本 README 只讲安装与使用。

---

## 安装

### 方式 1：作为团队共享 Skill（推荐）

把整个 `onboard/` 目录放到项目的 `.claude/skills/` 下，作为团队共享的 Skill 与项目一起入仓：

```bash
cd <your-project-root>
mkdir -p .claude/skills
cp -r <path-to-this-package>/onboard .claude/skills/
chmod +x .claude/skills/onboard/hooks/*.sh
```

最终目录结构：

```
<your-project>/
└── .claude/
    └── skills/
        └── onboard/
            ├── SKILL.md
            ├── hooks/
            │   ├── guard-bash.sh        (executable)
            │   ├── guard-edit.sh        (executable)
            │   ├── post-edit-check.sh   (executable)
            │   └── stop-verify.sh       (executable)
            ├── settings.template.json
            ├── README.md
            └── CHANGELOG.md
```

提交到 git：

```bash
git add .claude/skills/onboard
git commit -m "chore: add /onboard skill (v2.4)"
```

团队成员 pull 后 `/onboard` 命令立即可用。

### 方式 2：作为个人全局 Skill

放到 `~/.claude/skills/onboard/`，所有项目都能用，不入仓：

```bash
mkdir -p ~/.claude/skills
cp -r <path-to-this-package>/onboard ~/.claude/skills/
chmod +x ~/.claude/skills/onboard/hooks/*.sh
```

### 方式 3：转为 Command 形式

如果你团队还没用 Skill 形式或遇到 `disable-model-invocation` 兼容性问题，可改用 Command 形式：

```bash
cp <path-to-this-package>/onboard/SKILL.md .claude/commands/onboard.md
```

注意 Command 形式下 hook 脚本会由 Phase 7 **动态生成**到 `.claude/hooks/`，不复用本包的预制脚本。如果想沿用本包脚本，手动复制：

```bash
cp -r <path-to-this-package>/onboard/hooks .claude/hooks
chmod +x .claude/hooks/*.sh
```

并按 `settings.template.json` 配置 `.claude/settings.json`（注意路径要从 `.claude/skills/onboard/hooks/` 改成 `.claude/hooks/`）。

---

## 使用

### 首次运行

在已经初始化为 git 仓库的项目根目录下：

```
/onboard
```

Claude 会先输出**执行计划**（阶段清单、预估改动文件数、规模评级、预估总耗时），等你确认后逐阶段执行。每个阶段结束输出"阶段卡片"。

### 关键阶段与你的角色

| 阶段 | 你的角色 |
|---|---|
| Phase 0 · Preflight | 看到工作区脏会提示先 stash/commit |
| Phase 1 · Discovery | 阅读《项目环境现状报告》 |
| Phase 1.5 · Blocking Decisions | 用枚举 DSL 决策 lockfile/CI/forbidden zones |
| Phase 2 · Authorization | 用 `proceed safe` / `approve install <id>` / `skip <id>` 授权 |
| Phase 3-8 · 写入与验证 | 阶段卡片审阅，必要时 abort |

### 参数

| 参数 | 用途 |
|---|---|
| `--dry-run` | 只输出"将要做什么"，不实际写入 |
| `--phase=<n>` | 只跑指定阶段（0, 0.5, 1, 1.5, 2, 3-8） |
| `--resume` | 从上次中断处继续（同版本状态文件） |
| `--update` | 升级旧版 onboarding 到当前 spec（触发 Phase 0.5 Migration） |
| `--strict` | 任何验证失败立即中止 |
| `--isolate-branch` | 在专用分支 `chore/onboarding-<ts>` 跑写入阶段，整体回滚只需切回原分支 |

### 常用场景

**新项目接入：**

```
/onboard
```

**已用旧版接入过，升级到 v2.4：**

```
/onboard --update
```

**不放心，先看一遍：**

```
/onboard --dry-run
```

**想试一遍随时可整体回滚：**

```
/onboard --isolate-branch
```

不满意：

```bash
git checkout <original-branch>
git branch -D chore/onboarding-<ts>
```

满意：

```bash
git checkout <original-branch>
git merge chore/onboarding-<ts>
```

---

## 验证 Skill 是否正常工作

安装完毕、跑过 `/onboard` 后，建议在新会话中做几个验证：

```
/hooks
```

应该看到 4 个 hook 配置已加载（PreToolUse × 2、PostToolUse、Stop）。

让 Claude 试编辑确认过的 forbidden zone：

```
请把 packages/legacy-core/foo.ts 里的 X 改成 Y
```

应该看到 `guard-edit.sh` 输出的 deny 信息：`Forbidden zone (packages/legacy-core): refuse to edit ...`。

让 Claude 写一个明显的 lint 错误：

```
请在 apps/web/src/test.ts 里加一行 const x: number = "wrong type"
```

完工时 `stop-verify.sh` 应该按 `ONBOARD_STOP_MODE` 拦截。

---

## 多语言项目支持

v2.4 一等公民支持多栈项目（如 TS 前端 + Python 后端 + Python ML）。Phase 1 自动探测每个语言栈，Phase 4 按栈分别应用 lint/format/typecheck，Phase 7 hook 通过 `.claude/onboarding-logs/stacks.json` 配置文件按文件扩展名分发。

CLAUDE.md 在多栈项目里会用 `## Stacks`（多栈变体）而非 `## Stack`，每节按栈分子节。

---

## 第三方 hook 共存

如果项目已经有团队的 Claude Code hooks（如 secret scanner），Phase 7 不会覆盖，而是采用**独立 matcher 块**策略合并：

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write|MultiEdit", "hooks": [{ "command": "/usr/local/bin/team-hook" }] },
      { "matcher": "Edit|Write|MultiEdit", "hooks": [{ "command": "${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks/post-edit-check.sh" }] }
    ]
  }
}
```

按 Claude Code 官方语义"deny 优先"——任一 hook deny 整个操作即被拒。onboard hook 满足"故障静默"约束（自身失败仅 stderr warn，不影响第三方决策）。

---

## 环境要求

- **必需**：`git`、`bash` 4+
- **Phase 7 hooks 必需**：`jq`（macOS：`brew install jq` / Ubuntu：`apt install jq`）
- **可选**：`make`、`timeout`（GNU coreutils，Linux 自带；macOS 用 `brew install coreutils` 后用 `gtimeout` 或修改脚本）
- **POSIX shell**：脚本默认 POSIX；Windows-first 项目 Phase 1 会标记跨平台风险，Phase 6/7 给替代方案或显式 defer

---

## 故障排查

**`/onboard` 不出现在命令列表里**

- 检查 SKILL.md frontmatter 中 `disable-model-invocation: true` 是否触发了已知 bug（GitHub issue #43875）。若是，临时移除该字段或改用 Command 形式。

**Skill 加载但 hook 不生效**

- 跑 `/hooks` 看配置是否实际加载
- 检查 `.claude/settings.json` 中 `${CLAUDE_PROJECT_DIR}` 路径是否被正确展开
- 验证脚本可执行：`ls -l .claude/skills/onboard/hooks/`

**guard-edit 误拦了非禁区文件**

- 检查 `ONBOARD_FORBIDDEN_PATHS` env 是否包含意外条目
- 路径必须用冒号分隔，无引号无空格

**stop-verify 频繁超时**

- 项目规模可能被低估了。在 settings.json env 中把 `ONBOARD_STOP_MODE` 改为 `light`
- 或者把 timeout 从 60 调高到 120
- 大型 monorepo 强烈推荐 light 模式，typecheck 归 pre-push 处理

**`--update` 模式下迁移失败**

- 旧状态文件已自动备份到 `.claude/onboarding-state.v<old>.json.bak`
- 检查 Phase 0.5 Migration 输出，按提示手动修复或 abort 后手动迁移

---

## 升级与版本

当前版本：**v2.4**（v2 系列收官版）。

升级到未来版本：先 pull 新的 Skill 包，然后跑 `/onboard --update`。Phase 0.5 Migration 会自动处理 schema 差异和决策继承。

完整版本历史见 [`CHANGELOG.md`](./CHANGELOG.md)。

---

## 反馈

这套 Skill 经过 4 轮 simulation-based stress testing 迭代，但真实项目仍可能暴露新的 corner case。在真实项目跑出问题，把现场（错误信息、状态文件、Phase 卡片）记录下来作为 evidence 反馈给 spec 维护者，会成为下个版本的修复点。
