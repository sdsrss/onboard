---
name: onboard
description: 旧项目接入 Claude Code 的标准化引导流程
argument-hint: "[--local-only|--share] [--dry-run] [--phase=<0-8>] [--resume] [--update] [--strict] [--isolate-branch] [--doctor]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep
---

# /onboard — Legacy Project Onboarding Protocol (v2.6)

参数：`$ARGUMENTS`

> **本包是 Skill 形式发布**（`.claude/skills/onboard/`）。
> 包含预制的 4 个 hook 脚本作为 supporting files：
> - `hooks/guard-bash.sh` — PreToolUse on Bash，拦截危险命令
> - `hooks/guard-edit.sh` — PreToolUse on Edit|Write|MultiEdit，拦截禁区编辑
> - `hooks/post-edit-check.sh` — PostToolUse on Edit|Write|MultiEdit，记录触及文件 + 轻量检查
> - `hooks/stop-verify.sh` — Stop hook，按 mode 跑增量验证
>
> Phase 7 不再动态生成脚本，而是直接在 `.claude/settings.json` 中引用 `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks/<name>.sh`。
>
> 兼容 Command 形式：把 SKILL.md 重命名为 `.claude/commands/onboard.md`，Phase 7 改回动态生成脚本到 `.claude/hooks/`。
>
> **关于 `disable-model-invocation: true`**
> 防止 Claude 自动触发。已知 Skill 形式有兼容性 bug，若异常移除该字段或改用 Command 形式。
>
> **关于 `allowed-tools`**
> 故意限制为只读工具。Bash/Write/Edit 走正文授权流程。**会话开始时若希望连续执行，请在首个权限弹窗选择"允许本会话"**；否则保持逐次确认。两种节奏都安全。

---

## 0. 总则（贯穿全流程）

### 文件四分类

- **PROJECT**：仓库已有内容。默认不得修改；仅当 Phase 2 plan 列入 `touches` 并经授权后可改。
- **RUNTIME**：本命令运行期状态与日志：`.claude/onboarding-state.json`、`.claude/onboarding-logs/`、`.claude/tmp/`。
- **OUTPUT**：本流程新增/维护的 Claude 产物：`CLAUDE.md`、`.claude/settings.json`、`.claude/hooks/*`、`.gitignore` 修订等。
- **LOCAL-SIDE-EFFECT**：不入仓但改变本机环境的写入目标：`.git/hooks/*`、`.git/info/exclude`、专用 onboarding 分支。**不参与 touch_budget**。

工作区"干净"仅针对 PROJECT。

### Iron Laws（19 条，与 v2.3 同；Iron Law 3 / 14 措辞精化）

1. **Read-before-write**：未读取现状不得写入；现状报告未生成不得进入 Phase 1.5/2。
2. **No silent overwrite**：覆盖任何已存在配置文件前必须 diff + 用户确认。
3. **Respect existing stack(s)**：**同一语言栈内**禁止引入冲突工具（如 Node 内同时 ESLint + JSHint）。**允许多语言项目并存多套工具栈**——按栈分别应用。
4. **Idempotent**：可重复执行；已完成阶段须基于状态文件跳过或验证而非重做。
5. **Verifiable**：每个阶段必须有可执行验证步骤，失败不得标记为完成。
6. **Stateful**：所有阶段决策、产出、验证结果写入状态文件。
7. **No auto-install**：任何安装/升级动作必须先列清单 + 显式授权。凡 `installs != []`，对应 lockfile 自动追加到该 item 的 `touches`。
8. **No business logic changes**：onboarding 不得修改业务代码；唯一例外是 Phase 5 中用户批准的最小 smoke test。
9. **No dependency upgrades**：不得升级已有依赖版本；只允许新增经授权的开发依赖。
10. **Prefer existing task runner**：若项目已有 Makefile / justfile / package scripts，不新增平行入口；新增 script 前必须先做任务运行器健康检查。
11. **Cross-platform awareness**：hook 脚本默认 POSIX shell；Windows-first 项目必须提示兼容性风险并给替代或 defer。
12. **CI alignment**：本地 lint/test/typecheck 命令必须优先复用 CI 中已有命令。
13. **Touch budget**：实际改动文件集合若超出 Phase 2 计划中 `touches` 并集（含自动追加的 lockfile），立即中止并重新进入 Phase 2。`local_side_effects` 不计入。
14. **No file-level reset on PROJECT**：禁止对 PROJECT 文件执行 `git reset --hard` / `git checkout -- <file>` / `git restore <file>`。**`git checkout -b <new-branch>`（创建新分支）不在此限**——配合 `--isolate-branch` 模式使用。测试改动一律走 `.claude/tmp/`。
15. **Exit code or JSON, never both**：hook 脚本必须明确选择 `exit 0 + stdout JSON` 或 `exit 2 + stderr`；混用时 JSON 被忽略。
16. **Forbidden zones are global**：Phase 1 探测出的禁区是 **candidates**；只有 Phase 1.5 用户确认的 **confirmed forbidden zones** 才进入全流程消费——CLAUDE.md / lint ignore / hook env / guard-edit 必须保持一致。
17. **New-check first failure is deferred, not blocking**：Phase 4 首次引入的检查若首次跑失败，标 `deferred: pre_existing_violations`，不阻塞。
18. **Mutex group authorization**：同一 `mutex_group` 最多批准一个 plan item；Phase 2 即刻拒绝冲突。
19. **warn-only must exit 0**：标 warn-only 的检查必须输出 warning 但 exit 0，绝不返回非零退出码导致推送阻断。

### 参数解析

- `--local-only`（v2.6 新增，**默认模式**）：local 模式。所有 OUTPUT 文件走 Claude Code 原生 `.local.*` 约定 + `.git/info/exclude`，**完全不入仓**，团队成员 pull 后看不到任何 onboard 痕迹。详见下文「Mode model」章节。
- `--share`（v2.6 新增，opt-in）：team-share 模式（v2.5 及之前的默认行为）。OUTPUT 文件入仓，通过 .gitignore 管控 RUNTIME。需要团队对 AI 工具有共识。
- `--dry-run`：只输出"将要做什么"，不写 OUTPUT 文件。RUNTIME 正常创建/更新。
- `--phase=<n>`：只跑指定阶段（0, 0.5, 1, 1.5, 2, 3-8）。
- `--resume`：从上次中断处继续（同版本状态文件）。
- `--update`（v2.4 新增）：升级已完成的旧版 onboarding 到当前 spec。触发 Phase 0.5 Migration，继承旧决策、只跑差异阶段。
- `--strict`：任何验证失败立即中止整个流程。
- `--isolate-branch`（v2.4 新增）：在专用 git 分支 `chore/onboarding-<timestamp>` 上执行写入阶段。失败/不满意切回原分支即可整体回滚。**仅在 `--share` 模式下有意义**；local-only 模式文件均不入仓，分支隔离无收益（Phase 0 检测到 `--local-only --isolate-branch` 组合会发出 warn，但不阻断）。
- `--doctor`（v2.5 新增）：诊断模式。不跑任何 Phase，不写 PROJECT/OUTPUT，仅做健康检查 + RUNTIME log。详见下文「Doctor Mode」章节。

`--resume`、`--update`、`--doctor` 三者互斥。`--local-only` 与 `--share` 互斥（默认 `--local-only`，显式给 `--share` 才入仓）。

### 阶段卡片输出契约

```
─── Phase <n> · <name> ───
status:   done | skipped | failed | dry-run | blocked | deferred | verification_skipped | migrated
mode:     local-only | share
elapsed:  <耗时，例：1m23s>
actions:  <逐条做了什么>
outputs:  <OUTPUT 文件路径>
local_side_effects: <LOCAL-SIDE-EFFECT 路径>
verify:   <验证命令及结果摘要>
next:     <下一阶段或建议>
```

---

## Mode model（v2.6 核心新增）

### 设计原则

**默认 local-only**：大多数公司不全员支持 AI 工具，少数人试用。默认不入仓 = 不强加 AI 工具给同事 = 零团队污染风险。

**显式 share**：用户明确知道团队接受 AI 工具，主动 `--share` 入仓共享。

### 文件归宿表（v2.6 关键契约）

