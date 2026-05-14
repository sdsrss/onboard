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
| Phase 0 · Preflight | 看到工作区脏会提示先 stash/commit；team/solo 信号 + git host 自动探测 |
| Phase 1 · Discovery | 阅读《项目环境现状报告》（多栈识别 + lockfile / CI 分析） |
| Phase 1.5 · Blocking Decisions | 用枚举 DSL 决策 lockfile/CI/forbidden zones |
| **Phase 1.7 · Deep Analysis** (v2.7) | 阅读 8 维度分析结果（构建命令 / 依赖方向 / 行为禁令 / 覆盖率信号 / 等）|
| Phase 2 · Authorization | 用 `proceed safe` / `approve install <id>` / `skip <id>` 授权 |
| **Phase 2.5 · Install Plan** (v2.7) | 四类清单 batch 授权：dev tools / system CLIs / runtimes / Claude Code plugins |
| Phase 3-8 · 写入与验证 | 阶段卡片审阅，必要时 abort；Phase 3 token 预算检查 |

### 参数

| 参数 | 用途 |
|---|---|
| `--local-only` | **v2.6 新增，默认模式**：所有产物走 `.local.*` 约定 + `.git/info/exclude`，团队成员 pull 后零可见，零 .gitignore 改动 |
| `--share` | **v2.6 新增**：team-share 模式（v2.5 及之前的默认）。OUTPUT 文件入仓共享。需要团队对 AI 工具有共识 |
| `--dry-run` | 只输出"将要做什么"，不实际写入 |
| `--phase=<n>` | 只跑指定阶段（0, 0.5, 1, 1.5, 1.7, 2, 2.5, 3-8） |
| `--resume` | 从上次中断处继续（同版本状态文件） |
| `--update` | 升级旧版 onboarding 到当前 spec（触发 Phase 0.5 Migration） |
| `--strict` | 任何验证失败立即中止 |
| `--isolate-branch` | 在专用分支跑写入阶段（**仅 `--share` 模式有意义**，分支前缀自动从团队习惯探测，fallback `chore/`） |
| `--doctor` | **v2.5 新增**：诊断模式。不跑任何 Phase，只检查已有 onboarding 健康度（D1-D14 共 14 项），输出 `healthy \| drifted \| broken` |
| `--allow-large-claude-md` | **v2.7 新增**：覆盖 CLAUDE.md token 硬上限 5000。Phase 3 触发 hard AUTH 才能写超大 CLAUDE.md |

### 决策树：我该用哪个模式？

```
我要 onboard 一个项目 →
│
├─ 个人项目 / 只有我一个 contributor？
│  └─ 默认 --local-only（不入仓也行，方便干净）
│     或者 --share（如果想多机同步配置）
│
├─ 团队项目，团队还没 AI 政策？
│  ├─ 只是我个人试 → --local-only（默认，零团队污染）
│  └─ 想推动团队用 AI → --share --isolate-branch（v2.6 自动开 PR / MR）
│
├─ 团队项目，团队已禁止 AI 工具入仓？
│  └─ --local-only（强制，唯一合规选项）
│
└─ OSS 项目我只是 contributor？
   └─ --local-only（除非 maintainer 明确同意）
```

**默认 `--local-only` 的设计理由**：现实里大多数公司不全员支持 AI 工具，少数人试用。默认不入仓 = 不强加 AI 工具给同事 = 零团队污染风险。

### 常用场景

**首次接入（默认 local-only，安全无副作用）：**

```
/onboard
```

**确定团队接受 AI，想入仓共享：**

```
/onboard --share --isolate-branch
```

`--isolate-branch` 会自动建分支（前缀按团队习惯，比如 `infra/onboarding-...`），Phase 8 末尾按你的 git host (GitHub/GitLab/Gitea) offer 对应的 PR/MR 命令——只 offer 不自动执行。

**已用旧版接入过，升级到 v2.6（保持原 mode）：**

```
/onboard --update
```

**已 share 模式 onboard，想撤回到 local-only：**

```
/onboard --update --local-only
```

会触发 hard AUTH——撤回涉及 .gitignore 修订 + 取消 git tracking。

**不放心，先看一遍：**

```
/onboard --dry-run
```

**share 模式的整体回滚 / 接受：**

不满意：

```bash
git checkout <original-branch>
git branch -D <prefix>/onboarding-<ts>
```

满意（开 PR/MR 走团队 review）：

```bash
# GitHub
gh pr create --base <original-branch> --draft

# GitLab
glab mr create --target-branch <original-branch> --draft

# Gitea
tea pulls create --base <original-branch>
```

Phase 8 末尾会自动 offer 上面这条命令（含自动生成的 title + body），你确认后执行。

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

