# /onboard

> 给 legacy 项目接入 Claude Code 的标准化引导流程 —— 不强加 AI 工具给同事。

[![Release](https://img.shields.io/github/v/release/sdsrss/onboard?label=release&color=blue)](https://github.com/sdsrss/onboard/releases)
[![License](https://img.shields.io/github/license/sdsrss/onboard)](./LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-7c3aed)](https://docs.claude.com/en/docs/claude-code/plugins)
[![Tests](https://img.shields.io/badge/tests-224%20passing-brightgreen)](./tests)

**📖 其他语言: [English](./README.md) · [简体中文](./README.zh-CN.md)**

`/onboard` 是 [Claude Code](https://claude.com/claude-code) 的 Skill，把 *legacy* 项目走一遍 10 阶段标准化引导 —— 探测语言栈、生成 token 紧凑的 `CLAUDE.md`、配置 guard hooks、对齐 CI 与本地命令 —— **永远只 offer，永不自动安装系统工具**。默认 `--local-only` 模式零项目文件改动；团队成员 pull 后零感知。

当前版本：**v3.1.0**。

---

## Why?

| 问题 | `/onboard` 怎么做 |
|---|---|
| Legacy repo 上冷启动 Claude Code 要花几小时挖掘项目结构 | 10 阶段协议自动探测语言栈、lockfile、CI、forbidden zones、行为规约（Phase 1.7 8 维深度分析） |
| 5KB 的 `CLAUDE.md` 每轮对话烧 5K tokens | Extraction-first 模板，hard cap 5000 tokens（soft cap 2500），空节直接省略 |
| AI 工具入仓不应该默认强加给团队 | `--local-only` 是默认 —— 所有产物落 `.claude/local-only/` + `.git/info/exclude`；零 `.gitignore` 改动，零 commit |
| 让 LLM 随手 `brew install` / `npm i` 是灾难配方 | Iron Law 7 + 元规则 19：系统级安装 **永远 offer-only**，项目依赖改动需人类 batch AUTH |
| `--uninstall` 必须能做 | v2.8+ marker/manifest/snapshot 协议让每个 PROJECT 写入都可逆（Iron 级可逆性） |

## 核心能力

- **多语言栈一等公民**（v2.4）—— 原生支持 TypeScript 前端 + Python 后端 + ML 流水线这种混合 repo；Phase 1 按栈探测、Phase 4 按栈应用 lint/format/typecheck、Phase 7 hook 通过 `stacks.json` 按扩展名分发
- **双模式** —— `--local-only`（默认，零团队污染）/ `--share`（opt-in，OUTPUT 入仓）
- **4 个 guard hook** 通过 `.claude/settings.json` 装配 —— `guard-bash`（拦危险 shell）、`guard-edit`（forbidden-zone 保护）、`post-edit-check`（多栈 format 检查）、`stop-verify`（按 touched files 跑 lint + typecheck）
- **Doctor 模式**（`--doctor`，v2.5+）—— D1-D15 健康检查，不写任何文件，输出 `healthy | drifted | broken`
- **可逆性 Iron 级**（v2.8+）—— marker + manifest + snapshot 让 `--uninstall` 精确反向；v2.11+ 支持 `=skill`（仅 L1）和 `=all`（L1+L2+L3）双模式
- **Plugin marketplace 原生标准**（v2.9+）—— `/plugin marketplace add sdsrss/onboard` 直接装
- **Lazy-load spec**（v3.0+）—— SKILL.md 保留紧凑入口；consumer Claude 进入对应 phase 时才 Read `phases/phase-7.md` / `phases/uninstall.md` / `references/state-schema.md`（元规则 27）
- **紧凑 plan 输出**（v3.1+）—— Phase 2 / 2.5 卡片默认仅显示 Top-N 高亮项（Phase 2 Top 3、Phase 2.5 每类 Top 1-2），其余折叠为 `+N more`；`--verbose-plan` 还原全量。Phase 0 fresh run 新增首次会话授权提示。Skill description 扩展英文 trigger 表面，提升 discovery

## 快速开始

### 路径 A · Claude Code 原生 plugin marketplace（推荐）

```text
/plugin marketplace add sdsrss/onboard
/plugin install onboard
```

升级：

```text
/plugin marketplace update onboard
/plugin update onboard
```

### 路径 B · `curl | bash` 通用安装

```bash
curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash             # install
curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash -s -- update
curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash -s -- doctor
curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash -s -- uninstall
```

环境变量覆盖：`ONBOARD_TARGET=project|user` · `ONBOARD_REPO` · `ONBOARD_BRANCH` · `ONBOARD_ALLOW_DIRTY=1` · `ONBOARD_CONFIRM_UNINSTALL=yes`。

### 路径 C · 手动 `git clone`

仓库里 skill 文件位于 `skills/onboard/` 子目录（Claude Code plugin 标准布局），直接 clone 到 `~/.claude/skills/onboard` 会让 `SKILL.md` 嵌在二层目录中。先 clone 到一次性临时目录，再把 skill 子树拷过去：

```bash
SRC=$(mktemp -d -t onboard-src.XXXXXX)
git clone --depth 1 https://github.com/sdsrss/onboard.git "$SRC"
mkdir -p ~/.claude/skills
cp -r "$SRC/skills/onboard" ~/.claude/skills/
chmod +x ~/.claude/skills/onboard/hooks/*.sh ~/.claude/skills/onboard/scripts/*.sh
rm -rf "$SRC"
```

> 用 `mktemp -d` 是为了避免敲错命令后重跑出现 `fatal: destination path … already exists`。

### 首次运行

在已经 `git init` 的项目根目录下：

```text
/onboard
```

Claude 会先打印**执行计划** —— 阶段清单、当前模式（默认 `--local-only`）、改动文件预算、规模评级、总耗时预估 —— 等你确认后再开工。每个阶段结束输出"阶段卡片"。

---

## 模式

| 模式 | 何时用 | 写什么 |
|---|---|---|
| `--local-only`（默认，v2.6+） | 团队 repo 个人用 · 团队还没 AI 政策 · 你只是 OSS contributor · 试水 | `CLAUDE.local.md` · `.claude/settings.local.json` · `.claude/local-only/*` · `.git/info/exclude` markers。**零** 入仓文件改动 |
| `--share`（opt-in） | 团队已认可 AI 工具 · 个人项目想多机同步 · 团队要在 PR 中 review `CLAUDE.md` | `CLAUDE.md`（入仓）· `.claude/settings.json` · `.claude/onboarding-logs/*` · 修订 `.gitignore` · 通过 host adapter (`gh` / `glab` / `tea`) offer 开 PR/MR |

**默认 `--local-only` 的设计理由**：现实中大多数团队只有少数人试用 AI 工具。默认入仓 = 一个人的尝试强加给整个团队。默认 local-only = 零团队污染风险；团队达成共识后再升级到 `--share`。

**模式不会被静默切换**：项目中途换模式要 `/onboard --update [--share|--local-only]` + hard AUTH。

---

## 工作原理

完整协议见 [`skills/onboard/SKILL.md`](./skills/onboard/SKILL.md)。10 个阶段与你的角色：

| 阶段 | 做什么 | 你的角色 |
|---|---|---|
| 0 · Preflight | git 拓扑、host 探测、工具可用性 | 脏树 / submodule / detached HEAD 时按提示修 |
| 0.5 · Migration | 继承上次 `--update` 决策 | 首次跑跳过 |
| 1 · Discovery | 多栈探测、lockfile、CI 解析 | 阅读"项目环境现状报告" |
| 1.5 · Blocking Decisions | forbidden zone 候选、lockfile / CI 决策 | 用枚举 DSL 回答 |
| 1.7 · Deep Analysis（v2.7） | 8 维度行为档案 | 确认 / 修正发现 |
| 2 · Authorization | touch budget、写入范围 | `proceed safe` / `approve install <id>` / `skip <id>` |
| 2.5 · Install Plan（v2.7） | dev tools · system CLIs · runtimes · plugins | 四类清单 batch 授权 |
| 3 · CLAUDE.md | Extraction 模板、token-budget 强制 | Review draft（hard cap 5000 tokens） |
| 4 · Dev & Lint | 按栈集成 lint / format / typecheck | — |
| 5 · Test | Test runner 探测 + 烟测 | — |
| 6 · Commit & CI Gates | Pre-commit / pre-push hooks | — |
| 7 · Claude Code Hooks | 通过 `settings.json` 装 4 个 hook | — |
| 8 · `.gitignore` & Verification | 最终接线；`--share` 模式 offer PR/MR | — |

单阶段重跑：`/onboard --phase=<n>`。重新接入：`--resume`（同版本）或 `--update`（跨版本迁移，触发 Phase 0.5）。

---

## Hooks

4 个 hook 装在 `.claude/settings.json`（share）或 `.claude/settings.local.json`（local-only）：

| Hook | 事件 | 作用 |
|---|---|---|
| `guard-bash.sh` | `PreToolUse` / `Bash` | 拦 `rm -rf /`、force-push to main、`curl \| sh`、项目自定义 `ONBOARD_FORBIDDEN_COMMANDS` 正则表（v2.12.0+） |
| `guard-edit.sh` | `PreToolUse` / `Edit\|Write\|MultiEdit` | 阻止编辑 `ONBOARD_FORBIDDEN_PATHS`（已确认的 forbidden zones） |
| `post-edit-check.sh` | `PostToolUse` / `Edit\|Write\|MultiEdit` | 记录 touched file + 按栈跑 format check |
| `stop-verify.sh` | `Stop` | 按 `ONBOARD_STOP_MODE`（`light` / `standard` / `strict`）对 touched files 跑 lint + typecheck |

4 个 hook 全部满足 **Iron Law 15**（exit 0 + stdout JSON，二选一不能混）和 **Iron Law 19**（warn-only 检查必须 exit 0）。

**第三方 hook 共存**（v2.5+）：独立 matcher-block 策略 —— onboard 不覆盖已有 hook，两者并列；按 Claude Code 官方语义"deny 优先"。

**Plugin 安装路径注意**：`${CLAUDE_PLUGIN_ROOT}` 是 ephemeral 路径（每次 plugin update 都变）。Phase 7 默认调用 `scripts/mirror-hooks.sh`（v2.10.1+，idempotent）镜像 hook 到稳定路径 `~/.claude/onboard-runtime/hooks/`；`settings.json` 引用该镜像。

---

## Doctor / Update / Uninstall

```text
/onboard --doctor              # D1-D15 健康检查，不写任何文件
/onboard --update              # 跨版本迁移（触发 Phase 0.5）
/onboard --update --local-only # 从 --share 撤回 local-only
/onboard --dry-run             # 预览，不写
/onboard --uninstall           # 移除本项目的所有 onboard 写入
/onboard --uninstall=skill     # 只卸 L1 user-global skill，保留项目配置
```

**Uninstall 协议**（v2.8+；v2.11+ 三层模型）：`=skill` 清 L1 user-global（`~/.claude/skills/onboard/` + plugin cache + mirror），通过 keeper-rewrite（`.claude/onboard-keeper/`）保留项目侧 L2（settings hook 引用）和 L3（hook 脚本）。`=all` 清三层全部。Marker / manifest / snapshot 让每个 PROJECT 写入都可逆；用户可选 `restore-snapshot` 恢复到 onboard 首次写入前的状态。

---

## 环境要求

| 平台 | 状态 | 备注 |
|---|---|---|
| Linux | 一等公民 | — |
| macOS | 一等公民（v2.5+） | 推荐 `brew install coreutils` 提供 `gtimeout` |
| WSL2 | 一等公民 | 等价于 Linux |
| Windows 原生 | 不支持 | 用 WSL2 替代 |

**工具**：`git` · `bash 3.2+` · `jq`（全部必需 —— 安装器在缺少 jq 时直接拒装，因为 guard hook 全部 shell out 到 jq；缺 jq 会让 `permissionDecision` deny 负载静默失效）· `coreutils` on macOS（强烈推荐）· `make`（可选）。

**Git 托管平台 adapter**（Phase 8 PR/MR offer，永不自动执行）：GitHub（`gh`）· GitLab（`glab`）· Gitea/Forgejo/Codeberg（`tea`）；Bitbucket 和未识别 host fallback 到 web URL。

---

## 验证

装完 + 跑过 `/onboard` 后：

```text
/hooks
```

应该看到 4 条 hook 配置（PreToolUse × 2、PostToolUse、Stop）。试一次 forbidden-zone 编辑确认 `guard-edit.sh` 拦截；制造一个明显 lint 错确认 `stop-verify.sh` 在 Stop 事件被阻止。

跑仓库内测试：

```bash
bash tests/run.sh
# 10 个测试 / 224 个断言 / 0 fail
```

---

## 故障排查

| 症状 | 检查 |
|---|---|
| `/onboard` 不出现在命令列表 | SKILL.md frontmatter `disable-model-invocation: true` 可能触发 [anthropic#43875](https://github.com/anthropics/claude-code/issues/43875)；临时移除该字段或切 Command 形式 |
| Hook 不生效 | `/hooks` 确认加载；检查 `${CLAUDE_PROJECT_DIR}` 是否被正确展开；`ls -l .claude/skills/onboard/hooks/` 确认可执行 |
| `guard-edit` 误拦 | 检查 `ONBOARD_FORBIDDEN_PATHS` env（冒号分隔，无引号无空格） |
| `stop-verify` 超时频繁 | `ONBOARD_STOP_MODE` 降到 `light`，或在 `stacks.json` 调每栈的 `lint_timeout_sec` / `typecheck_timeout_sec`（v2.12+） |
| `--update` 迁移失败 | 旧状态备份在 `.claude/onboarding-state.v<old>.json.bak`；按 Phase 0.5 输出诊断 |

完整故障排查 + 边界 case 见 [`SKILL.md`](./skills/onboard/SKILL.md) § "异常处理"。

---

## 贡献

本仓库经过 v2 系列 **4 轮 simulation-based stress testing 迭代**（v2.0 → v2.4 是 net-line-decrease 里程碑；v2.5-v2.12 基于真实压测 evidence 增加能力）。v3 系列从 C1 SKILL.md 浅拆开始（lazy-load 契约）。任何改动遵循同一协议：

1. 跑当前版本（simulated 或 real）
2. 给每个问题编号（P-A、P-B、…），打 Critical / High / Medium / Low 严重度
3. 用书面 rationale 接受 / 拒绝
4. 接受的合并到下一版本

不接受 speculative 特性。仓库维护约定（Iron Laws / 元规则 / 验证命令 / 文件四分类 / 多栈规则）见 [`CLAUDE.md`](./CLAUDE.md)。

**Bug 上报**：抓现场 evidence（错误信息、状态文件、Phase 卡片）开 issue。基于 evidence 的 PR 欢迎。

---

## License

[MIT](./LICENSE) — `Copyright (c) sds`.

---

## 相关链接

- [完整协议规范（SKILL.md）](./skills/onboard/SKILL.md) · [Phase 7 hooks](./skills/onboard/phases/phase-7.md) · [Uninstall mode](./skills/onboard/phases/uninstall.md) · [State schema](./skills/onboard/references/state-schema.md)
- [Changelog](./CHANGELOG.md)（完整版本历史；v3.1.0 = 当前）
- [Releases](https://github.com/sdsrss/onboard/releases)
- [Issues](https://github.com/sdsrss/onboard/issues)
- [Claude Code 文档](https://docs.claude.com/en/docs/claude-code/overview)
- [Claude Code plugins 文档](https://docs.claude.com/en/docs/claude-code/plugins)