| 文件 | `--local-only`（默认） | `--share` |
|---|---|---|
| 知识文件 | `CLAUDE.local.md`（Claude Code 原生 per-user 文件，业界约定不入仓） | `CLAUDE.md`（入仓） |
| Claude Code 设置 | `.claude/settings.local.json`（Claude Code 原生 per-user override） | `.claude/settings.json`（入仓） |
| Skill 包 | 复用 `~/.claude/skills/onboard/`（用户全局安装），不写项目内 | `.claude/skills/onboard/`（入仓） |
| Hook 脚本（Command 形式） | `.claude/hooks/`，加入 `.git/info/exclude` | `.claude/hooks/`，入仓 |
| State 文件 | `.claude/local-only/onboarding-state.json` | `.claude/onboarding-state.json` |
| 运行日志 | `.claude/local-only/onboarding-logs/` | `.claude/onboarding-logs/` |
| Forbidden zones 注入到 lint ignore（.eslintignore 等） | **跳过**（不动 PROJECT 文件） | 注入（PROJECT 改动需 AUTH） |
| `.gitignore` 改动 | **不改**（零团队污染） | 修订（按 Case A/B） |
| `.git/info/exclude` 注入 | 注入所有 OUTPUT + RUNTIME 路径 | 仅注入 RUNTIME 路径 |
| `.git/hooks/*` 安装 | 默认 yes（per-clone，本就不入仓） | 按 Phase 6 决策 |

### 模式不变量

- **local-only 永远不修改 PROJECT 文件**——onboard 只在 `.claude/local-only/` 和 `.git/info/exclude` 写入；唯一例外是 `CLAUDE.local.md` 写到项目根（Claude Code 自动 load 它需要这个位置，但 git 默认 ignore `*.local.*`）
- **local-only 不改 .gitignore**——任何修改都可能成为 PR 噪音
- **share 模式必须显式**——用户 `--share` 即视为知情同意 AI 工具入仓
- **混合升级**：local-only 已 onboard 的项目可 `--update --share` 升级为团队共享（state file 标 `mode_migration: local-only→share`，需 hard AUTH）

### Local-only 模式下 Iron Laws 的特别要求

- **Iron Law 8（No business logic changes）**：local-only 模式扩展为"不修改任何 PROJECT 文件，包括 .gitignore"
- **Iron Law 13（Touch budget）**：local-only 模式的 `touch_budget` 限定为 `CLAUDE.local.md` 单文件 + `.git/info/exclude` 追加（LOCAL-SIDE-EFFECT，不计入预算）
- **Iron Law 16（Forbidden zones global）**：local-only 模式下 forbidden zones 仅通过 hook env `ONBOARD_FORBIDDEN_PATHS` 强制，**不同步**到项目的 .eslintignore / .prettierignore 等（避免 PROJECT 文件修改）

---

## Git host adapter（v2.6 新增）

支持多 git 托管平台的统一抽象。Phase 0 探测，Phase 8 调用。

### 支持平台

| Host | 远程 URL 信号 | CLI | PR/MR 命令 | 模板路径 |
|---|---|---|---|---|
| GitHub | `github.com` / `*.github.com` / `*.github.*` (Enterprise) | `gh` | `gh pr create --base <X> --title <Y> --body <Z>` | `.github/PULL_REQUEST_TEMPLATE.md` / `.github/pull_request_template.md` |
| GitLab | `gitlab.com` / `gitlab.*` (self-hosted) | `glab` | `glab mr create --target-branch <X> --title <Y> --description <Z>` | `.gitlab/merge_request_templates/*.md` |
| Gitea / Forgejo | `gitea.*` / `codeberg.org` / `forgejo.*` | `tea` | `tea pulls create --base <X> --title <Y> --description <Z>` | `.gitea/PULL_REQUEST_TEMPLATE.md` |
| Bitbucket | `bitbucket.org` / `bitbucket.*` | none mainstream | fallback URL | none |
| 未识别 | other | none | fallback URL | none |

### Adapter 接口（实现层 contract）

每个 adapter 必须提供：

```
detect()         → bool                            是否检测到此 host
cli_available()  → bool                            对应 CLI 是否安装
template_path()  → string | null                   PR/MR 模板文件路径
create_pr(base, title, body) → command_string      构造 PR/MR 命令
web_url_hint(branch) → string                      未装 CLI 时的"手动开 PR"网址
```

Phase 0 探测得出 `git_host` 字段写入状态文件：

```yaml
git_host:
  platform: github | gitlab | gitea | bitbucket | unknown
  remote_url: <git remote get-url origin 输出>
  cli_command: gh | glab | tea | null
  cli_available: true | false
  template_path: <文件路径或 null>
  enterprise: true | false   # 自托管标志（gitlab.example.com 等）
```

### Fallback 策略

| 情况 | 行为 |
|---|---|
| Host 识别成功 + CLI 可用 | Phase 8 末尾 offer `<cli> pr/mr create ...` |
| Host 识别成功 + CLI 缺失 | Phase 8 末尾给出 web URL 让用户手动开 PR/MR，附自动生成的 title + body 文本 |
| Host 不识别（unknown / 未推送的本地 repo） | Phase 8 静默跳过 PR offer，仅提示"推送后手动开 PR/MR" |
| Multiple remotes | 优先 `origin`，多 remote 时提示用户选 |

### Local-only 模式下的 adapter 行为

local-only 模式 Phase 8 **不 offer 任何 PR/MR**——文件根本没入仓，没有可推送的 commit。但 adapter 仍然探测并记录，用于：
- `--update --share` 模式升级时直接复用 adapter 决策
- Doctor mode D8 检查"如未来切到 share，host 工具链是否就绪"

---

## Phase 0 · Preflight

### 工具可用性策略

| 工具 | 必需级别 | 缺失时行为 |
|---|---|---|
| `git` | 始终 blocking | 整个流程不可进行 |
| `jq` | Phase 7 才 blocking；Phase 0-6 仅 warning | Phase 7 缺失时 blocked，给替代脚本提示 |
| `make` | 仅 `Makefile` 存在时检查 | 缺失给安装建议，不 blocking 至 Phase 4 |

### 动作

1. `git rev-parse --show-toplevel` 等于当前目录。
2. **Git 拓扑检测（v2.6 新增，hard-block 集）**：
   ```bash
   git rev-parse --show-superproject-working-tree   # 非空 → 在 submodule 里
   git rev-parse --is-bare-repository                # true → bare repo
   git symbolic-ref -q HEAD                          # 失败 → detached HEAD
   git rev-parse --is-shallow-repository             # true → shallow clone (warn-only)
   test "$(git rev-parse --git-common-dir)" = "$(git rev-parse --git-dir)" # false → worktree (warn-only)
   ```
   | 拓扑状态 | 行为 |
   |---|---|
   | submodule | **hard-block**：拒绝运行，提示进入 superproject 跑 |
   | bare repo | **hard-block**：bare repo 没 working tree |
   | detached HEAD | **hard-block**：无法安全建分支 |
   | shallow clone | **warn**：committer 统计可能不准，team signal 评分会偏低；可继续 |
   | worktree | **warn**：`.git/info/exclude` 是 per-worktree，跨 worktree 不共享；可继续 |

3. PROJECT 工作区状态：过滤 RUNTIME 路径后 `git status --porcelain` 为空，否则等待 `continue dirty`。
4. 按表检查工具可用性。

5. **Team-signal 评分（v2.6 新增）**：扫描以下 6 个信号，每个 1 分：

   ```yaml
   signals:
     codeowners:        path 存在 (.github/CODEOWNERS 或 CODEOWNERS 或 docs/CODEOWNERS)
     pr_template:       .github/PULL_REQUEST_TEMPLATE* / .github/pull_request_template* / .gitlab/merge_request_templates/*
     committers_3plus:  git shortlog -sn --since="6 months ago" --no-merges 行数 ≥ 3
     ci_branch_protect: .github/workflows/*.yml 含 required_status_checks 字符串 或 .gitlab-ci.yml 含 rules:.*protected_branches
     enterprise_remote: origin URL 含已知企业域名（非 github.com / gitlab.com / bitbucket.org）
     contributing_doc:  CONTRIBUTING.md 或 .github/CONTRIBUTING.md 提到 "review" / "approval"
   ```

   评分阈值：
   - **score ≥ 2 → team**（强烈推荐 `--share + --isolate-branch`；默认仍 `--local-only` 但提示）
   - **score = 0 → solo**（默认 `--local-only` 即可，可考虑 `--share` 直跑 main）
   - **score = 1 → ambiguous**（ASK 用户）

6. **Git host adapter 探测（v2.6 新增）**：见上文「Git host adapter」章节。结果写入 `git_host` 字段。

7. 读取状态文件 → 加载历史。**检测 `version` 字段**：
   - 与当前 spec 版本相同 → 走 `--resume` 流程
   - 不同且用户指定 `--update` → 进入 Phase 0.5 Migration
   - 不同但用户未指定 `--update` → 标 `blocked`，提示用户加 `--update` 或手动删除旧状态文件

8. **模式确认（v2.6 新增）**：
   - 默认 `--local-only`，仅 Phase 0 卡片显示当前模式
   - score = 1 且未显式指定 mode → ASK：
     ```
     检测到 1 个团队信号（CODEOWNERS）。
     推荐:
       [L] --local-only （默认，零团队污染）
       [S] --share --isolate-branch （团队共享 + PR review）
     ```
   - 显式 `--share` 时输出"将修改 PROJECT 文件 + 入仓"警示