### 支持矩阵（v2.5 明确）

| 平台 | 支持级别 | 备注 |
|---|---|---|
| Linux | 一等公民 | `timeout` 自带 |
| macOS | 一等公民（v2.5 起） | 需 `brew install coreutils` 提供 `gtimeout`；hook 脚本自动 fallback。无 coreutils 时退化为无超时（仍可用，但失去 hook 卡死保护） |
| WSL2 | 一等公民 | 与 Linux 等价 |
| Windows 原生 | 不支持 | Phase 1 会标记跨平台风险并 defer 写入；用 WSL2 替代 |

### 工具依赖

- **必需**：`git`、`bash` 3.2+（macOS 自带版本可用，但部分高级特性需 bash 4+）
- **Phase 7 hooks 必需**：`jq`（macOS：`brew install jq` / Ubuntu：`apt install jq`）
- **强烈建议**：`coreutils`（macOS：`brew install coreutils`，提供 `gtimeout`）
- **可选**：`make`

### Git 托管平台支持（v2.6）

| 平台 | CLI | 自动检测 | PR/MR 自动 offer | 模板路径 |
|---|---|---|---|---|
| GitHub | `gh` | ✓（远程 URL 含 `github.com`） | ✓ | `.github/PULL_REQUEST_TEMPLATE.md` |
| GitLab | `glab` | ✓（远程 URL 含 `gitlab.`） | ✓ | `.gitlab/merge_request_templates/*.md` |
| Gitea / Forgejo / Codeberg | `tea` | ✓ | ✓ | `.gitea/PULL_REQUEST_TEMPLATE.md` |
| Bitbucket | — | ✓ | fallback web URL | — |
| 自托管未识别 | — | unknown | fallback web URL | — |

未装对应 CLI 时 fallback：Phase 8 末尾给出 web URL 让你手动开 PR/MR，附自动生成的 title 与 body 文本。**Onboard 永不自动执行开 PR/MR**——只 offer，你确认后才跑（开 PR 涉及外部系统状态变更，属 §5 hard AUTH）。

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

## 与 `claudemd` 插件共存（v2.5）

如果你的环境装了 [`claudemd` 插件](https://github.com/anthropics/claude-code)（生态里专门管 CLAUDE.md 规范的工具），Phase 3 会探测它的存在：

- **claudemd 已装** → onboard 只生成 onboard 特有的节：`## Stacks` / `## Forbidden` / `## Testing` / `## Change Policy`；不动 claudemd 管辖的规范节（如 banned-vocab、specificity 等）
- **未装** → 走完整模板

两个工具的"归属节"会写入 `.claude/onboarding-state.json` 的 `phase_3.claudemd_coexistence`，后续 `--update` 会保持这个分工。

---

## 升级与版本

当前版本：**v2.7**。

**v2.7 新增能力一览**：
- 深度项目认知（Phase 1.7）：构建/测试命令、目录依赖方向、代码规范、行为禁令、覆盖率信号 8 维度自动抽取
- 提取式 CLAUDE.md：token 预算 soft 2500 / hard 5000；每行 load-bearing；空节不写
- Install Plan（Phase 2.5）：dev tools / system CLIs / language runtimes / Claude Code plugins 四类清单 batch 授权
- Claude Code plugin 推荐矩阵（15 项硬编码 + open recommendation fallback）

**从 v2.6 升级**：
- `--update` 会触发 Phase 1.7 / 2.5 / 3 重跑（Phase 0.5 自动标 `update_phases`）
- CLAUDE.md 会被重写（旧版备份到 `.claude/onboarding-logs/CLAUDE.md.v26.bak`）→ Phase 3 触发 hard AUTH
- 若新草稿 ≥ 5000 token → 拒绝写入，需 `--allow-large-claude-md` 覆盖

**从 v2.5 升级**：
- 默认行为反转：v2.5 默认入仓，v2.6/v2.7 默认 local-only
- 已有 v2.5 onboarding 的项目 `--update` 后**保留 share 模式**（不会偷偷改默认）
- 想撤回到 local-only：`/onboard --update --local-only`（会触发 hard AUTH）

升级到未来版本：先 pull 新的 Skill 包，然后跑 `/onboard --update`。Phase 0.5 Migration 会自动处理 schema 差异和决策继承。

完整版本历史见 [`CHANGELOG.md`](./CHANGELOG.md)。

---

## 反馈

这套 Skill 经过 4 轮 simulation-based stress testing 迭代，但真实项目仍可能暴露新的 corner case。在真实项目跑出问题，把现场（错误信息、状态文件、Phase 卡片）记录下来作为 evidence 反馈给 spec 维护者，会成为下个版本的修复点。
