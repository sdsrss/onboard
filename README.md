# /onboard Skill — Legacy Project Onboarding Protocol

旧项目接入 Claude Code 的标准化引导流程，**Skill 形式发布版**。

- 版本：v2.4（v2 系列收官版本）
- 入口命令：`/onboard`
- 形式：Skill（含 SKILL.md + 4 个预制 hook 脚本作为 supporting files）

完整流程定义见 [`SKILL.md`](./SKILL.md)。本 README 只讲安装与使用。

---

## 安装

三条等价的安装路径，按你的 Claude Code 版本与团队习惯选一条。

### 路径 A · Claude Code 原生 plugin marketplace（推荐，v2.9+）

完全符合 Claude Code 插件标准。两条命令：

```
/plugin marketplace add sdsrss/onboard
/plugin install onboard
```

第一条把本 GitHub 仓库注册为 plugin marketplace（仓库根有 `.claude-plugin/marketplace.json`，Claude Code 据此发现 plugin）。第二条从该 marketplace 安装 onboard plugin（`.claude-plugin/plugin.json` 描述 plugin 本身）。安装后 `/onboard` 命令立即可用。

升级：

```
/plugin marketplace update onboard
/plugin update onboard
```

卸载：

```
# 先在每个 onboarded 的项目里跑这一步（清理项目级痕迹）
cd <project> && /onboard --uninstall
# 然后卸载全局 plugin
/plugin uninstall onboard
# （可选）移除 marketplace 注册
/plugin marketplace remove onboard
```