9. 创建 RUNTIME 目录（local-only 模式：`.claude/local-only/`；share 模式：`.claude/`）；追加到 `.git/info/exclude`（LOCAL-SIDE-EFFECT）。

10. **若指定 `--isolate-branch`** （仅 `--share` 模式有意义）：
    ```bash
    PREFIX=$(detect_branch_prefix)   # 从 git for-each-ref 推断（chore/infra/feat/...）
    BRANCH="${PREFIX}/onboarding-$(date +%Y%m%d-%H%M%S)"
    git checkout -b "$BRANCH"
    ```
    分支名记入状态文件 `params.isolation_branch`，最终报告告知用户回滚方式 + 自动开 PR/MR offer。

### 分支前缀探测（v2.6 新增）

```bash
detect_branch_prefix() {
  # 统计 origin 远程分支前缀出现次数
  git for-each-ref --format='%(refname:short)' refs/remotes/origin \
    | grep -v '^origin/HEAD' \
    | cut -d'/' -f2 \
    | sort | uniq -c | sort -rn \
    | awk '$1 >= 2 {print $2; exit}'   # 至少出现 2 次的最常见前缀
}
```

零信号 → fallback `chore`。

### 输出预估（v2.4 新增）

Phase 0 卡片新增"预估总耗时"：

| 项目规模 | 预估耗时 |
|---|---|
| small | 5-10 min |
| medium | 15-30 min |
| large | 30-60+ min |

### 验证

- 当前目录 == git 根目录
- Git 拓扑无 hard-block 状态（v2.6）
- PROJECT 工作区干净（或 `continue dirty`）
- 工具按需就位
- Team-signal 评分已记录 + 模式已确认（v2.6）
- Git host adapter 已探测（v2.6）
- 本地 ignore 配置完毕
- 状态文件版本已判定后续路径（resume / update / fresh）

### Phase 0 卡片样例（v2.6）

```
─── Phase 0 · Preflight ───
status:       done
mode:         local-only (default)
elapsed:      3s
git topology: healthy (single-repo, branch=main, clean)
team signals: 1/6  (CODEOWNERS missing, PR template missing, 1 committer in 6mo)
              → classified as SOLO
git host:     github.com (gh CLI v2.x available)
size:         small (estimated 5-10 min)
actions:
  - Created .claude/local-only/onboarding-state.json
  - Appended .git/info/exclude (4 entries)
outputs:      [none — local-only mode writes no PROJECT files]
local_side_effects:
  - .claude/local-only/  (created)
  - .git/info/exclude  (appended)
next:         Phase 1 (Discovery)
```

---

## Phase 0.5 · Migration（仅 `--update` 触发，v2.4 新增）

**目的**：把旧版本状态文件升级到当前 schema，**保留所有可继承的决策**。

### 动作

1. 备份原状态文件：`cp .claude/onboarding-state.json .claude/onboarding-state.v<old>.json.bak`。
2. 按下表执行字段映射 / 补全：

   | 源版本 | 缺失字段 | 处理 |
   |---|---|---|
   | v1 | `stacks[]`、`forbidden_zone_candidates`、`confirmed_forbidden_zones`、`mutex_resolutions`、`local_side_effects` | 重新跑 Phase 1 探测并合并；Forbidden 列表对照旧 CLAUDE.md `## Forbidden` 节 |
   | v1 / v2.0 | `stack.size` | 重新评级 |
   | v1 / v2.0 / v2.1 | `phase_1_5` 整体 | 从历史决策推断；缺失项进 Phase 1.5 重新决策 |
   | v2.2 及更新 | `local_side_effects`、`mutex_resolutions` | 从 `phases.6/7` 推断 |
   | v2.5 及之前 | `mode`、`git_topology`、`team_signals`、`git_host`、`mode_migration`、`git_info_exclude_injected` | v2.5 及之前都是 share 行为 → `mode: "share"`、`mode_migration: null`；其余字段重跑 Phase 0 探测填充 |
   | 任何版本 | `entry_point` | 检测当前发布路径（Skill or Command） |

**v2.5→v2.6 升级特殊处理**：v2.5 项目原本就是 share 行为，升级后 `mode: "share"`；用户若想改回 local-only 必须显式跑 `/onboard --update --local-only`，此时 Phase 0.5 标 `mode_migration: "share→local-only"` + Phase 8 输出"清理 .gitignore 中 onboard 条目 / 取消 git tracking 的 CLAUDE.md / settings.json"步骤（涉及 PROJECT 改动 → hard AUTH）。

3. 写入新状态文件，`version` 升级到当前 spec 版本，`migrated_from: <old>` 记入元数据。
4. **决策继承策略**：
   - 旧 `phase_1_5.decisions` 中仍合法的值（在新 `allowed_values` 中）→ 直接继承
   - 不合法或不存在的值 → 重新进入 Phase 1.5
   - 用户在 Phase 1.5 看到"已继承"与"需重决"两类，分别处理

### 差异 Phase 识别

迁移完成后，标记哪些 Phase 需要重跑：
- 旧版无此 Phase（如 v1 没 Phase 1.5）→ 重跑
- spec 在该 Phase 有 schema 重大变化 → 重跑
- 其余 → 跳过，继承旧产物

### 验证

- 原状态文件已备份且可读
- 新状态文件 `version` 与当前 spec 一致
- 决策继承结果输出给用户审阅
- 差异 Phase 清单写入状态文件 `params.update_phases`

---

## Phase 1 · Discovery（多语言栈一等公民）

**目的**：生成《项目环境现状报告》。

**严格约束**：不修改 PROJECT/OUTPUT，仅允许写入 RUNTIME。

### 探测矩阵（v2.4：按目录归属判断多栈）

按目录划分识别每个**语言栈**（一个项目可有多个）：

| 检测信号（按目录） | 推断 stack |
|---|---|
| `<dir>/package.json` + lockfile | Node 栈，paths=[dir]，包管理器按 lockfile |
| `<dir>/pyproject.toml` / `<dir>/Pipfile` / `<dir>/requirements.txt` | Python 栈 |
| `<dir>/go.mod` / `<dir>/Cargo.toml` / 其余 | 对应栈 |

每个栈独立记录：`{ id, language, paths[], package_manager, frameworks[], size }`。

**根级聚合层**单独识别：`Makefile` / `justfile` / `Taskfile.yml` / `pnpm-workspace.yaml` / `turbo.json`——这些跨栈协调，不归属任何单栈。

### 项目规模评级（按整体）

| 指标 | small | medium | large |
|---|---|---|---|
| 源文件数 | <500 | 500–5000 | >5000 |
| Workspace/package 数 | ≤3 | 4–15 | >15 |
| 单次全量 typecheck 估时 | <10s | 10–60s | >60s |

写入 `stack.overall_size`，作为 Phase 7 Stop hook 默认模式推荐依据。

### CI 命令提取协议（v2.4：按 job 分类映射栈）

提取 CI 命令时**按 job 归类**，每个 job 推断对应的 stack（依据：job 名前缀、`run` 命令首个 token、`working-directory` 字段）：

```yaml
ci_commands_extracted:
  - job: test-web
    stack_id: ts-web
    commands: [pnpm install, pnpm lint, pnpm test]
  - job: test-api
    stack_id: py-api
    commands: [poetry install, poetry run ruff check, poetry run pytest]
  - job: test-ml
    stack_id: py-ml
    commands: [...]
```

后续 Phase 4 对齐按 stack 分别处理。

### 包管理器冲突检测（v2.4：按栈归属先做归类）

检测前先做栈归属：
- `apps/web/package-lock.json` 和 `apps/api/poetry.lock` → 属不同栈 → **不算冲突**
- 同一栈内 `package-lock.json + pnpm-lock.yaml` → 真冲突，记 conflicting

### 禁区探测（Forbidden zone CANDIDATES，Iron Law 16）

按以下信号收集**候选**（须经 Phase 1.5 确认）：
1. `.eslintignore` / `.prettierignore` / 等价 ignore 中的目录条目（排除构建产物）
2. 文件名含 `legacy` / `deprecated` / `vendor` / `third_party` 的目录
3. `CODEOWNERS` 中标注 `@no-modify` 或类似
4. 已有 CLAUDE.md 中 `## Forbidden` 节列出的路径

### 报告结构

```markdown
# 项目环境现状报告

## 1. 技术栈（可多栈）
- stack `ts-web`: TypeScript + Next.js, pnpm, paths=[apps/web]
- stack `py-api`: Python + FastAPI, poetry, paths=[apps/api]
- stack `py-ml`: Python + Jupyter, poetry, paths=[ml]
- 跨栈聚合：pnpm-workspace.yaml / Makefile
- 平台：POSIX / Windows-first / mixed
- 整体规模：small | medium | large

## 2. 已有质量工具（按栈）
- ts-web: ESLint / Prettier / tsc / vitest
- py-api: ruff / -- / mypy / pytest
- py-ml: ruff / -- / -- / --

## 3. 已有提交检查
- pre-commit framework
- .git/hooks/
- commitlint
- CI 命令（按 job 分类映射栈）

## 4. Claude Code 现状
- CLAUDE.md (含/不含 v2.x 章节如 Change Policy / Testing 级别)
- .claude/settings.json（含 hooks 列表与第三方 hook 标识）
- .claude/commands/ / .claude/skills/ / .claude/hooks/

## 5. 目录与约定
- 顶层目录职责、各栈测试目录、配置聚合位置

## 6. 可运行命令实测清单（按栈）
- ts-web: dev / build / test / lint / typecheck / format
- py-api: dev / -- / test / lint / typecheck / format
- 跨栈聚合：make / pnpm -r
- 任务运行器健康状态

## 7. 缺失项 & 风险项
- missing / outdated / conflicting / windows-risk（按栈标注）

## 8. CI ↔ 本地命令一致性（按 stack × job）

## 9. 推荐落地顺序

## 10. Forbidden zone CANDIDATES（待 Phase 1.5 确认）
```

### 验证

- 每个识别栈独立列出
- 第 6 节命令按栈分类
- 第 7 节冲突已做栈归属判断
- 第 10 节明确为 candidates

**进入 Phase 1.5 前停顿让用户阅读。**

---

## Phase 1.5 · Blocking Decisions

### 触发条件

满足任一即进入：lockfile 冲突 / CI 不一致 / 有 forbidden candidates / stale Makefile target / `--update` 模式下有未继承决策。

### Decision item 结构（含严格枚举）

```yaml
- id: <decision-id>
  description: <一句话>
  allowed_values: [enum-value-1, enum-value-2, ...]
  default_suggestion: <按上下文推荐>
  inherited_from_v<old>: <true|false>   # v2.4 新增，--update 模式标注
```

### DSL

```
decide <id> <value>          # value 必须是 allowed_values 之一
add-forbidden <path>          # 补充 confirmed forbidden zone
remove-forbidden <path>       # 从 candidates 移除
list-decisions                # 列出所有待决项及枚举
inherit                       # --update 模式下批准所有继承的决策
proceed-to-plan               # 进入 Phase 2
abort                         # 中止
```

Value 不匹配 `allowed_values` 一律拒绝，不接受同义词、自由文本、其他语言。

### 验证

- 所有阻塞决策项已 `decide` 或显式 `defer`
- Forbidden 已最终化为 `confirmed_forbidden_zones`
- `--update` 模式下继承决策已审阅

---

## Phase 2 · Plan + Authorization

### 动作

1. 读取 `phase_1_5.decisions` → 转化为 plan item。
2. 从 `discovery_report.缺失项` 补充剩余。
3. **自动 lockfile 追加**：凡 `installs != []`，对应 lockfile 加入 `touches`。
4. 自动注入 `forbidden-zones-register` item。
5. **多栈展开**：对每个语言栈分别生成 `lint-<stack>` / `format-<stack>` / `typecheck-<stack>` 等 item，命名空间化。
6. 输出 plan + DSL。

### Plan item schema

```yaml
- id: <短标识>                       # 多栈时含 stack 后缀：lint-ts-web
  phase: <3|4|5|6|7|8>
  stack_id: <对应 stack id 或 null>   # v2.4 新增
  intent: <一句话意图>
  touches: []                         # 仓库工作区文件
  local_side_effects: []              # 不入仓
  installs: []                        # 非空时对应 lockfile 自动加入 touches
  mutex_group: <string | null>
  mode: <light | standard | strict | null>
  reversible:
    can_rollback: yes|no
    method: <如何回滚>
  risk: low | medium | high
```

### 互斥组示例

**`git-hook-strategy`**：`hook-local` vs `hook-husky` vs `hook-lefthook`（多栈项目推荐 lefthook，语言无关）。

**`cc-stop-strategy`**：`cc-stop-light` / `cc-stop-standard` / `cc-stop-strict`，按 `stack.overall_size` 默认推荐。

### 授权 DSL

```
proceed safe             # 只执行 installs == [] && risk == low 的项
proceed all              # 执行全部（mutex 仍会拒绝冲突）
approve install <id>
approve risk <id>
skip <id>
abort
```

`proceed safe` 严格定义：`installs == []` && `risk == low`。

### Mutex / Touch budget 校验

授权完毕后：
- 扫描 mutex group → 多于一个被批准则 Phase 2 失败，要求 `skip` 多余项
- 合并 `touches` 为 `touch_budget`（含自动追加的 lockfile）
- `local_side_effects` 独立记录，不计入 budget

### `--update` 模式

只把 `update_phases` 中标记需要重跑的项加入 plan；其余 item 跳过并标 `inherited-from-v<old>: true`。

---

## Phase 3 · CLAUDE.md（多栈模板支持）

### `claudemd` 插件共存探测（v2.5 新增，前置）

进入决策树前先探测 `claudemd` 插件是否安装（生态里专门管 CLAUDE.md 规范的工具）：

**探测信号**（任一命中即视为已装）：
1. `~/.claude/plugins/claudemd*/` 或项目级 `.claude/plugins/claudemd*/` 目录存在
2. 用户在过去若干会话用过 `/claudemd-*` 命令（询问用户而非自检）
3. `~/.claude/CLAUDE.md` 中含 `claudemd` 字符串（spec 路标）

**分工规则**：

| 节 | claudemd 已装 | claudemd 未装 |
|---|---|---|
| `## Stacks` / `## Stack` | onboard 写 | onboard 写 |
| `## Commands` | onboard 写（按栈） | onboard 写 |
| `## Layout` | onboard 写 | onboard 写 |
| `## Change Policy` | onboard 写 | onboard 写 |
| `## Testing`（含级别行） | onboard 写 | onboard 写 |
| `## Forbidden` | onboard 写 | onboard 写 |
| `## Gotchas` / `## Mistakes log` | onboard 写 | onboard 写 |
| banned-vocab / specificity / 通用规范节 | **claudemd 管，onboard 不动** | onboard 模板默认不含 |

分工写入状态文件 `phases.3.claudemd_coexistence`：

```json
{
  "claudemd_detected": true,
  "detection_signal": "plugin_dir | user_confirmed | spec_marker",
  "onboard_owned_sections": ["## Stacks", "## Commands", ...],
  "claudemd_owned_sections": ["## Specificity", "## Banned vocabulary", ...]
}
```

`--update` 模式继承该分工；后续修订严格按归属编辑。

### 决策树

**`--share` 模式（v2.5 及之前的默认行为）**：
- 已有 `CLAUDE.md` → 修订模式，diff 给用户看后合并，不替换；按 `claudemd_coexistence` 分工只动 onboard 拥有的节
- 无 `CLAUDE.md` → 优先调用 `/init`，否则按模板生成
- 目标文件：项目根 `CLAUDE.md`（入仓）

**`--local-only` 模式（v2.6 默认）**：
- 写入目标改为 `CLAUDE.local.md`（项目根，Claude Code 自动 load，业界约定 git 不入仓）
- 已有 `CLAUDE.md` 且 onboard 跑在 local-only：**不动 `CLAUDE.md`**，把 onboard 新增内容写到 `CLAUDE.local.md`（Claude Code 同时 load 两者）
- 已有 `CLAUDE.local.md` → 修订模式（同 share 模式对 CLAUDE.md 的处理）
- 无任一 → 直接生成 `CLAUDE.local.md`
- `claudemd` 插件共存探测仍生效，但分工记录在 `phases.3.claudemd_coexistence` 仍引用 onboard 拥有的节（节归属与模式无关）
- `CLAUDE.local.md` 自动加入 `.git/info/exclude`，**不动 .gitignore**

### 多栈变体（v2.4 新增）

单栈项目用原模板；多栈项目用以下变体：

```markdown
# Project Knowledge for Claude Code

## Stacks
- **ts-web**: TypeScript + Next.js, pnpm, `apps/web/`
- **py-api**: Python + FastAPI, poetry, `apps/api/`
- **py-ml**: Python + Jupyter, poetry, `ml/`
- 整体规模：medium

## Commands
### 跨栈聚合
- 全量构建：`<聚合命令>`
- 全量测试：`<聚合命令>`

### TS (apps/web/)
- 开发：`pnpm dev`
- Lint：`pnpm lint`
- Typecheck：`pnpm typecheck`
- Format：`pnpm format`

### Python (apps/api/, ml/)
- 开发：`poetry run uvicorn main:app --reload`
- Lint：`poetry run ruff check`
- Typecheck：`poetry run mypy`
- Format：`poetry run ruff format`

## Layout
- `apps/web/` (ts-web)：<职责>
- `apps/api/` (py-api)：<职责>
- `ml/` (py-ml)：<职责>

## Change Policy
- **Safe-to-edit**：apps/web/src/, apps/api/src/
- **Ask-before-edit**：packages/ui/, .github/workflows/, ml/notebooks/
- **Read-only / Forbidden**：packages/legacy-core/, vendor/

## Testing
- 当前测试级别：unit + integration（无 e2e）
- 框架：vitest (ts) / pytest (py)
- 快速验证：`pnpm test --run` + `poetry run pytest -x`
- 全量验证：`pnpm test` + `poetry run pytest`
- 例外：ml/ 暂无测试覆盖

## Gotchas
- <Phase 1 发现的坑、deferred 项现状>

## Forbidden（confirmed by Phase 1.5）
- packages/legacy-core/
- vendor/

## Mistakes log
```