**plugin 缓存位置**：`~/.claude/plugins/cache/onboard@onboard/`（路径含 marketplace 名）。每次 `/plugin update` 会变；onboard 内部用 `${CLAUDE_PLUGIN_ROOT}` 变量引用，user settings.json 默认走稳定镜像（详见 [Plugin 路径行为](#plugin-路径行为)）。

### 路径 B · `curl | bash` 通用安装（v2.8+）

不依赖 `/plugin` 命令支持，任何 Claude Code 版本可用：

```bash
# 安装到 ~/.claude/skills/onboard/
curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash

# 升级
curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash -s -- update

# 卸载（先在每个项目里跑 /onboard --uninstall）
curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash -s -- uninstall

# 健康检查（不改任何状态）
curl -sSL https://raw.githubusercontent.com/sdsrss/onboard/main/install.sh | bash -s -- doctor
```

安装到项目内（团队共享，需要团队接受 AI 工具入仓）：

```bash
ONBOARD_TARGET=project ./install.sh install
git add .claude/skills/onboard
git commit -m "chore: add /onboard skill"
```

环境变量覆盖：

| 变量 | 用途 | 默认 |
|---|---|---|
| `ONBOARD_REPO` | git URL | `https://github.com/sdsrss/onboard.git` |
| `ONBOARD_BRANCH` | 分支或 tag | `main` |
| `ONBOARD_TARGET` | `user`（`~/.claude/skills/`）/ `project`（`./.claude/skills/`） | `user` |
| `ONBOARD_ALLOW_DIRTY` | `1` 跳过 update 的脏树检查 | unset |
| `ONBOARD_CONFIRM_UNINSTALL` | `yes` 跳过 uninstall 交互确认 | unset |

### 路径 C · 手动 git clone（最透明）

```bash
# 全局
git clone --depth 1 https://github.com/sdsrss/onboard.git ~/.claude/skills/onboard
chmod +x ~/.claude/skills/onboard/hooks/*.sh

# 升级
cd ~/.claude/skills/onboard && git pull && chmod +x hooks/*.sh

# 卸载
rm -rf ~/.claude/skills/onboard
```

### 仓库布局（v2.10 plugin-canonical）

```
<repo>/                              # = marketplace root = plugin root
├── .claude-plugin/
│   ├── marketplace.json            # /plugin marketplace add 入口
│   └── plugin.json                 # plugin 元数据
├── skills/onboard/                 # 标准 plugin 内 skill 目录
│   ├── SKILL.md                    # 协议规范（v2.10 起从根移到这里）
│   ├── hooks/                      # skill 内 hook 资源
│   │   ├── guard-bash.sh           (executable in git index)
│   │   ├── guard-edit.sh
│   │   ├── post-edit-check.sh
│   │   └── stop-verify.sh
│   ├── settings.template.json      # share 模式参考
│   └── settings.local.template.json # local-only 模式参考
├── install.sh                      # 通用安装器（curl | bash）
├── tests/                          # in-repo 沙箱测试（87 assertions / 4 tests, bash tests/run.sh）
└── README.md / CHANGELOG.md / LICENSE / CLAUDE.md
```

**install.sh 安装后的形状**（target = `~/.claude/skills/onboard/`）：

```
~/.claude/skills/onboard/            # install.sh 复制 skills/onboard/* 的内容
├── SKILL.md
├── hooks/
├── settings.template.json
├── settings.local.template.json
└── (+ README / CHANGELOG / LICENSE 副本)
```

**plugin 安装后的形状**（cache = `~/.claude/plugins/cache/onboard@onboard/`）：

```
~/.claude/plugins/cache/onboard@onboard/  # 完整 repo 镜像
├── .claude-plugin/
├── skills/onboard/SKILL.md
├── skills/onboard/hooks/
└── ...
```

### 项目级 vs 全局安装

| 维度 | 全局（`~/.claude/skills/` 或 plugin 缓存） | 项目级（`./.claude/skills/`） |
|---|---|---|
| 入仓 | 否 | 是（团队共享） |
| 多机同步 | 各机器各装 | git pull 即同步 |
| 升级 | 一次升级所有项目可用 | 每个项目 PR 升级 |
| 团队拒绝 AI 时 | 仍可用（个人） | 不该用（污染团队） |
| 推荐 | local-only 模式 / 个人试水 | share 模式 / 团队认可后 |

**强烈建议默认全局安装**（路径 A 或 B）——配合 `/onboard --local-only`（v2.6+ 默认）做到对团队 0 影响。

### Plugin 路径行为

通过路径 A 安装时，onboard 文件位于 plugin 缓存 `~/.claude/plugins/cache/onboard@onboard/`。**该路径含版本号，每次 `/plugin update` 会变**。

为避免 user settings.json 中硬编码该不稳定路径，onboard v2.9 在 plugin 模式下 Phase 7 **默认镜像** hook 脚本到稳定位置 `~/.claude/onboard-runtime/hooks/`，user settings 引用该镜像而非 plugin 缓存。Plugin 升级后用户跑 `/onboard --update` 同步新 hooks 到镜像。

要直接用 `${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks/<name>.sh`（不建镜像）可在 `/onboard` 启动时显式选择 "direct" 选项——接受 plugin 升级期间 Claude Code 重载前 hooks 短暂失效的风险。

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
| `--doctor` | **v2.5 新增**：诊断模式。不跑任何 Phase，只检查已有 onboarding 健康度（D1-D15 共 15 项），输出 `healthy \| drifted \| broken` |
| `--uninstall` | **v2.8 新增**：项目级卸载。按 marker / manifest 反向移除 onboard 在本项目的所有写入；提供 snapshot restore 选项 |
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

## 卸载 / 恢复（v2.8 新增）

`/onboard --uninstall` 反向移除 onboard 在本项目写入的所有内容。**先做项目级，再做全局**。

### 项目级卸载

在已 onboarded 的项目里：

```
/onboard --uninstall
```

按 manifest + marker 准确识别 onboard 写过的内容并展示卸载预览，包括 snapshot restore 候选。

三种选择：
- `Y`：按 marker / manifest 精准移除（保留用户在 marker 块外的内容）
- `restore-snapshot`：恢复到 onboard 首次写入前的快照（最干净的回退）
- `n`：取消，不动任何东西

### 全局卸载

```bash
# install.sh 路径
~/.claude/skills/onboard/install.sh uninstall

# /plugin 路径
/plugin uninstall onboard
```

⚠️ **顺序至关重要**：先在每个 onboarded 的项目里 `/onboard --uninstall`，**再**做全局卸载。否则 `/onboard` 命令消失后只能手动清理。

### Marker / Manifest 协议（可逆性 Iron 级）

onboard 任何 PROJECT 文件写入都加 marker：

- Line-based（`.gitignore` / `.git/info/exclude`）：`# >>> /onboard v<ver> >>>` ... `# <<< /onboard v<ver> <<<`
- Markdown（`CLAUDE.md` / `CLAUDE.local.md`）：`<!-- >>> /onboard v<ver> >>> -->` ... `<!-- <<< /onboard v<ver> <<< -->`
- JSON（`settings.json` / `settings.local.json`）：每条目 `_onboard_managed: true` + `_onboard_version`

权威清单：`.claude/local-only/onboard-manifest.json`（local-only）或 `.claude/onboard-manifest.json`（share）记录所有 managed files + paths + snapshots dir。

---

## 升级与版本

当前版本：**v2.10.2**。

**v2.10.2 改进**（v2.10.1 后全仓审计找到的 10 条 P-B fixes，2 条 HIGH / 4 MED / 4 LOW，不破坏兼容）：
- **HIGH**：`guard-bash.sh` deny 模式从子串改为锚定 — 之前 `rm -rf /` 作子串匹配把所有 `rm -rf /<subpath>`（如 `/tmp/foo`、`/var/log/old`）一起误拒；新版仅在 `/` / `~` / `$HOME` 是删除目标本体或链式起始时 deny
- **HIGH**：新增 `ONBOARD_LOG_DIR` env，`post-edit-check.sh` / `stop-verify.sh` 用它决定 `stop-lint-*.log` / `post-edit-check.log` 归宿。之前硬编码 `.claude/onboarding-logs/` 在 local-only 模式下泄漏到 PROJECT 工作树（meta-rule 13 违规）
- **MED**：`stop-verify.sh` 改用数组 + `printf %q` 跨 `bash -lc` 边界传文件名 — 之前 space-join + word-split 会把 `src/has space.ts` 拆成 `has` / `space.ts` 两个错误参数
- **MED**：SKILL.md 内嵌 `示例脚本 3/4` 同步到 canonical hooks/*.sh（含 v2.5 跨平台 timeout、v2.10 strict-mode `FMT_CMD`、v2.10.2 `ONBOARD_LOG_DIR` + 空格安全）；加 canonical pointer 防 Command-mode fallback 退化
- **MED**：Doctor mode sample output 补 D15（uninstall reversibility）；Phase 7 hook 路径替换表从 2 项扩到 5 项覆盖所有 install 来源
- **LOW**：settings 模板 `_onboard_version` 8 处从 `2.8` 同步到 `2.10.2`；4 个 test 脚本 git index `100644 → 100755`；`install.sh do_uninstall` 加 path sanity guard
- 新增 `tests/integration/hook-behavior.sh`（22 assertions）锁住 P-B1/B2/B4 不复发；`tests/run.sh` 5 个 test / 109 assertions / 0 fail

**从 v2.10.1 升级**：纯补丁，无 schema / 行为破坏。已 onboarded 项目需要把 `ONBOARD_LOG_DIR` 加入 settings.local.json / settings.json env 块（local-only 模式尤其需要，否则日志仍写到 share 路径）— 跑 `/onboard --update` 自动迁移；或手动从模板 `skills/onboard/settings*.template.json` 复制对应那行。

**从 v2.10 升级**：不破坏兼容；plugin 模式用户下次 `/onboard --update` 会自动从 prose-only 镜像策略切换到调用 `mirror-hooks.sh` helper

**v2.10 新增能力一览**：
- **结构性修复**：skill 从仓库根移到 `skills/onboard/`（Claude Code plugin 标准布局），plugin install 现在能正确发现 skill
- **Git executable bits 修复**：hook 脚本 + install.sh + lifecycle 脚本在 git index 中标记为 `100755`（之前是 `100644`，clone 后必须手动 chmod）
- **install.sh 重新设计**：使用 staging cache `~/.claude/.cache/onboard-source/` 保留 git history，install/update 时从 stage 复制 `skills/onboard/*` 到 target
- **Settings templates 同址**：从 repo root 移到 `skills/onboard/`，与 SKILL.md co-located
- **沙箱 round-trip 测试**：通过 `/plugin marketplace add` + `/plugin install` 完整模拟测试（24 pass / 0 fail）

**从 v2.9 升级**：
- 重新跑 `install.sh install`（路径模型变了，stage cache 是新概念）
- 已 onboarded 的项目 `/onboard --update` 触发 Phase 0.5 Migration 调整 settings hook 路径

**v2.9 新增能力一览**：
- `/plugin marketplace add sdsrss/onboard` + `/plugin install onboard` 标准化插件安装
- `.claude-plugin/marketplace.json` + `.claude-plugin/plugin.json`（符合 Claude Code 官方 schema）
- Phase 7 新增 install 来源检测（Plugin / User-skill / Project-skill / Command 四种），自动选对的 hook 路径变量
- Plugin 模式下默认建立 hook 镜像（`~/.claude/onboard-runtime/hooks/`）避免 user settings 引用 ephemeral plugin 缓存路径
- 元规则 23：plugin 路径不可硬编码到 user settings

**从 v2.8 升级**：
- `/onboard --update` 触发 Phase 0.5 Migration 检测当前 install 来源，重写 settings 中的 hook 路径
- 新装 plugin 模式自动建立 hook 镜像

**v2.8 新增能力一览**：
- 通用 `install.sh` 安装器（curl-bash 风格）+ `.claude-plugin/plugin.json` 原生插件清单
- `/onboard --uninstall` 项目级卸载（marker / manifest 驱动，可逆 Iron 级）
- Marker 约定（line-based / markdown / JSON 三种）+ snapshot protocol（Phase 3/4/6/7/8 入口快照）
- Doctor mode D15（卸载可逆性检查）

**v2.7 新增能力一览**：
- 深度项目认知（Phase 1.7）：构建/测试命令、目录依赖方向、代码规范、行为禁令、覆盖率信号 8 维度自动抽取
- 提取式 CLAUDE.md：token 预算 soft 2500 / hard 5000；每行 load-bearing；空节不写
- Install Plan（Phase 2.5）：dev tools / system CLIs / language runtimes / Claude Code plugins 四类清单 batch 授权
- Claude Code plugin 推荐矩阵（15 项硬编码 + open recommendation fallback）

**从 v2.7 升级**：
- `--update` 触发 Phase 0.5 Migration 把旧 PROJECT 写入加上 v2.8 marker；缺 snapshot 的标 `irrecoverable: true`
- 新 onboarding 全程走 marker / snapshot 协议，可一键 `--uninstall`

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