### 验证

- 文件存在且非空
- 占位符残留检测：正则 `^[ \t]*<[a-z+_\-]+>$` 不得匹配任何整行
- 多栈项目必须有 `## Stacks` 节，单栈项目用 `## Stack`
- `## Change Policy` / `## Testing`（含级别行）必须存在
- 若有 confirmed forbidden zones，`## Forbidden` 必须列全
- 多栈项目 Commands 节必须含每个栈的子节

---

## Phase 4 · Dev & Lint Environment（按栈分别应用）

### 任务运行器健康检查（前置必做，Iron Law 10）

```bash
for tgt in $(make -qp 2>/dev/null | awk '/^[a-zA-Z0-9_-]+:/ {print $1}' | sed 's/://' | sort -u); do
  make -n "$tgt" >/dev/null 2>&1 && echo "$tgt: ok" || echo "$tgt: broken"
done
```

stale target 写入状态文件，新增 target 时避开。

### 工具选型矩阵（按栈，已有则保留）

| 栈 | Linter | Formatter | Typecheck |
|---|---|---|---|
| Node + TS | ESLint | Prettier | tsc --noEmit |
| Node + JS | ESLint | Prettier | — |
| Python | ruff | ruff format / black | mypy / pyright |
| Go | golangci-lint | gofmt | go vet |
| Rust | clippy | rustfmt | cargo check |
| Ruby | rubocop | rubocop -A | sorbet / steep |

**多栈项目按栈分别应用**——禁止跨栈混搭（如 Python 项目里加 ESLint）。

### 脚本标准化命名（多栈命名空间化，v2.4 新增）

```
# 单栈项目
lint / lint:fix / format / format:check / typecheck

# 多栈项目
lint:ts / lint:py / lint        # lint 聚合所有栈
typecheck:ts / typecheck:py / typecheck
format:check:ts / format:check:py / format:check
```

聚合命令通过 task runner 实现：

```makefile
lint:
	pnpm run lint:ts
	poetry run ruff check
```

### Forbidden zones 集成

把 `confirmed_forbidden_zones` 写入：
- `.eslintignore`（若 lint 工具是 ESLint）
- `.prettierignore`
- `pyproject.toml` 的 `[tool.ruff.lint]` `exclude` 等

### 验证（Iron Law 17：新增 vs 已有按栈分别处理）

每个栈每个标准命令分两类记录：

```json
{
  "stack_id": "ts-web",
  "command": "pnpm typecheck",
  "category": "new",
  "baseline": null,
  "after": { "exit_code": 1, "summary": "23 errors", "raw_log_path": "..." },
  "status": "deferred: pre_existing_violations"
}
```

raw log 全部落盘 `.claude/onboarding-logs/`。

---

## Phase 5 · Test Environment

### 决策矩阵

| 现状 | 动作 |
|---|---|
| 有测试 + 全部通过 | 在 CLAUDE.md `## Testing` 节补全约定与级别 |
| 有测试 + 部分失败 | 输出诊断，不自动修，标 deferred |
| 无测试 + app/service | 引入最小框架 + 冒烟测试（需授权） |
| 无测试 + library/CLI/SDK/infra/config-only | 默认只在 CLAUDE.md 文档化"无测试入口" |

### 测试级别识别

- 测试目录存在且 ≥1 个 `*.test.*` / `*.spec.*` → 至少 `unit`
- 出现 `request(app)` / `supertest` / `pytest.fixture(client)` → `+ integration`
- 出现 `playwright` / `cypress` / `puppeteer` → `+ e2e`
- 仅 1-2 个 "hello world" 风格测试 → `smoke`
- 完全无 → `none`

多栈项目按栈分别评估，CLAUDE.md `## Testing` 节合并报告。

### 占位 test 命令策略

默认不创建；仅 `approve risk test-placeholder` 时创建，且占位必须 `exit 1` + "No tests configured"。

### 验证

- `test` 脚本能跑且未变红
- CLAUDE.md `## Testing` 含级别行
- deferred / placeholder 在最终报告说明

---

## Phase 6 · Commit & CI Gates

### 框架选型（按现有信号优先；多栈推荐 lefthook）

1. `.husky/` → husky
2. `.pre-commit-config.yaml` → pre-commit
3. `lefthook.yml` → lefthook
4. `package.json` 中有 `simple-git-hooks` → simple-git-hooks
5. 无信号 → Phase 2 互斥组产出多个候选：
   - `hook-local`：本机 `.git/hooks/*`
   - `hook-husky` / `hook-pre-commit-fw` / `hook-lefthook`：入仓
   - **多栈项目默认推荐 `hook-lefthook`**（语言无关，跨栈聚合好）

### 阶段分层

| Stage | 触发 | 允许耗时 | 跑什么 |
|---|---|---|---|
| pre-commit | 提交前 | < 5s | 对 staged 跑 lint:fix + format（按文件扩展名分发到对应栈） |
| commit-msg | 写消息后 | < 1s | Conventional Commits（若有此约定） |
| pre-push | 推送前 | < 30s | typecheck + test（多栈聚合） |

### 自动修复后 re-stage 规则

- lint-staged / pre-commit framework / lefthook：依赖框架自动 re-stage
- 自写裸脚本：**必须显式 `git add`**
- 无法可靠 re-stage：**hook 只能检查不修复**

### warn-only 实现规则（Iron Law 19）

deferred 检查在 pre-push 中以 warn-only 形式存在：

```bash
if ! pnpm typecheck; then
  echo "⚠️  WARN: typecheck has pre-existing violations. Not blocking push." >&2
fi
# 关键：不 exit 非零
```

切换到 fail-on-error（违规清零后）：替换为 `pnpm typecheck || exit 1`。

### CI 配置对齐

按 Phase 1.5 `ci-realign` 决策修改 CI 文件，touches 计入 budget。

### 旁路约定（写入 CLAUDE.md）

```
--no-verify 仅限紧急 hotfix；事后同一天内补救。
```

### 验证（含 fallback）

前置检查：lint-staged / lefthook 配置是否覆盖 `.claude/tmp/` 路径？无法覆盖则标 `verification_skipped: lint_config_excludes_tmp` 并写入人工验证步骤——**不视为 failed**。

如能验证：

```bash
EXT=<按栈选择 .ts / .py / .go>
TMP=.claude/tmp/onboarding-lint-fail.$EXT
echo '<linter 一定能发现的错误>' > "$TMP"
git add "$TMP"

.husky/pre-commit  # 或等价
# 期望非零退出码

git restore --staged "$TMP"
rm "$TMP"
```

CI 修改只验证 yaml 合法性 + 命令字符串变更；实际 CI 跑通需 push 后观察。

---

## Phase 7 · Claude Code Hooks

### 发布路径决策（v2.4 新增）+ 模式决策（v2.6 新增）

Phase 7 行为同时依两个维度决定：

#### 维度 1：skill vs command 形式

| 形式 | hook 脚本来源 | Phase 7 动作 |
|---|---|---|
| **Skill** (`.claude/skills/onboard/` 或 `~/.claude/skills/onboard/`) | supporting files：`hooks/*.sh` | 仅写 settings 文件，引用 hook 路径；**不复制**脚本 |
| **Command** (`.claude/commands/onboard.md`) | 命令运行时动态生成 | 写 `.claude/hooks/*.sh` + 写 settings 文件引用 |

Skill 形式优势：脚本团队 review 一次复用到所有项目；升级 spec 时只升级 skill 包，不必每个项目重跑 Phase 7。

#### 维度 2：local-only vs share 模式（v2.6 新增）

| 模式 | settings 文件 | hook 路径引用 | .gitignore 改动 | .git/info/exclude 改动 |
|---|---|---|---|---|
| `--local-only`（默认） | `.claude/settings.local.json` | Skill：`~/.claude/skills/onboard/hooks/<name>.sh`（用户全局安装路径）<br>Command：`${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh` + 加入 `.git/info/exclude` | **不动** | 注入所有 hook 输出路径 + RUNTIME 路径 |
| `--share` | `.claude/settings.json` | Skill：`${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks/<name>.sh`（项目内 skill 路径）<br>Command：`${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh` | 修订（Case A/B） | 仅注入 RUNTIME 路径 |

**关键细节**：
- local-only + Skill 形式 → hook 引用**全局安装路径**（`~/.claude/skills/onboard/hooks/...`），无项目内 skill 副本，零 PROJECT 改动
- local-only + Command 形式 → hook 脚本写到 `.claude/hooks/*.sh` 但通过 `.git/info/exclude` 隐藏
- local-only 模式 **强烈推荐使用 Skill 形式**（git 状态最干净；Command 形式要求 `.claude/hooks/` 目录可写，且 status 噪音多）
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
    "ONBOARD_TOUCHED_LOG": "${CLAUDE_PROJECT_DIR}/.claude/onboarding-logs/touched-files.txt",
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

`<hook 路径>` 按发布路径决策替换：
- Skill：`${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks`
- Command：`${CLAUDE_PROJECT_DIR}/.claude/hooks`

### 多栈配置文件（v2.4 新增）

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
    "format_check_cmd": "poetry run ruff format --check"
  }
]
```

hook 脚本通过 `ONBOARD_STACKS_FILE` env 读取此 JSON。

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

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$CLAUDE_PROJECT_DIR"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# 记录本轮触及的文件
mkdir -p "$(dirname "$ONBOARD_TOUCHED_LOG")"
echo "$FILE_PATH" >> "$ONBOARD_TOUCHED_LOG"

LOG=".claude/onboarding-logs/post-edit-check.log"

# 多栈分发：按扩展名找对应 stack 的 format_check_cmd
if [ -n "${ONBOARD_STACKS_FILE:-}" ] && [ -f "$ONBOARD_STACKS_FILE" ]; then
  EXT=".${FILE_PATH##*.}"
  CMD=$(jq -r --arg ext "$EXT" '
    .[] | select(.extensions | index($ext)) | .format_check_cmd
  ' "$ONBOARD_STACKS_FILE" | head -1)

  if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
    if ! timeout 10 bash -lc "$CMD" >"$LOG" 2>&1; then
      echo "Post-edit warning: $EXT format check failed. Stop hook will enforce later." >&2
    fi
  fi
fi

exit 0
```

### 示例脚本 4：`stop-verify.sh`（多栈分发 + 模式分支）

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$CLAUDE_PROJECT_DIR"

MODE="${ONBOARD_STOP_MODE:-light}"
STACKS_FILE="${ONBOARD_STACKS_FILE:-}"
TOUCHED_LOG="${ONBOARD_TOUCHED_LOG:-}"

# 防死循环
INPUT=$(cat || echo '{}')
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
[ "$ACTIVE" = "true" ] && exit 0

LOG_DIR=".claude/onboarding-logs"
mkdir -p "$LOG_DIR"
FAILED=()

# 读取栈配置
if [ -z "$STACKS_FILE" ] || [ ! -f "$STACKS_FILE" ]; then
  echo "stop-verify: no stacks config, skipping" >&2
  exit 0
fi

TOUCHED_FILES=""
if [ -n "$TOUCHED_LOG" ] && [ -f "$TOUCHED_LOG" ]; then
  TOUCHED_FILES=$(sort -u "$TOUCHED_LOG" | tr '\n' ' ')
fi

# 没改任何文件且非 strict 模式 → 放行
if [ -z "$TOUCHED_FILES" ] && [ "$MODE" != "strict" ]; then
  exit 0
fi

# 按栈分发
STACK_IDS=$(jq -r '.[].id' "$STACKS_FILE")
for stack_id in $STACK_IDS; do
  EXTS=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .extensions[]' "$STACKS_FILE")
  LINT_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .lint_cmd' "$STACKS_FILE")
  TC_CMD=$(jq -r --arg sid "$stack_id" '.[] | select(.id == $sid) | .typecheck_cmd' "$STACKS_FILE")

  # 筛出本栈的 touched files
  STACK_FILES=""
  for f in $TOUCHED_FILES; do
    for ext in $EXTS; do
      [[ "$f" == *"$ext" ]] && STACK_FILES="$STACK_FILES $f"
    done
  done

  case "$MODE" in
    light)
      [ -z "$STACK_FILES" ] && continue
      if [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD $STACK_FILES" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 || FAILED+=("lint:$stack_id")
      fi
      ;;
    standard)
      if [ -n "$STACK_FILES" ] && [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ]; then
        timeout 30 bash -lc "$LINT_CMD $STACK_FILES" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 || FAILED+=("lint:$stack_id")
      fi
      if [ -n "$TC_CMD" ] && [ "$TC_CMD" != "null" ]; then
        timeout 45 bash -lc "$TC_CMD" >"$LOG_DIR/stop-typecheck-$stack_id.log" 2>&1 || FAILED+=("typecheck:$stack_id")
      fi
      ;;
    strict)
      [ -n "$LINT_CMD" ] && [ "$LINT_CMD" != "null" ] && (timeout 30 bash -lc "$LINT_CMD" >"$LOG_DIR/stop-lint-$stack_id.log" 2>&1 || FAILED+=("lint:$stack_id"))
      [ -n "$TC_CMD" ]   && [ "$TC_CMD" != "null" ]   && (timeout 45 bash -lc "$TC_CMD"   >"$LOG_DIR/stop-typecheck-$stack_id.log" 2>&1 || FAILED+=("typecheck:$stack_id"))
      ;;
  esac
done

# 清理触及清单
: > "$TOUCHED_LOG"

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

## Phase 8 · .gitignore & Final Verification

### 模式分支（v2.6 关键改动）

Phase 8 行为完全依模式分流：

#### `--local-only` 模式（默认）

**不修改 .gitignore**，**不修改任何 PROJECT 文件**。所有隐藏走 `.git/info/exclude`（per-clone，团队不可见）：

```
# .git/info/exclude appended by /onboard v2.6 (local-only mode)
CLAUDE.local.md
.claude/settings.local.json
.claude/local-only/
.claude/hooks/                  # Command 形式时 hook 输出
.claude/onboarding-state.json   # 兼容老版本残留
.claude/onboarding-logs/
.claude/tmp/
```

**写入前**：`grep -F` 检查避免重复；写入后 `git status` 应显示 0 个 untracked 文件（除非用户已有自己的 untracked 文件）——这是 local-only 的核心契约。

#### `--share` 模式（opt-in）

检测 `.claude/` 是否被父规则 ignore，按 Case A/B 修订 `.gitignore`：

```bash
git check-ignore -v .claude/ 2>/dev/null && echo "ignored" || echo "not_ignored"
```

**情况 A**（未被 ignore）：

```gitignore
# Claude Code: personal / runtime files, do not share
.claude/settings.local.json
.claude/onboarding-state.json
.claude/onboarding-state.v*.json.bak
.claude/onboarding-logs/
.claude/tmp/
.claude/local-only/
CLAUDE.local.md
```

**情况 B**（被父规则 ignore）：

```gitignore
# Claude Code: share with team
!.claude/
!.claude/commands/
!.claude/commands/**
!.claude/skills/
!.claude/skills/**
!.claude/hooks/
!.claude/hooks/**
!.claude/settings.json

# Claude Code: personal / runtime, do not share
.claude/settings.local.json
.claude/onboarding-state.json
.claude/onboarding-state.v*.json.bak
.claude/onboarding-logs/
.claude/tmp/
.claude/local-only/
CLAUDE.local.md
```

补全通用必加项（缺失时）：`.env*`、IDE、OS、构建产物、覆盖率。每项写入前 `grep -F` 检查避免重复。

### PR/MR 自动开启（v2.6 新增，仅 `--share --isolate-branch` 模式）

Phase 8 末尾按 `git_host.platform` 调用对应 adapter：

```bash
# GitHub
gh pr create \
  --base "$ORIGINAL_BRANCH" \
  --title "chore: onboard Claude Code dev environment (v2.6)" \
  --body "$(cat .claude/onboarding-logs/pr-body.md)" \
  --draft

# GitLab
glab mr create \
  --target-branch "$ORIGINAL_BRANCH" \
  --title "chore: onboard Claude Code dev environment (v2.6)" \
  --description "$(cat .claude/onboarding-logs/pr-body.md)" \
  --draft

# Gitea
tea pulls create \
  --base "$ORIGINAL_BRANCH" \
  --title "chore: onboard Claude Code dev environment (v2.6)" \
  --description "$(cat .claude/onboarding-logs/pr-body.md)"
```

**Adapter 行为**：
- CLI 可用 → offer 命令字符串 + ASK 用户确认（never auto-execute——开 PR 是 §5 hard AUTH）
- CLI 缺失但 host 已识别 → 输出 web URL：`https://<host>/<owner>/<repo>/compare/<base>...<branch>`
- Host 未识别 → 仅提示 push + 手动开 PR

**PR body 自动生成**：从状态文件提取 mode / mutex_resolutions / stacks / forbidden_zones / installed deps / deferred items 汇总为 markdown，写入 `.claude/onboarding-logs/pr-body.md`，用户可在 push 前手动编辑。

### 入仓共享验证（动态，仅 `--share` 模式）

`--share` 模式：执行 `git ls-files .claude/` 列出当前入仓文件，**动态填入**最终报告。
`--local-only` 模式：执行 `git ls-files .claude/`，**断言输出为空**（除非用户原本就有入仓的 .claude/ 文件，那些不归 onboard 管）；非空则在最终报告里列出 onboard 不会动的现有入仓文件。

### 最终验证清单

通用项（两模式都查）：

```
[ ] CLAUDE.md / CLAUDE.local.md 含 Stack(s) / Commands / Layout / Change Policy / Testing / Forbidden
[ ] 多栈项目按栈分别验证标准化脚本
[ ] Phase 4 类 A 检查前后对比通过（按栈）
[ ] Phase 4 类 B 新增检查首次失败已记入 deferred（按栈）
[ ] pre-commit hook 能拦截 lint 错误（或标 verification_skipped）
[ ] pre-push hook 中 deferred 检查为 warn-only 且 exit 0
[ ] .claude/hooks/*.sh（或 skill supporting）自动验证全通过
[ ] 第三方 hook 共存验证通过（若适用）
[ ] Mutex group 无冲突
[ ] local_side_effects 已独立记录
[ ] `--update` 模式下 migrated_from / 继承决策 / 差异 Phase 已记录
[ ] `--isolate-branch` 模式下分支名已告知用户（仅 share 模式有意义）
[ ] 状态文件字段完整
```

`--local-only` 模式专属（v2.6）：

```
[ ] PROJECT 工作区 0 改动（git diff --quiet HEAD 通过）
[ ] git ls-files .claude/ + CLAUDE.local.md 输出为空 / 与 onboard 运行前一致
[ ] .git/info/exclude 已注入所有 onboard 写入路径
[ ] settings 文件为 .claude/settings.local.json 而非 .claude/settings.json
[ ] 知识文件为 CLAUDE.local.md 而非 CLAUDE.md
[ ] CI 配置未被修改（local-only 模式不动 CI）
[ ] forbidden zone 未注入到项目 lint ignore（仅通过 hook env 强制）
```

`--share` 模式专属：

```
[ ] PROJECT 工作区只有 touch_budget 范围内的改动
[ ] CI 配置已对齐（按 job × stack）
[ ] .gitignore 包含 Claude Code 条目
[ ] git ls-files .claude/ 列表已附最终报告
[ ] PR/MR 命令已 offer（若 --isolate-branch + host CLI 可用）
```

### 最终输出（v2.6 加 mode 节）

```markdown
# Onboarding Complete

## Mode
- **<local-only | share>** （v2.6）
- <local-only 时：本次 onboarding 对团队完全不可见；CLAUDE.local.md + .claude/settings.local.json 仅在本机生效>
- <share 时：OUTPUT 文件已入仓，团队 pull 后即可用>

## What was added (OUTPUT)
- <…>

## What was modified (PROJECT, authorized)
- <local-only 模式下此节应为空；非空 → bug>

## What was applied as local-side-effects (not committed)
- <例：.git/info/exclude（追加 N 行）, .git/hooks/pre-commit>

## What was inherited from v<old> (--update mode)
- <继承自旧版的决策与产物>

## What was skipped (and why)
- <…>

## What was deferred (need human action)
- <按栈分组列出 deferred 项>

## Quick reference
- 开发：<按栈命令>
- 提交前自动跑：lint:fix + format（staged，含 re-stage）
- 推送前自动跑：typecheck (warn-only) + test
- Claude 完工前自动跑：按 ONBOARD_STOP_MODE 模式
- Change Policy：见 <CLAUDE.md | CLAUDE.local.md>

## Forbidden zones (confirmed)
- <…>

## Hook coexistence note
- 已存在第三方 hook：<列出>
- onboard 注入：<列出>
- 合并策略：独立 matcher 块；deny 优先；onboard hook 故障静默

## Team share verification (dynamic)
- `git ls-files .claude/`:
  <local-only 应为空；share 模式列出入仓文件>
- 入口：<.claude/skills/onboard/SKILL.md | ~/.claude/skills/onboard/SKILL.md | .claude/commands/onboard.md>

## Git host integration (v2.6)
- platform: <github | gitlab | gitea | bitbucket | unknown>
- CLI available: <gh | glab | tea | none>
- PR/MR command (offered, not auto-executed):
  ```
  <gh pr create ... | glab mr create ... | manual web URL>
  ```

## Rollback (--isolate-branch mode only, share only)
- 分支名：<prefix>/onboarding-<ts>
- 整体回滚：`git checkout <original-branch> && git branch -D <isolation-branch>`
- 接受变更：`git checkout <original-branch> && git merge <isolation-branch>` 或开 PR/MR

## Local-only cleanup (if user later wants to remove onboard traces)
- `rm CLAUDE.local.md .claude/settings.local.json`
- `rm -rf .claude/local-only/`
- 从 `.git/info/exclude` 删除 onboard 注入的行（开头有 `# /onboard v2.6` 注释）

## Recommended next steps
1. `/hooks` 验证 hook 加载
2. 试编辑 confirmed forbidden zone → 期望 guard-edit 拦截
3. 试写一个 lint 错误 → 期望 Stop hook 按 mode 拦截
4. 修复 deferred 项（另起 PR；清零后改 pre-push 为 fail-on-error）
5. （仅 share）第一次 push 后观察 CI 实际行为
6. Review CLAUDE.md / CLAUDE.local.md，删除不符合实际的条目
7. （local-only → share 升级）日后想团队共享时跑 `/onboard --update --share`
```

---

## Doctor Mode（v2.5 新增，v2.6 扩展）

**触发**：`/onboard --doctor`。**不跑任何 Phase**，不写 PROJECT / OUTPUT，仅做诊断 + 追加 RUNTIME log。

**前置**：当前目录是 git 仓库 + 已存在 onboarding 状态文件（local-only: `.claude/local-only/onboarding-state.json`；share: `.claude/onboarding-state.json`）。两个路径都不存在 → 返回 `not_onboarded` 提示用户跑 `/onboard`。

### 检查项

| ID | 检查 | 失败定义 | 失败级别 | 模式相关 |
|---|---|---|---|---|
| D1 | state file schema 合法 | `version` 字段缺失或非已知值 / 关键字段（stacks/confirmed_forbidden_zones/phases）结构错 | broken | both |
| D2 | `stacks[]` 与当前目录一致 | 探测 Phase 1 信号，与 stacks.json 比对；新增 / 消失的栈 | drifted | both |
| D3 | `confirmed_forbidden_zones` 路径仍存在 | 路径已被删 / 重命名 | drifted | both |
| D4 | settings 文件仍引用四个 onboard hook | 引用缺失 / 路径不指向实际脚本 | broken | both |
| D5 | `bash -n` 通过 4 个 hook 脚本 | 语法错误 | broken | both |
| D6 | `jq empty < <settings>` 通过 | JSON 非法 | broken | both |
| D7 | 4 个 hook 脚本可执行（mode 含 `x`） | 缺执行位 | drifted | both |
| **D8** | **模式一致性（v2.6 新增）**：state file `mode` 字段与实际文件分布吻合 | local-only 模式但发现 `CLAUDE.md` 或 `.claude/settings.json` 被 onboard 写入 / share 模式但缺 `.claude/settings.json` | drifted | both |
| **D9** | **`.git/info/exclude` 完整性（v2.6 新增，local-only）**：onboard 写入的所有路径都已在 exclude 中 | 缺路径 → 团队可能误见 onboard 文件 | broken | local-only |
| **D10** | **Git host adapter 就绪度（v2.6 新增）**：检测 host CLI 是否仍可用 | gh/glab/tea 之前可用，现在不可用 | drifted | both |

### 三态健康度

- **healthy**：D1–D10 全过
- **drifted**：仅 drifted 级失败（D2/D3/D7/D8/D10）→ 建议 `/onboard --update` 或针对性手动修复
- **broken**：任一 broken 级失败（D1/D4/D5/D6/D9）→ 必须人工介入或重新 onboard

### 输出格式

```
─── Doctor Report ───
state:        healthy | drifted | broken
mode:         local-only | share
checked_at:   <ISO timestamp>
spec_version: <state.version> (current: 2.6)
git host:     github.com (gh CLI v2.x available)

D1 schema:                ✓ ok
D2 stacks consistency:    ✗ drifted — new dir `ml/` looks like a Python stack not in stacks.json
D3 forbidden zones exist: ✓ ok
D4 hook references:       ✓ ok
D5 hook syntax:           ✓ ok
D6 settings.json valid:   ✓ ok
D7 hook executable:       ✗ drifted — guard-edit.sh missing +x
D8 mode consistency:      ✓ ok
D9 git/info/exclude (local-only): ✓ ok (7 entries match)
D10 host adapter:         ✓ ok (gh)

Suggested actions:
  D2 → run `/onboard --update` to re-detect stacks
  D7 → chmod +x ~/.claude/skills/onboard/hooks/guard-edit.sh
```

### Iron Law 边界

- **不修改 PROJECT / OUTPUT**：doctor 只读不写
- **可以追加到 RUNTIME**：`.claude/onboarding-logs/doctor-<ts>.log` 记录本次诊断
- **遵守 Iron Law 14**：D7 不自动 `chmod +x`，列出建议命令交给用户

### 状态文件不变

Doctor 模式不修改 `.claude/onboarding-state.json`。如需基于诊断结果更新状态，必须用户显式跑 `--update`。

---

## 异常处理

### 中途中止 / 失败

- `abort` / Ctrl-C：保存当前阶段为 `interrupted`，下次 `--resume`
- 验证失败：标 `failed`，输出诊断，不进入下一阶段
- 验证配置不可达：标 `verification_skipped`，写入人工验证步骤，**不阻塞**
- Touch budget 越界：标 `failed: budget_exceeded`，重新进入 Phase 2
- Mutex 冲突：Phase 2 立即拒绝
- 工具缺失：标 `blocked`
- 版本迁移失败：标 `migration_failed`，保留备份文件，提示手动处理

### 整体回滚（`--isolate-branch` 模式）

不满意 → `git checkout <original> && git branch -D <isolation>`，**不需要**走 `git reset --hard` 或 file-level checkout（这些被 Iron Law 14 禁止）。

### 冲突解决原则

- 既有配置与默认值冲突 → 保留既有 + 记录冲突 + 用户决策
- lockfile 冲突 → Phase 1.5 必决
- Mutex 同时被批准 → Phase 2 拒绝
- 第三方 hook 与 onboard hook → 独立 matcher 块共存

### 不可恢复操作（永不执行）

- `git reset --hard`
- 对 PROJECT 文件的 `git checkout -- <file>` / `git restore <file>`
- 任何项目内 `rm -rf`
- 强制覆盖未读取过的文件
- 用户 PROJECT 工作区有未提交改动时执行 git 写操作（除非 `continue dirty`）

---

## 状态文件结构（v2.6 schema）

**路径**：
- `--local-only` 模式（默认）：`.claude/local-only/onboarding-state.json`
- `--share` 模式：`.claude/onboarding-state.json`

```json
{
  "version": "2.6",
  "migrated_from": "1 | 2.0 | 2.1 | 2.2 | 2.3 | 2.4 | 2.5 | null",
  "mode": "local-only | share",
  "mode_migration": "local-only→share | share→local-only | null",
  "started_at": "...",
  "last_updated": "...",
  "params": {
    "dry_run": false,
    "strict": false,
    "update": false,
    "local_only": true,
    "share": false,
    "isolation_branch": "<prefix>/onboarding-... | null",
    "update_phases": []
  },
  "git_topology": {
    "is_submodule": false,
    "is_bare": false,
    "is_detached": false,
    "is_shallow": false,
    "is_worktree": false,
    "branch_prefix_detected": "chore | infra | feat | ..."
  },
  "team_signals": {
    "score": 0,
    "classification": "solo | team | ambiguous",
    "signals_hit": ["codeowners", "pr_template", ...],
    "shortlog_committers_6mo": 1
  },
  "git_host": {
    "platform": "github | gitlab | gitea | bitbucket | unknown",
    "remote_url": "...",
    "cli_command": "gh | glab | tea | null",
    "cli_available": true,
    "template_path": "...",
    "enterprise": false
  },
  "stacks": [
    {
      "id": "ts-web",
      "language": "TypeScript",
      "paths": ["apps/web"],
      "package_manager": "pnpm",
      "frameworks": ["Next.js"],
      "size": "medium"
    }
  ],
  "stack_overall_size": "small | medium | large",
  "tool_availability": { "git": "ok", "jq": "ok", "make": "n/a" },
  "forbidden_zone_candidates": [],
  "confirmed_forbidden_zones": [],
  "touch_budget": [],
  "local_side_effects": [],
  "git_info_exclude_injected": [],
  "phases": {
    "0":   { "status": "done", "elapsed": "...", "mode_confirmed_by": "default | flag | ask" },
    "0_5": { "status": "done | not_triggered", "schema_diff": [], "inherited_decisions": [] },
    "1":   { "status": "done", "discovery_report": "<markdown>", "lockfile_conflicts": [], "ci_commands_extracted": [], "stale_task_runner_targets": [] },
    "1_5": { "status": "done", "decisions": {} },
    "2":   { "status": "done", "plan": [], "approved_items": [], "approved_installs": [], "approved_risks": [], "skipped": [], "mutex_resolutions": {} },
    "3":   { "status": "done", "outputs": ["CLAUDE.md | CLAUDE.local.md"], "change_policy_set": true, "testing_level": "unit + integration", "stacks_section_format": "single | multi", "claudemd_coexistence": {} },
    "4":   { "status": "done", "outputs": [], "installed": [], "task_runner_health": {}, "checks_by_stack": {} },
    "5":   { "status": "skipped | done | deferred | placeholder", "testing_level_recorded": "unit" },
    "6":   { "status": "done | verification_skipped", "choice": "...", "auto_fix_restage_strategy": "...", "ci_realigned": true, "warn_only_checks": [], "outputs": [] },
    "7":   {
      "status": "done",
      "publish_path": "skill | command",
      "settings_file": ".claude/settings.json | .claude/settings.local.json",
      "stop_mode": "light | standard | strict",
      "settings_merged": true,
      "hook_merge_conflicts": [],
      "scripts_created_or_referenced": [],
      "forbidden_paths_injected": [],
      "stacks_config_written": true,
      "auto_verification": {}
    },
    "8":   { "status": "done", "gitignore_strategy": "A | B | none(local-only)", "team_share_files": [], "entry_point": "...", "final_checklist": {}, "pr_command_offered": null }
  }
}
```

---

## 元规则（给执行此命令的 Claude 实例，v2.6 增 4 条）

> v2.3 元规则 9-14 与 Iron Laws 16-19 重复，v2.4 已删除冗余。元规则只保留执行操作层面、Iron Laws 不直接涵盖的指引。

1. 读完本命令后**先输出执行计划**：阶段清单、**当前模式（local-only / share）**、参数解析、改动文件数量上限、规模评级初判、预估总耗时。等用户确认才进 Phase 0。
2. 每个阶段结束严格输出"阶段卡片"，含 `mode`、`elapsed` 和 `local_side_effects` 字段（即使为空）。
3. 若 Phase 1 报告显示项目已经过完整 onboarding 且无 `--update` 参数，提示用户加 `--update` 或显式 `--resume`；不自行决定走法。
4. 任何脚本写入前用 `bash -n` 跑一遍语法。
5. 所有 `${CLAUDE_PROJECT_DIR}` 路径使用 exec form 或正确 quoting，避免空格路径问题。
6. 跨平台风险一旦在 Phase 1 检测到，必须在 Phase 6/7 主动给替代或显式 defer。
7. 任何写入动作前用 touch_budget 比对；越界立即停下。`local_side_effects` 与 touch_budget 不混。
8. **Phase 1.5 DSL 严格枚举**：value 不在 allowed_values 列表中一律拒绝，不接受同义词或自由文本。
9. **Stop hook 模式按 stack_overall_size 推荐**：medium/large 默认 light，small 默认 standard，strict 仅在显式批准时启用。
10. **多栈项目按栈分别处理**：Phase 1/3/4/5/6/7 任何按栈生效的步骤都要遍历 `stacks[]`，命令命名空间化，hook 配置文件驱动。
11. **`--update` 模式下不重做继承的 Phase**：只跑 `update_phases` 中标记的差异项；继承项写入最终报告以便审计。
12. **Skill 形式 Phase 7 不复制 hook 脚本**：直接在 settings.json 中引用 `.claude/skills/onboard/hooks/<name>.sh` 路径。
13. **（v2.6）默认 local-only**：未显式 `--share` 时一律走 local-only。Phase 0 前必须打印"将使用 local-only 模式（默认）"让用户知情。`--share` 触发 hard AUTH（"将修改 PROJECT 文件并入仓，团队成员 pull 后会看到 onboarding 产物"）。
14. **（v2.6）Git 拓扑 hard-block**：submodule / bare / detached HEAD 三种状态绝不开工，Phase 0 立即 abort 并提示具体修复路径。
15. **（v2.6）模式不可单方面切换**：检测到 state file `mode` 字段与当前命令模式不一致 → hard AUTH 要求显式 `--update` 才能切换；切换记 `mode_migration` 字段。
16. **（v2.6）Host adapter 决不自动开 PR/MR**：探测出 CLI 可用最多 *offer* 命令字符串 + 自动生成 body，**永远** ASK 用户确认后才执行——开 PR 涉及外部系统状态变更，属 §5 hard AUTH。
```
