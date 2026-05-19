# Changelog

按 [Keep a Changelog](https://keepachangelog.com/) 风格记录。整个 v2 系列经过 4 轮 simulation-based stress testing 演进，每轮都基于真实压测 evidence 而非理论设计。

---

## v3.0.1 — user-simulation dogfood follow-up (current)

User-simulation dogfood (2026-05-19，临时沙箱模拟 4 类真实安装路径) 发现两处缺陷，已修。Total 测试断言 214 → **218 assertions** / 10 tests / 0 fail。Patch bump 因 (a) 都是 bug 修复（installer untracked 泄漏 + README 一字不差跑不通），无新功能，(b) `install.sh` 行为面"reset --hard 后清 untracked"是兼容修复（先前的"泄漏"不是公开契约），(c) v3.0.0 `(current)` 标签移除。

### Fixed

- **`install.sh` update path 不清 stage untracked 文件**（Low；installer logic）。`git reset --hard` 默认忽略 untracked，stage `skills/onboard/` 子目录内任何用户/外因落下的 stray 文件都会通过 `deploy_skill_from_stage` 的 `cp -a` 泄漏进 INSTALL_DIR 并跨次 update 持续残留。修法：reset 之后追加 `git clean -fdx`（STAGE_DIR 已是 throwaway 安装缓存，Iron Law 14 stage-cache 豁免照旧）。Repro：`bash install.sh install`，向 `~/.claude/.cache/onboard-source/skills/onboard/STRAY.txt` 写文件，再 `bash install.sh update` — 修前 STRAY.txt 出现在 `~/.claude/skills/onboard/`，修后无泄漏。
- **README Option C / 路径 C `git clone` 指令完全装不上**（Medium；docs）。仓库布局 v2.10 起把 skill 移到 `skills/onboard/`（Claude Code plugin 标准），但 README Option C 的 `git clone ... ~/.claude/skills/onboard` 会把 SKILL.md 嵌在 `~/.claude/skills/onboard/skills/onboard/SKILL.md` 二层目录里——Claude Code 找不到 skill，下一行 `chmod +x ~/.claude/skills/onboard/hooks/*.sh` 直接报 No such file or directory。修法：改成 clone 到 `/tmp/onboard-src` + `cp -r /tmp/onboard-src/skills/onboard ~/.claude/skills/` 两步式。`README.md` + `README.zh-CN.md` 同款修。Repro：见 `tasks/2026-05-19-user-simulation-dogfood.md` 沙箱日志。

### Added

- **`install-roundtrip.sh` STEP 4b**: +4 个断言（stray 文件 plant / update exit 0 / no leak in INSTALL_DIR / stage cleaned by git clean）。锁住 stray-file-leak 回归口。`install-roundtrip.sh` 34 → 38 assertions。总测试 214 → **218 assertions** / 10 tests / 0 fail。

### Not changed (intentional)

- **未 bump version**。dogfood 周期内的 documentation+installer 修复，按当前 release 节奏更适合并入下一个 patch（v3.0.1）。`plugin.json` / `marketplace.json` 版本号未动；SKILL.md header 仍 `(v3.0.0)`。
- **未改 SKILL.md 本体**。两 bug 均不在 spec 层面，install.sh 是 installer infra、README 是文档。

---

## v3.0.0 — C1 SKILL.md 浅拆

v3 系列首版。SKILL.md 浅拆改造：3 段最重独立块抽到 sub-file，元规则 27 落地。Major bump 因 (a) **LLM-visible metadata protocol shift**（SKILL.md 不再是 entry-only-load，consumer Claude 进入对应 phase 前需要 Read sub-file），(b) sub-file 加载契约本身是新 spec 条款（元规则 27），(c) prior-AUTH override 自 memory `project_v2_11_candidates.md` 2026-05-15 "不做"判断（重启闸门 1/2 仍保留作为深拆评估触发条件，3/4 作废）。**Sub-file scope 仅限**: Phase 7 / Uninstall Mode / 状态文件结构；其余 phase / 总则 / Iron Laws / 元规则 / Marker conventions 保留在 SKILL.md。Migration note: consumer 端无显式动作要求——SKILL.md sentinel summary 中的 "Read `sub-file.md`" 指令 + 元规则 27 cross-ref 即可触发 lazy-load。Promoted from `v3.0.0-rc.1` (commit `9d940eb`) after 3/3 subagent dogfood verified lazy-load 契约。

### Ship evidence (post-rc.1 dogfood, 2026-05-18)

3 个独立 general-purpose subagent (Opus 4.7) 模拟 consumer Claude，分别 entry 三种场景；每个 agent 收到 SKILL.md 路径 + dry-run 约束 + "list every Read call" 要求。结果 3/3 全部触发 sub-file Read：

| Scenario | Sub-file Read? | 元规则 27 cited? | Decisions cite sub-file? |
|---|---|---|---|
| Phase 7 entry | ✓ `phases/phase-7.md` (full 469 行) | ✓ "mandated by meta-rule 27 before any actionable decision" | ✓ phase-7.md:18-23 / 88-132 / 25-31 / 92-99 |
| `--uninstall=skill` | ✓ `phases/uninstall.md` (full 218 行) | ✓ "SKILL.md:1646 + meta-rule 27 require this Read" | ✓ uninstall.md:19-23 / 41-82 / 83-97 / 71-82 |
| State file write | ✓ `references/state-schema.md` (full 137 行) | ✓ "sentinel summary explicitly forbids inferring schema from it (元规则 27)" | ✓ state-schema.md:17-132 具体行号 |

Caveats（诚实记录）：3 个 subagent 都是 Opus 4.7 同模型族，未覆盖 Haiku/Sonnet 行为；prompt 明确"list every Read call"可能引导 agent 偏严谨；模拟的是 SKILL.md 已 Read 入 context 的情况（非真 Skill tool 自动加载）。Cross-model + 真 plugin install dogfood 仍需用户实测，但当前 evidence 足够 ship。

### Added

- **`skills/onboard/phases/phase-7.md`** (459 行 + 7 行 frontmatter prose = 468 行)：Phase 7 完整 spec 从 SKILL.md:1327-1785 迁出。canonical：settings.json 形式 × 模式 × 安装来源 三维决策表 / 4 hook 完整 settings 模板 / canonical 嵌入示例脚本 (guard-bash / guard-edit / post-edit-check / stop-verify) / mirror-hooks.sh 集成点 / Iron Law 12/15/16/19/23 在 hook 层面的具体绑定。
- **`skills/onboard/phases/uninstall.md`** (209 行 + 8 行 frontmatter = 217 行)：Uninstall Mode 完整 spec 从 SKILL.md:2090-2298 迁出。canonical：三层状态模型 (L1/L2/L3) / `=skill` vs `=all` 双模式流程 / keeper-rewrite atomic protocol (jq tmp + mv) / 默认值约定 / 非交互调用样例 (`ONBOARD_CONFIRM_UNINSTALL=yes ONBOARD_UNINSTALL_MODE=skill ...`) / Iron Law 20/21/22 + 元规则 26 在 uninstall 层面的具体绑定。
- **`skills/onboard/references/state-schema.md`** (128 行 + 8 行 frontmatter = 136 行)：状态文件结构 schema 从 SKILL.md:2332-2459 迁出。canonical：完整字段定义 / 模式分支路径 / phase status 11 枚举 / params XOR 约束 / `scripts/validate-state.sh` 引用点。
- **元规则 27 (v3.0 sub-file 拆分契约)**：SKILL.md 元规则段加第 27 条。强制 sentinel summary 与 sub-file 顶部「保留要点」语义同步；改 3 段任意一处需 audit 另一处；consumer Claude 必 Read sub-file 才能拿 actionable 细节（不准凭 sentinel summary 推断）。`## 元规则` header bump `v2.11 共 26 条` → `v3.0 共 27 条`。
- **`skillmd-links.sh` STEP 8**: +12 个断言（3 个 sub-file 存在 / 3 个 frontmatter prose / 3 个 SKILL.md sentinel link / 3 个 sentinel header 命中次数）。`skillmd-links.sh` 9 → 21 assertions。总测试 202 → **214 assertions** / 10 tests / 0 fail。

### Changed

- **`SKILL.md` 2490 → 1731 行（−30.5%）**：3 段抽出后原位置改为 sentinel header + 4-8 bullet summary + `Read sub-file.md` 指令。Sentinel 段长度共 ~45 行（替代抽出的 796 行）。`## Phase 7` / `## Uninstall Mode` / `## 状态文件结构` 三个 header 名字不变 → 外部 prose 引用（CLAUDE.md 5 处、README 6 处、scripts 4 处、tests 多处）零修改。Iron Law 12/16/20/21/22/23 + 元规则 24/25/26 跨段 anchor（按名字非行号）零修改。
- **`CLAUDE.md` "Don't add a hook" 规则更新**：line 118 改 hook 时需更新的列表从 `(a) SKILL.md Phase 7` 改为 `(a) skills/onboard/phases/phase-7.md (canonical Phase 7 spec, v3.0+) AND SKILL.md ## Phase 7 sentinel summary bullets (元规则 27 同步契约)`。
- **`CLAUDE.md` inventory line** (line 9)：SKILL.md 描述加 v3.0 sub-file 拆分说明。
- **`uninstall-modes.sh`** (21 assertions, 数不变)：新加 `UNINSTALL="$SOURCE_REPO/skills/onboard/phases/uninstall.md"` 变量；9 个 assertion 从 grep `$SKILL` 改为 grep `$UNINSTALL`（三层模型 / 模式 1/2 流程 / 默认值约定 / jq atomic / 元规则 21 snapshot / ONBOARD_CONFIRM）；1 个改为 grep `$SKILL $UNINSTALL`（onboard-keeper/hooks/，两文件均可命中）；元规则 header 断言 `v2.11 共 26 条` 改 `v3.0 共 27 条`。

### Not changed (intentional)

- **4 个 hook 脚本本体** (`skills/onboard/hooks/*.sh`)：零行修改。Phase 7 canonical 嵌入示例脚本与 `hooks/*.sh` 的同步契约规则照旧（per CLAUDE.md「示例脚本」failure mode）——只是 canonical 位置从 SKILL.md 段内移到 phase-7.md 段内。
- **`install.sh`**：staging cache `cp -a "$STAGE_DIR/skills/onboard/." "$INSTALL_DIR/"` 已经递归处理子目录（`phases/` / `references/`），无需改动。
- **`scripts/validate-state.sh`**：v2.12.0 标注 `per SKILL.md state schema v2.9` 注释指向的 schema 内容仍精确（迁到 sub-file 但 schema 字段定义不变）；不更新注释（rationale: 注释引用 schema 版本而非文件路径）。
- **`scripts/release-preflight.sh` PIN_RULES**：7 条不变。sub-file 不嵌入 version pin（跟随 SKILL.md 一起 ship）。

### Migration

- Consumer Claude (运行 `/onboard` 的 LLM 实例)：进入 Phase 7 / Uninstall Mode / 状态文件结构 任一段前，遵循 SKILL.md sentinel 中的 `Read .../<sub-file>.md` 指令拉完整 spec。如跳过 Read 仅凭 sentinel summary 做决策 = 元规则 27 违规。
- 现有 onboarded 项目：无 PROJECT 变化。`/onboard --update` 在 plugin 安装模式下会重新跑 `mirror-hooks.sh` 把 `phases/` 和 `references/` 子目录也镜像到稳定路径（mirror 包含 `skills/onboard/*` 全部）。
- 维护者：改 hook 需同步更新 `phases/phase-7.md` 的 canonical spec + SKILL.md `## Phase 7` sentinel summary（CLAUDE.md "Don't add a hook" 规则已 record 此契约）。改 Uninstall 行为需同步 `phases/uninstall.md` + SKILL.md sentinel；改 state schema 需同步 `references/state-schema.md` + SKILL.md sentinel + `scripts/validate-state.sh` 校验逻辑。

### Deferred to later

- C1 中拆 / 深拆（每 Phase 一个 sub-file / 总则 / Mode model / Iron Laws / 元规则 抽出）：闸门 1（consumer /onboard Phase 4+ "忘 Iron Law" 类错误）+ 闸门 2（单次 /onboard 跑 >60k tokens）任一触发再评估。memory `project_v2_11_candidates.md` 仍保留这两个闸门 active。
- H4 (state migration fixtures v1-v8) / H5 (third-party hook coexistence fixture) / C3 (LLM-based integration test via `claude --print`)
- Phase 4.5 build validation / M2 (LSP / editor config awareness in Phase 2.5)

---

## v2.12.0 — audit follow-up Batch B + C2

Post-architecture-audit Batch B + C2：3 个 additive 特性 + 1 个 critical 缺口补齐。**Minor bump** 因 (a) 引入新 env (`ONBOARD_FORBIDDEN_COMMANDS`) 和新 stacks.json 字段（additive Δ-contract），(b) 新增 user-callable script (`scripts/validate-state.sh`)，(c) 新增 1 个集成测试套件。**纯 additive**，无 schema 破坏，无现有行为变化。

### Added

- **H2 · `ONBOARD_FORBIDDEN_COMMANDS` env**（`guard-bash.sh`）：补齐 Iron Law 16 对称性缺口。audit 发现 forbidden zones 有 global 机制（`ONBOARD_FORBIDDEN_PATHS` → `guard-edit.sh`），但**forbidden commands 没有**——项目无法说"本仓库禁止 `flyctl deploy --strategy=immediate`" 或 "禁止 `psql ... -c DROP`"。`guard-bash.sh` 现读 `ONBOARD_FORBIDDEN_COMMANDS`（newline-separated `grep -qE` ERE 正则；空 = 关）作 project-level deny。换行分隔（**不**用 `:`）是 deliberate design choice——`:` 跟 POSIX 字符类 `[[:space:]]` / `[[:alpha:]]` 冲突；newline 让用户写 `kubectl[[:space:]]+delete[[:space:]]+namespace` 原样可用。Built-in 7 条 dangerous patterns 仍然 unconditional 优先生效。Deny reason 显式标 `Blocked by ONBOARD_FORBIDDEN_COMMANDS pattern: <pat>` 便于诊断。2 个 settings template 加新 env + `_comment_ONBOARD_FORBIDDEN_COMMANDS` 内联说明。`hook-behavior.sh` 加 11 个断言（empty / single-pattern / multi-pattern / POSIX 字符类 / 空 slot / built-in 共存 / reason 字符串）
- **H3 · per-stack timeout 字段**（`stacks.json` + `stop-verify.sh` + `post-edit-check.sh`）：audit 发现历史硬编码的 30/45/30/10s timeouts 在 medium/large monorepo 上几乎必然触发 Stop block（`mypy` / `tsc --noEmit` cold start 60-120s 是常态）。新加 4 个可选字段：`lint_timeout_sec` (default 30) / `typecheck_timeout_sec` (default 45) / `format_timeout_sec` (default 30) / `format_check_timeout_sec` (default 10)。缺省保持历史行为；大项目按栈调高即可摆脱"良性 block"。SKILL.md Phase 7 stacks.json schema 更新 + timeout 表格说明。`hook-behavior.sh` 加 4 个断言（default OK / lint timeout / typecheck timeout / post-edit-check format timeout）
- **C2 · `scripts/validate-state.sh` + `tests/integration/state-schema.sh`**：audit Critical 缺口——SKILL.md:2317-2440 描述了完整 state file schema 但**没任何代码**校验它。Consumer Claude 可以标 `phases.3.status: "done"` 而不写任何 managed file，doctor D1 才会发现。补上脚本化校验器：required top-level fields / `mode` enum / `params.local_only` XOR `params.share` / `mode`↔params 一致性 / phase status 枚举 / stacks 数组 / version 格式 / auto-find 项目根 state file。**Exit codes**：0 valid / 1 violations / 2 invocation error。**未**接入 doctor mode D1（下一版本工作），仅作 standalone tool。`state-schema.sh` 新测试套件 21 个断言覆盖 valid / missing-version / bad-mode / params-both-true / params-both-false / mode-mismatch / bad-phase-status / stacks-not-array / invalid-JSON / auto-find / no-arg-no-file / bad-version-format

### Changed

- SKILL.md Phase 7 settings.json template 加 `ONBOARD_FORBIDDEN_COMMANDS` env 行 + 5 段散文说明（separator design choice / Iron Law 16 对称性）
- SKILL.md "多栈配置文件" header 标 `v2.12.0 加 per-stack timeout`；stacks.json 示例加 `typecheck_timeout_sec: 120` 演示用法；新增 4 字段表格说明
- 元规则 / Iron Law 数量**未变**——本次是 additive 实现，不引入新 spec 约束

### Tests

- 10 个 integration tests / **202 assertions** / 0 fail（+36：H2 11 + H3 4 + C2 21）
- `bash scripts/verify-counts.sh`：全对齐
- `bash scripts/release-preflight.sh`：本 release 自我验证 PASS

### Known limits

- C2 的 validator 是 standalone，**未**接入 doctor mode D1——D1 仍按 SKILL.md 原描述跑 grep。把 `validate-state.sh` 接入 D1 是下个 minor 候选
- C2 没改 SKILL.md state file schema 本身——只校验它。schema 重大升级（如把 `mode` 拆 sub-object）仍是 v3.x 议题
- H2 默认值是空字符串。Phase 7 实际写入 settings 时该字段保留为空——consumer Claude 在 Phase 1.7 A6 行为禁令推断阶段可以**建议**填充常见模式（如 `psql.*DROP TABLE`），但绝不预填——避免误拦 onboarder 自己想跑的合法命令

### 升级路径

- 纯 additive，无 schema / 现有行为变化
- v2.11.3 → v2.12.0：`bash install.sh update`；已 onboarded 项目无需重跑
- 想用 H2 / H3 新字段 → 编辑 `.claude/settings.local.json` 加 env 或 `stacks.json` 加 timeout 字段；onboard 不会自动注入

---

## v2.11.3 — audit follow-up patch

Post-audit Batch A：5 条低风险修正，2 个测试套件扩容。无 Iron Law / 元规则变化，无 schema 破坏，纯 polish + 修正一处明确的 false-positive。

### Fixed

- **H1 · `guard-bash.sh` `.env` 模式 false-positive**：`'> *\.env'` 子串匹配会拦合法的 `> .env.local` / `> .env.example` / `> .envrc` / `> .env_backup` 等变体文件。改成 `'>[[:space:]]*\.env([^.a-zA-Z0-9_-]|$)'`，在 `.env` token 边界处锚定——仍 deny `> .env` / `>.env` / `>> .env 2>&1` / `> .env && deploy`，但放行所有 `.env.<suffix>` / `.env_<suffix>` / `.env-<suffix>` / `.envrc` 形态。`hook-behavior.sh` 加 12 个正反断言（6 deny + 6 allow），22 → 34
- **M4 · `install.sh` `git reset --hard` 缺豁免注释**：`do_update` 第 169 行 reset 是对 stage cache 操作，不归 Iron Law 14（PROJECT only）管，但读 diff 的人没线索。补上 4 行注释指明：STAGE_DIR 在 `~/.claude/.cache/` 是 user-global 缓存，installer 拥有的 throwaway clone，Iron Law 14 不适用
- **M5 · `settings.local.template.json` 缺 inline keeper 路径文档**：`=skill` 卸载会原子重写 4 处 `command` 字段为 `${CLAUDE_PROJECT_DIR}/.claude/onboard-keeper/hooks/<name>.sh`（元规则 26），但每个 hook 块只在 file-top `_comment` 提了一次，深层 reader 易漏。每个 matcher 块加 `_keeper_command_after_skill_uninstall` 字段就近标注 post-rewrite 路径；标准 JSON parsers 忽略 underscore-prefix 未知字段，jq atomic rewrite (元规则 26) 只动 `.command` 不动该注解字段，所以无副作用

### Added

- **L1 · `mirror-hooks.sh` cmp -s fast path**：源 = 目标已相同时跳过 `cp` + `chmod` + manifest 重写，让"幂等无开销"可观察。日志：变化时 `mirrored N hooks (v$V) → $DEST (M unchanged)`；全 unchanged 时 `no changes — all N hooks already current (v$V) at $DEST`；只有源版本改但内容相同时 `refreshed manifest (v$V) → $DEST (all N hooks already current)`。`mirrored_at` 字段语义收紧：现在反映"最近一次真实 mirror 操作"，不再是"最近一次调用"——便于诊断真实变更点。`hook-mirror.sh` 加 4 个断言（manifest TS 不变 / "no changes" 日志 / drift 后重写 / 单文件 mirrored count），29 → 33
- **README · "设计承诺" 顶部 section**：明示 Iron Law 7 + 元规则 19 的设计选择——`/onboard` 永不自动执行系统级安装。5 类安装行为（System CLI / dev dep / runtime / CC plugin / Project 文件）逐类列清。避免"一键自动配置"宣传与"逐项 offer-only" 实操之间的张力

### Tests

- 9 个 integration tests / **166 assertions** / 0 fail（+16）
- `bash scripts/verify-counts.sh`：全对齐
- `bash scripts/release-preflight.sh`：本 release 自我验证 PASS

### 升级路径

- 纯 polish + 文档 + 一处明确 bug fix，无 schema 破坏，无 user-facing flag 变化
- v2.11.2 → v2.11.3：`bash install.sh update`；已 onboarded 项目无需重跑

---

## v2.11.2 — release-preflight 维护脚本

把 `feedback_cross_cutting_grep` + `feedback_git_index_chmod_on_new_sh` + `feedback_release_commit_staging` + `scripts/verify-counts.sh` 四类 pre-commit hygiene 合成单一 `scripts/release-preflight.sh`。纯维护工具，无 /onboard runtime behavior 变化。

### Added

- **`scripts/release-preflight.sh`**（~210 行 bash）— `git add -A` 后 `git commit` 前跑一次，4 步：
  1. **Version-bump completeness** — positive check 7 个 pinned 位置（plugin.json / marketplace.json / SKILL.md title / 2 个 settings template `_onboard_version` / CLAUDE.md 当前版本 / README.md 当前版本）都已显示 NEW_VERSION。避免了对 OLD_VERSION 直接 grep 产生的 historical-fact false positive 漩涡
  2. **chmod +x on staged-new `.sh`** — 自动 `git update-index --chmod=+x $f` 对所有 staged 新建 `.sh` 文件，解决 `feedback_git_index_chmod_on_new_sh` 三次连续 followup commit 的 root cause
  3. **verify-counts.sh** — propagate exit；blocking
  4. **Staged-file sanity** — warn on working-tree-only edits + untracked files（不进 commit 静默丢失）
  - **退出码契约**：0 = 可 commit；1 = blocking drift（pinning 不全 / counts 漂移）；2 = 调用错
  - 用法：`bash scripts/release-preflight.sh [OLD_VERSION] [NEW_VERSION]`；裸跑自动从 `plugin.json` 和 CHANGELOG.md 推
- CLAUDE.md inventory 一行更新提到 `release-preflight.sh`

### Changed

- memory `feedback_git_index_chmod_on_new_sh.md`：尾段从"建议 future script"降级为"v2.11.2 已实现该 script"的指针 + 保留 WHY 解释段供未来维护者参考

### Tests

- 仍 9 个 integration tests / 150 assertions / 0 fail
- `bash scripts/verify-counts.sh`：全对齐
- `bash scripts/release-preflight.sh`：本 release 自我验证 PASS（version-bump 7/7 + chmod 1 file +x + verify-counts OK + sanity 无 warning）

### Known limits

- v2.11.0 known limits 全部沿用：plugin 端到端 dogfood + `=skill` 沙箱 jq 跑通仍未做（v2.12 batch）
- release-preflight.sh 的 OLD_VERSION grep（step 1b）目前是 informational warning，不阻塞——本身就难自动判断 "historical fact" vs "drift"。后续如积累足够 false-positive pattern 再 tighten

### 升级路径

- 维护脚本类 patch，无 schema / 行为变化
- v2.11.1 → v2.11.2：`bash install.sh update`；已 onboarded 项目无需重跑
- 仓库维护者第一次跑：`bash scripts/release-preflight.sh` 即可

---

## v2.11.1 — code-review follow-up patch

4 条 P-A-followup fixes（reviewer-surfaced Important 全收）+ 1 个新维护脚本。源自 v2.11.0 ship 后 `superpowers:requesting-code-review` 跑出的发现，无 schema 破坏，无 user-facing flag 变化。

### Fixed

- **Issue #1**：`CLAUDE.md` inventory line per-test counts 修正：`skillmd-links.sh` 22 → 9；`hook-behavior.sh` 24 → 22（claimed total 仍是 150，但 per-test claim 总和 165 ≠ 150 — 修后 9+22+29+34+24+8+2+1+21 = 150 一致）；删除误导性 "counts include hdr lines" 副括号
- **Issue #2**：SKILL.md `=skill` 流程步骤 2 rollback 顺序收紧 — snapshot 提到子步骤 2.0（先于 keeper 创建），按已完成步骤号 0..4 给出精确回滚矩阵 + 明确"绝不允许 settings 已重写但 keeper 不存在"作为 元规则 26 实操不变量。原 spec 把 snapshot 放在 atomic jq 重写一节里，逻辑上正确但顺序与 prose 描述错位，若 step 1-2 (mkdir+cp) 部分失败时回滚 prose 读起来"还原 snapshot"是 no-op
- **Issue #3**：SKILL.md `=all` 流程 step 3 AUTH chain 歧义消除 — 显式声明 step 2 干跑预览的 hard AUTH 已覆盖 L1+L2+L3 所有删除类，子步骤里不再弹 AUTH；防止 implementing Claude 因 元规则 22 "no batch AUTH for uninstall" 误以为要逐子步骤再触发 AUTH
- **Issue #4**：`install.sh` do_uninstall pre-prompt 一致性 — 原 `cd <project> && /onboard --uninstall` 与同文件 HELP 块 `--uninstall=all` 不一致；现两行分别提示 `=all`（完整清理）和 `=skill`（仅卸 user-global），同步 HELP 文案

### Added

- **`scripts/verify-counts.sh`** — 维护脚本：直接跑 `tests/integration/*.sh` 收集 per-test `pass: N`，对账 `CLAUDE.md` headline + per-test counts + `CHANGELOG.md` latest section TOTAL。`feedback_cross_cutting_grep.md` lesson 的机械化对账实现。**不**接入 `tests/run.sh`（会递归调自身）；release 前手动跑或 wire 进 pre-commit hook
  - Exit 0 = 全对齐；1 = drift；2 = 调用 / 解析错
  - 本次 release 跑通：actual 150 across 9 tests，匹配 CLAUDE.md 与 CHANGELOG v2.11.0 段

### Changed

- `tests/integration/uninstall-modes.sh`：snapshot-元规则 21 grep 模式 wording-tolerant 化（reviewer rec #9）— 从 `'snapshot per 元规则 21'` 精确匹配改成 `'snapshot.*元规则 21|元规则 21.*snapshot'` 双向，避免 spec wording 微调即破测试

### Tests

- 仍 9 个 integration tests / 150 assertions / 0 fail
- `scripts/verify-counts.sh` 跑通：全部 per-test claim + headline + CHANGELOG 引用一致

### Known limits

- v2.11.0 known limit 仍在：真实 `/plugin install onboard` 端到端 dogfood + `=skill` 沙箱 jq 跑通仍未做。本 patch 没扩 scope 去补它们，留给 v2.12 batch

### 升级路径

- 纯文档 / 实操约束 patch，无 schema 破坏
- v2.11.0 → v2.11.1：`bash install.sh update`（自动从 stage cache 拉新版）；已 onboarded 项目无需重跑

---

## v2.11.0 — uninstall 三层模型 + CC plugin detection + install.sh 自动化

8 条 P-A items（4 HIGH / 3 MED / 1 LOW）batched into single minor release。Source：2026-05-15 全仓审计 + v2.10.2 ship-后设计讨论。无 schema 破坏，所有改动 Δ-contract additive 或向后兼容。

### Migration (read first)

- 旧 `/onboard --uninstall` 用户：行为不变。裸 `--uninstall` ≡ `--uninstall=all`（向后兼容到 v2.8）
- 新 `--uninstall=skill` 模式：仅卸 user-global skill，保留所有项目侧配置 + hook 脚本（local-only 模式会自动把 hook 复制到 `.claude/onboard-keeper/`）
- `install.sh install` 行为变化：default 覆盖（v2.10.x 是 exit-if-exists）。要恢复旧行为加 `ONBOARD_NO_OVERWRITE=1`
- v2.10.x → v2.11.0：`install.sh update`；已 onboarded 项目无需重跑

### Added

- **P-A1 (HIGH)** **CC plugin as target project**：onboard 自己 dogfood / CC plugin 开发者用 /onboard 时，detection 正确识别
  - Phase 1 探测矩阵新增根级 row：`.claude-plugin/plugin.json` + (`hooks/`/`skills/`/`commands/`/`agents/`/`.mcp.json`) → CC plugin 栈 + `cc_plugin: true` 标志，与对应语言栈并存
  - Phase 1 Forbidden zone candidates 新增 item 5：plugin.json / marketplace.json / .mcp.json（手编辑破坏 Claude Code plugin install / marketplace 索引）
  - Phase 1.7 A8 recipe 扩展：CC plugin manifests 自动列入 `confirmed_forbidden_zones`
  - Phase 3 模板新增 conditional `## Plugin` 节（仅 `cc_plugin: true` 栈输出）：Manifests / Components / Install topology / Hook path strategy 四类信息
  - Phase 3 验证规则强制：cc_plugin 栈必须有 `## Plugin` 节
- **P-A7 (HIGH)** **local-only mode `--uninstall=skill` 自动 hook 本地化**：解决"卸 skill 后 hook 路径 `~/.claude/skills/onboard/hooks/` 不复存在 → settings.local.json 引用 broken path → 后续 PreToolUse/Stop hook silent fail exit 127"问题
  - Keeper 目录 `.claude/onboard-keeper/hooks/` + `scripts/`，加入 `.git/info/exclude`（LOCAL-SIDE-EFFECT 不入仓）
  - jq atomic 重写 settings.local.json 4 个 hook command 路径（snapshot per 元规则 21；tmp + mv per Iron Law 14）
  - 失败原子回滚（任一步骤失败 → 还原 settings + rm keeper + abort）
  - Share 模式无需本地化（hook 脚本本来就在项目内 `.claude/skills/onboard/hooks/`）
- **P-A8 (MED)** **`install.sh install` 默认覆盖**：v2.10.x exit-if-exists 改成 silent overwrite + `[onboard]` 提示行；`ONBOARD_NO_OVERWRITE=1` 保留旧行为
- **P-A9 (MED)** **`install.sh do_uninstall` 自动清 mirror 目录**：v2.10.1 引入的 `~/.claude/onboard-runtime/hooks/` plugin-mode mirror 之前没人清理；现在 uninstall 一并 rm + `rmdir ~/.claude/onboard-runtime` 兜底
- **P-A10 (LOW)** **`--uninstall=skill` 非交互调用约定**：consumer Claude 自己做 spec 内 hard AUTH，install.sh stdin 提示作 redundant；约定 `ONBOARD_CONFIRM_UNINSTALL=yes ONBOARD_UNINSTALL_MODE=skill bash install.sh uninstall`
- **3 个新 元规则**：
  - 元规则 24（uninstall 三层语义）：L1 user-global / L2 project-config / L3 project-files 各自定义清楚清理边界
  - 元规则 25（分层各自 hard AUTH）：`--uninstall=skill` 一次 AUTH；`=all` 每个 L2 entry 类单独 AUTH（延续 元规则 22 "no batch AUTH for uninstall"）
  - 元规则 26（skill 卸载必须保 hook 路径连续性）：local-only `=skill` 三步本地化 (cp / jq atomic edit / exclude 写入)，任一失败原子回滚
- **新增 3 个 integration tests + 1 新 + 2 扩展**：
  - `tests/integration/cc-plugin-detection.sh`（8 assertions）锁 P-A1 spec
  - `tests/integration/prepare-script-detection.sh`（2 assertions）锁 P-A2
  - `tests/integration/sync-versions-detection.sh`（1 assertion）锁 P-A3
  - `tests/integration/uninstall-modes.sh`（21 assertions）锁 P-A6/A7/A10 spec：argument-hint / 参数解析 / 三层模型 / 模式 1+2 流程 / keeper / 元规则 24/25/26 / 元规则 22 修订 / 非交互约定
  - `tests/integration/install-roundtrip.sh` 扩展（25 → 34 assertions）覆盖 P-A8/A9：overwrite / no-overwrite / mirror cleanup / ONBOARD_UNINSTALL_MODE env validation
- `install.sh` 新增 env：`ONBOARD_NO_OVERWRITE` / `ONBOARD_UNINSTALL_MODE`

### Changed

- **P-A6 (HIGH)** **`--uninstall` 参数化为 `[=skill|all]`**：
  - frontmatter `argument-hint` 更新
  - 参数解析增 `=skill` 与 `=all` 各自语义说明 + 向后兼容声明
  - Uninstall Mode 章节整段重写（v2.8 单模式 → v2.11 三层模型 + 双模式 + 默认值约定 + 与 install.sh 分工表更新）
  - SKILL.md 2336 → 2457 行（+121 / +5.2%）
- **元规则 22 修订**（v2.8 → v2.8 / v2.11）：区分 `=all` 和 `=skill` 的 hard AUTH 颗粒度
- **元规则 header**：v2.9 共 23 条 → v2.11 共 26 条
- **Mode model 文件归宿表**新增 keeper 行：`--uninstall=skill` 后自动生成的 `.claude/onboard-keeper/hooks/` 归宿
- **P-A2 (MED)** Phase 6 hook 框架选型新增 item 5：`package.json scripts.prepare` 写 `.git/hooks/` 模式识别为已存在 ad-hoc hook 框架，标 `hook-prepare-script` third-party 共存，不再走 hook-local 候选
- **P-A3 (LOW)** Phase 1.7 A6 (`behavioral_donts`) recipe 扩展：检 `scripts/sync-version*` / `scripts/version-bump*` 写入 ≥2 manifests → 同步目标列入 Phase 3 `## Don't`
- `settings.local.template.json` `_comment` 扩展：解释 v2.11 keeper 路径重写机制
- `settings.template.json` `_comment` 扩展：解释 share 模式下 `=skill` 是 L1 only no-op-on-project
- `install.sh` 顶部 Environment 块 + HELP 块同步新增 env 文档

### Tests

- 5 → 9 integration tests，109 → 150 assertions（+41 / +38%）
- 所有 9 个 test PASS / 0 FAIL
- 新 sandbox 路径无（新 tests 都是 spec-grep / 不创建 sandbox）；uninstall-modes.sh 复用 + install-roundtrip.sh 扩展复用现有 `/tmp/onboard-install-sandbox`

### Known limits

- **Plugin-as-target dogfood**：v2.10 known-limit 仍在 — 真实 `/plugin marketplace add sdsrss/onboard` + `/plugin install onboard` 端到端 dogfood 尚未在 v2.11.0 release 时跑通；ship 后立即在本 repo 自身跑 dogfood，发现 gap 进入 v2.12 P-B 队列
- **`=skill` 模式 hook 本地化的 atomic 回滚**：spec 已写清要求，但 consumer Claude 实际跑 jq + cp + rm 时若中途 IO 失败的回滚路径还未在沙箱测试，依赖元规则 26 + 元规则 22 重入约束在真实运行时收敛

### 升级路径

- v2.10.x → v2.11.0：`bash install.sh update`（自动从 stage cache 拉新版）；已 onboarded 项目用 `/onboard --update` 同步 settings 模板新 _comment 文案
- 想试 `=skill` 模式：先 onboard 一个项目 → `/onboard --uninstall=skill` → 观察 `.claude/onboard-keeper/` 生成 + settings.local.json 路径重写 → 后续 hook 调用仍走 keeper

---

## v2.10.2 — v2.10.1 后全仓审计

10 条 P-B fixes（2 HIGH / 4 MED / 4 LOW），均源自 2026-05-15 全面审计；不破坏兼容。

### Fixed

- **P-B1 (HIGH)**：`hooks/guard-bash.sh` deny 模式作子串匹配致所有 `rm -rf /<subpath>` 误拒
  - 错例：`rm -rf /tmp/foo` / `rm -rf /var/log/old` / `rm -rf ~/.cache/foo` / `rm -rf $HOME/cache` 都被拦
  - 原因：grep -qE `'rm -rf /'` 在 `rm -rf /tmp/foo` 字符串内匹配为子串 → 触发 deny
  - 修复：锚定为 `'rm[[:space:]]+-rf[[:space:]]+/[[:space:]]*($|[;&|])'` 三个 root-target 模式（`/`、`~`、`$HOME`），只在删除目标本体或链式起始（`/ && ...`、`/;...`）时 deny；正常 subpath 删除全部放行
- **P-B2 (HIGH)**：`post-edit-check.sh` / `stop-verify.sh` 硬编码 `LOG_DIR=".claude/onboarding-logs"` 在 local-only 模式下泄漏日志到 PROJECT 工作树
  - meta-rule 13 + Mode model 不变量"local-only 不动 PROJECT" 违规：模板已正确路由 `ONBOARD_TOUCHED_LOG` / `ONBOARD_STACKS_FILE` 到 `.claude/local-only/onboarding-logs/`，但 hook 自己写 `stop-lint-*.log` / `post-edit-check.log` 仍用 share 默认路径
  - 修复：引入 `ONBOARD_LOG_DIR` env；两个模板分别设为 mode-aware 路径并注册到 `_onboard_managed_env_keys`；hook fallback 到 share 默认保持 backwards 兼容
- **P-B4 (MED)**：`stop-verify.sh` 文件名含空格 word-splitting bug
  - 错例：`src/has space.ts` 被 `tr '\n' ' '` + `for f in $TOUCHED_FILES` 拆成 `has` + `space.ts` 两个错误参数喂给 lint
  - 修复：改用数组读 + `printf %q` 跨 `bash -lc` 边界保形

### Changed

- **P-B3 (MED)** SKILL.md `示例脚本 3/4`（Phase 7）同步到 canonical `hooks/*.sh`：补 v2.5 跨平台 timeout shim、v2.10 strict-mode `FMT_CMD` 分支、v2.10.2 `ONBOARD_LOG_DIR` 和空格安全的 array+`printf %q` 文件名分发；脚本顶部加 canonical pointer 注释，防 Command-mode fallback 按 spec 重生时退化到老版本
- **P-B5 (MED)** Doctor mode sample output 补 D15（uninstall reversibility）；定义表里有 D1-D15，sample 只列到 D14 导致 consumer Claude 按 sample 输出永远漏 D15
- **P-B6 (MED)** SKILL.md `<hook 路径>` 替换表从 2 项（Skill / Command）扩到 5 项（Plugin via mirror / Plugin direct opt-in / User-global Skill / Project-shared Skill / Command），与上方"install 来源 × 路径"表对齐
- **P-B7/B8 (LOW)** settings 模板 `_onboard_version` 8 处从 `"2.8"` 同步到 `"2.10.2"`；两个模板顶部 `_comment` 字段也带上 v2.10.2 引用 + ONBOARD_LOG_DIR 描述
- **P-B9 (LOW)** `tests/run.sh` / `tests/integration/{plugin-install,skillmd-links,hook-behavior}.sh` 从 git index `100644 → 100755`，与 `hook-mirror.sh` / `install-roundtrip.sh` 已有的 100755 对齐；实际不影响 `bash <file>` 调用但文件 mode 一致性以及 CLAUDE.md 文档 claim
- **P-B10 (LOW)** `install.sh do_uninstall` rm -rf 前加 `case` guard 拒绝空 / `/` / `/.` / `/..` 这类可疑值；`set -u` 之前已隐式保护，但 §8 SAFETY 严格读要求显式 validate-VAR-before-rm

### Added

- `tests/integration/hook-behavior.sh`（22 assertions）锁住 P-B1/B2/B4 不复发：
  - 6 条 guard-bash allow-list（legitimate subpath 删除）
  - 6 条 guard-bash deny-list（真危险）
  - 4 条 guard-bash 其他模式（chmod 777 / force-push / curl|sh / >.env）
  - 6 条 stop-verify + post-edit-check 的 `ONBOARD_LOG_DIR` 路由 + 空格安全
- `tests/run.sh` 测试数 4 → 5，总断言 87 → 109，sandbox 清理增加 `/tmp/onboard-hook-sandbox`

### 升级路径

- 纯补丁，无 schema 破坏
- 已 onboarded 项目应跑 `/onboard --update` 把 `ONBOARD_LOG_DIR` 加进 settings env；或手动从模板复制对应一行
- v2.10.1 用户直接 `install.sh update`

---

## v2.10.1 — v2.10 后 dev infra 打磨

### Added

- **`tests/` 测试基础设施入库**：v2.10 release 后从 `/tmp/onboard-plugin-test.sh` 迁入 repo
  - `tests/integration/plugin-install.sh`：24 项沙箱断言，改用 `$SCRIPT_DIR/../..` 自动定位 repo root（消除硬编码绝对路径）；执行前检查 `jq` / `rsync` + `.claude-plugin/` 存在性
  - `tests/run.sh`：通用 runner，自动跑 `tests/integration/*.sh`，聚合退出码；支持 `bash tests/run.sh <name>` 单跑
  - v2.10 的 "24 pass / 0 fail / 0 warn" claim 从 ephemeral `/tmp` 变成 in-repo 回归保护
- **`install.sh do_uninstall` 警告扩充**：列出 4 类 NOT removed 项（per-project state、hook entries、CLAUDE.md / CLAUDE.local.md 内容、`.gitignore` / `.git/info/exclude`），并在 rm 成功后打印手动清理 recipe（针对忘记跑 `/onboard --uninstall` 的用户）
- **`skills/onboard/scripts/mirror-hooks.sh`（v2.9 prose-only 策略 → v2.10.1 可执行 helper）**：plugin 模式默认调用该脚本把 4 个 hook 从 ephemeral `${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks/` 镜像到稳定的 `${HOME}/.claude/onboard-runtime/hooks/`；同时写 `.mirror-manifest.json`（version + source + dest + mirrored_at + hooks）用于诊断
  - 幂等：同 source 重跑 → 内容不变；新 source（plugin update）重跑 → manifest.source 更新
  - 自动检测：无 `ONBOARD_MIRROR_SOURCE` env 时从脚本 sibling `../hooks/` 取（plugin 实际部署形态）
  - 错误处理：source 目录不存在 / 缺少 4 个必需 hook → exit 非零
  - `install.sh deploy_skill_from_stage` 同步加 `chmod +x "$INSTALL_DIR/scripts/"*.sh`
- **`tests/integration/hook-mirror.sh`**：27 项断言（覆盖 mirror-hooks.sh 全部行为：fresh mirror / manifest schema / 幂等性 / plugin-update 模拟 / 自动检测 / 错误路径），首跑 27 pass / 0 fail

### Changed

- **SKILL.md Phase 7 plugin 模式策略**（line 1326 / 1334-1337 / 1347）：
  - 修正 v2.10 layout 漏改：所有 `${CLAUDE_PLUGIN_ROOT}/hooks/*.sh` 引用补齐为 `${CLAUDE_PLUGIN_ROOT}/skills/onboard/hooks/*.sh`（v2.10 已把 hooks 移到 `skills/onboard/hooks/`，但 Phase 7 prose 没同步更新——consumer Claude 按旧 spec 走会找不到文件）
  - 选项 B（镜像，默认）从 prose-only "复制 hooks 到稳定路径" 落地为调用 `${CLAUDE_PLUGIN_ROOT}/skills/onboard/scripts/mirror-hooks.sh`，consumer Claude 不再需要现场实现镜像逻辑（之前要按 spec 自己写 mkdir/cp/chmod/manifest 一遍——失败模式多、且不幂等）

### Removed

- **`scripts/lifecycle/*.sh`（3 文件，~3.7 KB）**：v2.8 误以为是 Claude Code plugin lifecycle hook，但 plugin 系统根本没有此概念；脚本自描述 "Plugin install lifecycle hook" 与现实矛盾。v2.10 已在 CHANGELOG 标过"角色尴尬"。`install.sh` 已自带全部 chmod / 健康检查 / 引导文案逻辑——3 脚本是 orphan dead code，没有任何调用者（grep `scripts/lifecycle` 在 install.sh 内零命中）
  - 有用文案没丢：`scripts/lifecycle/uninstall.sh` 那段 "what this uninstall does NOT do" + 手动清理 recipe 已 merge 进 `install.sh do_uninstall`
  - 同步清理：CLAUDE.md "What this repo is" 段；CLAUDE.md Validation commands 段 `bash -n` glob；README.md 仓库布局 tree diagram

---

## v2.10 — 结构修正：sandbox 测试通过 `/plugin install onboard`

实测发现 v2.9 仍有两个阻塞性问题，**真实 `/plugin install onboard` 不会工作**。v2.10 修复并通过 24 项沙箱模拟测试。

### Fixed（v2.9 的两个 ship-blocker）

- **结构性 BUG**：SKILL.md 在仓库根；hook 脚本在 `hooks/` 根。Claude Code plugin auto-discovery **只扫描 `skills/<name>/SKILL.md`**——根级 SKILL.md 完全被忽略。结果：`/plugin install onboard` 成功，但 `/onboard:onboard` 命令不存在
  - **修复**：`git mv SKILL.md → skills/onboard/SKILL.md`；`git mv hooks/ → skills/onboard/hooks/`；`git mv settings.template.json → skills/onboard/`；`git mv settings.local.template.json → skills/onboard/`
  - 现在 plugin install 后，Claude Code 发现 `skills/onboard/SKILL.md` → 注册 `/onboard:onboard` slash command
- **Git executable bit BUG**：v2.4–v2.9 期间所有 `*.sh` 在 git index 中是 `100644`（无执行位）。本机 ACL 让脚本看起来 executable，但任何 clone（包括 Claude Code 的 plugin install、install.sh 的 git clone）拿到的都是 non-executable
  - **修复**：`git update-index --chmod=+x` 应用到 8 个脚本（4 hooks + install.sh + 3 lifecycle）；现在 index mode 全部是 `100755`
  - 影响：标准 `git clone` 也能直接跑脚本了，不再需要手动 chmod

### Added

- **沙箱端到端测试**（`tests/integration/plugin-install.sh`，通过 `tests/run.sh` 调度）：模拟 `/plugin marketplace add sdsrss/onboard` + `/plugin install onboard` 完整流程
  - 24 项检查：marketplace.json schema、kebab-case、reserved-name；plugin.json schema、name 一致性；component auto-discovery（skills/ commands/ agents/ hooks/.mcp.json/.lsp.json）；`${CLAUDE_PLUGIN_ROOT}` 解析；hook 脚本可执行 + 行为；slash command 注册
  - 当前结果：**24 pass / 0 fail / 0 warn**
  - v2.10 release 后入库（先前位于 `/tmp/onboard-plugin-test.sh`，重启即失）；现在 `bash tests/run.sh` 直接跑，repo 内回归保护

### Changed

- **install.sh 重新设计**：v2.9 假设 clone 整个 repo 到 install 目录；v2.10 改为 staging-then-copy 模型
  - Stage cache：`~/.claude/.cache/onboard-source/`（保留 .git 用于 update）
  - Install/update 时从 `<stage>/skills/onboard/*` 复制到 install target
  - Uninstall 同时清 stage cache
  - 还顺便复制 README/CHANGELOG/LICENSE 到 install target 作为本地参考
- **plugin.json + marketplace.json 版本号 → 2.10.0**
- **SKILL.md 标题版本号 → v2.10**

### Known limits

- 仍未在真实 `/plugin install onboard` 端到端 dogfood（沙箱测试是 spec-compliant 模拟，假设 Claude Code 严格按 docs 行为；实际可能有边缘差异）
- Phase 7 plugin 模式 hook 镜像策略（v2.9 引入）的实际行为还没在真 plugin install 验证；需要 v2.11 实测后调整
- 历史 v2.4-v2.9 用户从 git clone 装的项目级 skill，clone 后 hook 不可执行——他们要么重装、要么手动 chmod；下一版 SKILL.md Phase 7 可加自动 chmod 修复

---

## v2.9 — 标准 Claude Code plugin marketplace 支持

实现官方 `/plugin marketplace add sdsrss/onboard` + `/plugin install onboard` 流程。修正 v2.8 对 plugin 系统的几个错误假设。

### Added

- **`.claude-plugin/marketplace.json`**（关键缺失）：仓库根 marketplace catalog，符合 Claude Code 官方 marketplace schema（`name`/`owner`/`plugins[]`）。这是 `/plugin marketplace add sdsrss/onboard` 成功的必要条件
- **Phase 7 install 来源检测**：四种来源自动识别
  - Plugin（`/plugin install onboard`）：检测 `${CLAUDE_PLUGIN_ROOT}` 环境变量 + SKILL.md 路径含 `/.claude/plugins/cache/`
  - User-global skill（`install.sh install`）：检测 SKILL.md 在 `~/.claude/skills/onboard/`
  - Project-shared skill（手动 clone 到项目内）：检测 SKILL.md 在 `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/`
  - Command（旧版兼容）：commands 路径
- **Plugin 模式 hook 镜像**：plugin 缓存路径含版本号且会随 update 变化（`~/.claude/plugins/cache/onboard@onboard@<ver>/`），onboard v2.9 在 plugin 安装下**默认镜像** hook 到稳定位置 `~/.claude/onboard-runtime/hooks/`，user settings 引用镜像；plugin 升级后用户跑 `/onboard --update` 同步
- **元规则 23**（v2.9 新增）：plugin 路径用 `${CLAUDE_PLUGIN_ROOT}` 但禁止硬编码到 user settings；默认走 hook 镜像

### Changed

- **`.claude-plugin/plugin.json` 精简到官方 schema**：移除 v2.8 引入的非标准字段 `lifecycle` / `platform` / `dependencies` / `supports` / `skills[]` / `files`（这些字段 Claude Code plugin 系统并不解析）。保留官方 schema 字段：`name` / `description` / `version` / `author` / `homepage` / `repository` / `license` / `keywords`
- **`scripts/lifecycle/*.sh` 角色澄清**：这些脚本**不是** Claude Code plugin 生命周期钩子（plugin 系统没有 install/update/uninstall hooks 概念）；它们是 `install.sh` 通用安装器的辅助脚本。在 README 与 CHANGELOG 明确标注，避免误导
- **Phase 7 publish path 决策表升级到 4 行**：v2.8 的 2 维表（skill/command × local-only/share）扩展为 install 来源 × 模式
- **状态文件 schema v2.9**：增加 `install_source`（plugin / user-skill / project-skill / command）+ `hook_runtime_dir`（plugin 模式镜像路径）
- **Phase 0.5 Migration**：补 v2.8→v2.9 字段映射；检测当前 install 来源 + 重写 settings 中 hook 路径

### Fixed

- **v2.8 误以为 plugin 有 lifecycle hooks**：实际 Claude Code plugin 系统是文件复制 + skill/agent/hook/mcp/lsp 自动发现，**没有** install/update/uninstall lifecycle script 概念。v2.8 创建的 `scripts/lifecycle/*.sh` 实际不会被 `/plugin install` 调用——仅在 `install.sh` 通用安装器路径下有意义
- **v2.8 plugin.json schema 偏离官方**：`lifecycle` / `platform` / `dependencies` 等字段是臆想，Claude Code 实际 schema 只有 `name` / `description` / `version` / `author` 等基础字段。v2.9 已纠正
- **v2.8 hook 路径在 plugin 模式下错误**：settings 模板用 `${CLAUDE_PROJECT_DIR}` / `${HOME}`，但 plugin 安装下文件在 `~/.claude/plugins/cache/onboard@<marketplace>@<ver>/` —— 两种变量都不指向那里。v2.9 引入 `${CLAUDE_PLUGIN_ROOT}` 识别 + 镜像策略

### Known limits

- Plugin 模式镜像策略尚未在真实 `/plugin install onboard` 上端到端验证；可能需要根据 Claude Code 实际行为调整
- `scripts/lifecycle/*.sh` 现在角色尴尬（不是 plugin lifecycle，也不是必需），下一版可能考虑删除或重组
- marketplace.json 中 plugin source 用 `"./"` 表示"plugin 即 marketplace 根目录"——这种单 plugin 仓库布局在 Claude Code 实际行为下是否兼容，需要 dogfooding 验证

---

## v2.8 — 完美的安装/更新/卸载

把"装得上、留得净、卸得干净"做到 Iron 级。两条安装通道并行存在 + 全链路可逆性 + snapshot/restore。

### Added

- **`install.sh` 通用安装器**（`curl | bash` 友好）：
  - `install` / `update` / `uninstall` / `doctor` / `help` 五个子命令
  - 全局（`~/.claude/skills/onboard/`）或项目内（`./.claude/skills/onboard/`）安装目标
  - `update` 前检查工作树干净（`ONBOARD_ALLOW_DIRTY=1` 可绕过）
  - `uninstall` 默认交互确认；`ONBOARD_CONFIRM_UNINSTALL=yes` 非交互
  - `doctor` 检测安装状态 + 必需 / 可选依赖（git/bash/jq + gh/glab/tea/make/coreutils/mise/asdf）
- **`.claude-plugin/plugin.json` 插件清单**：符合 Claude Code 插件规范的 manifest（name / version / skills / lifecycle / supports / platform）
- **Lifecycle scripts**（`scripts/lifecycle/install.sh|update.sh|uninstall.sh`）：Claude Code `/plugin install|update|uninstall onboard` 调用的生命周期钩子；负责 chmod / 健康检查 / 提示语
- **`/onboard --uninstall` 子命令**（项目级卸载）：
  - 按 manifest + marker 反向移除 onboard 在本项目的所有写入
  - 不动用户在 marker 块外的内容
  - 强制 dry-run 预览 + 每类 hard AUTH
  - 提供 snapshot restore 候选（pre-modify 快照）
  - 中途失败可重入
- **Marker 约定**（v2.8 核心可逆性机制）：
  - Line-based 文件（.gitignore / .git/info/exclude / CLAUDE.md 等）：`# >>> /onboard v<ver>` / `<!-- >>> /onboard v<ver> -->` 块标
  - JSON 文件（settings.json / settings.local.json）：每 hook 块加 `_onboard_managed: true` + `_onboard_version` 字段，env 区段加 `_onboard_managed_env_keys` 列表
  - 权威清单：`<state-dir>/onboard-manifest.json` 记录 managed files / blocks / settings paths / snapshots dir
- **Snapshot protocol**：
  - Phase 3/4/6/7/8 首次写入既有 PROJECT 文件前必须快照
  - 文件名 `<basename>.<ISO>.<phase>.pre`，目录 `<state-dir>/onboard-snapshots/`
  - 同时追加 `index.jsonl`（ts/phase/action/sha256）
  - 保留策略：每文件最近 5 个 pre-modify + 1 个 post-install + 每次 update 一个 post-update
- **Doctor mode D15**：卸载可逆性检查（manifest 存在 + managed_files 仍在 manifest 路径上 + 至少一个 pre-modify snapshot 可用）
- **元规则 20–22**（v2.8 新增）：写入必须可逆 / 首次写入前 snapshot / 卸载是单方向不可逆操作

### Changed

- **Settings 模板加 marker 字段**：`settings.template.json` 与 `settings.local.template.json` 现在每个 hook 块和 env 段都带 `_onboard_managed: true` / `_onboard_version` / `_onboard_managed_env_keys`，开箱即可卸载
- **状态文件 schema v2.8**：新增 `onboard_manifest_path`、`snapshots`（dir / index_path / counts / retention）
- **Phase 0.5 Migration**：补 v2.7→v2.8 字段映射；旧版残留 PROJECT 文件自动加 marker；缺 snapshot 的标 `irrecoverable: true`
- **README 重写**："安装" 节给出三条等价路径（plugin / curl bash / 手动 cp）

### Fixed

- v2.7 没有正式的"卸载"通道：用户卸载靠人工手撸路径
- v2.7 不存在写入前 snapshot：误改用户文件后无法 restore
- v2.7 marker 约定模糊：仅 `.gitignore` 大致约定，没规范化到所有写入文件
- v2.7 `.claude/settings.json` 修改不可识别：onboard 与第三方 hook 共存时无法区分谁写的

### Known limits

- `.claude-plugin/plugin.json` 是按现有 Claude Code 插件生态规范推断的合理猜测；实际 plugin 系统对 schema 的要求可能有差异，需要在真实 `/plugin install` 上验证
- Snapshot 占空间：典型项目 12 个 pre-modify snapshot × 平均 5KB = ~60KB，可接受
- v2.7→v2.8 升级时旧 onboarding 的 PROJECT 写入若无 marker → migration 反向扫描加 marker，但 snapshot 历史不可恢复

---

## v2.7 — 深度项目认知 + 提取式 CLAUDE.md + Install orchestration

合并交付原计划中的 v2.7 + v2.8。三大主题：(1) 项目认知深度（Phase 1.7 深度分析）；(2) CLAUDE.md 信息密度反转（提取式模板 + token 预算）；(3) 安装编排（Phase 2.5 Install Plan + Claude Code plugin 推荐矩阵）。

### Added

- **Phase 1.7 · Deep Analysis（新阶段）**：8 维度分析 recipe
  - A1 build_test_invocation：跨任务运行器（package.json scripts / Makefile / pyproject.toml / Cargo / Justfile / Taskfile / turbo / nx / .github/workflows）提取构建+测试命令交集
  - A2 test_subset_invocation：按 framework 给出"只跑一个 test"形式
  - A3 module_dep_direction：grep 抽样 import 跨目录指向，标 one-way / 双向 / via codegen
  - A4 generated_code_dirs：识别 codegen 输出目录与"DO NOT EDIT"文件头
  - A5 naming_convention_anomaly：跨目录命名风格异常（一致则不写）
  - A6 behavioral_donts：从 CONTRIBUTING/CHANGELOG/incident commits/pre-commit/ADR 抽出禁令
  - A7 coverage_signal：检 coverage 配置与 CI 阈值
  - A8 forbidden_zones_v2：CODEOWNERS @archived / .gitattributes export-ignore 补强
- **Phase 2.5 · Install Plan（新阶段）**：四类清单
  - 类 1 dev quality tools（需修 PROJECT，仅 share 模式可装）
  - 类 2 system CLIs（offer-only，跨 OS 命令矩阵）
  - 类 3 language runtimes（首选 mise/asdf）
  - 类 4 Claude Code plugins（按硬编码矩阵推荐 + open recommendation fallback）
- **Claude Code plugin 推荐矩阵（硬编码 15 项）**：claudemd / claude-mem-lite always-on；code-graph-mcp / serena 按 size/stack 数；frontend-design / design-review / qa / setup-deploy / cso / document-release / mcp-builder / seo-* / claude-api / webapp-testing / make-pdf 按检测信号
- **CLI / runtime 安装三层优先级**：mise/asdf → npx/pipx → 系统包管理器；多 OS 命令矩阵（jq / gh / glab / coreutils 覆盖 macOS/Ubuntu/Fedora/Arch/Windows）
- **CLAUDE.md token 预算执行**：soft cap 2500 / hard refuse 5000；`--allow-large-claude-md` flag override
- **CLAUDE.md 自动压缩规则**：5 条按序应用（inline 短列表 / 去 H3 / 合并相近 bullet / 拆 gotchas 到附属文件 / 删空节）
- **Doctor mode D11–D14**：token 预算 / 行格式约束 / plugin 漂移 / install drift
- **元规则 17–19**（v2.7 新增）：token 上限 / Don't 强制一行 / 安装永不自动执行系统级
- **行格式约束 Iron 级**：`## Run` / `## Layout` / `## Don't` / `## Watch out` 强制 format string

### Changed

- **CLAUDE.md 模板哲学反转**：从"填空式 outline"改为"提取式事实集"
  - 任一节无内容 → 整节不写，绝不留 placeholder
  - 模板骨架（type / run / layout / rules / don't / tests / watch out）按需选填
  - 目标尺寸：≤ 2500 tokens（v2.6 之前的填空式典型 80-150 行 ≈ 3000-5000 tokens）
- **Iron Law 7 注释扩写**：明确 batch AUTH = explicit AUTH；禁止"dev-only 无差别豁免"
- **状态文件 schema 升级到 v2.7**：新增 `phase_1_7`（深度分析结果）、`phase_2_5`（安装计划）、`phases.3.claude_md_tokens` / `token_budget_override` / `auto_compressions_applied`、`params.allow_large_claude_md`
- **Phase 0.5 Migration**：补 v2.6→v2.7 字段映射；标 `update_phases: ["1_7", "2_5", "3"]` 触发深度分析 + 模板重写
- **元规则 1**：执行计划现需展示"模式 + 预估 CLAUDE.md token"

### Fixed

- v2.6 CLAUDE.md 填空式模板的 token 浪费：典型项目 80-150 行无内容占位
- v2.6 Phase 1 探测深度不足：构建/测试命令只看 package.json 表层，漏 Makefile/Justfile/Taskfile/turbo/nx/CI 等数据源
- v2.6 没有"禁止操作清单"维度：仅目录禁区，缺行为禁区（don't run X / don't commit to Y）
- v2.6 没有 plugin 推荐机制：装 onboard 后用户不知道还该装啥配套工具
- v2.6 CLI 缺失（jq / gh / glab / coreutils）时仅在 Phase 0 abort，没系统化的 install plan

### Known limits

- 行格式约束验证靠 spot-check 而非 100% 全扫（性能取舍）
- Token 估算 = `wc -c / 4`，粗粒度但够用；要精确装 tiktoken 即可
- Plugin 推荐矩阵硬编码 15 项，覆盖 Claude Code 主流插件；冷门插件走 open recommendation 通道（用户填）
- v2.6→v2.7 升级会重写 CLAUDE.md，备份在 `.claude/onboarding-logs/CLAUDE.md.v26.bak`；属 hard AUTH

---

## v2.6 — Local-only 默认 + 多平台 git host 适配

**重大变更**：默认行为反转。v2.5 及之前默认入仓，v2.6 起默认 **local-only**（不入仓）。理由：现实里大多数公司只有少数人试用 AI 工具，"默认入仓"等于强加 AI 工具给同事——v2.6 反转这个假设。

### Added

- **`--local-only` 模式（默认）**：
  - 知识文件写入 `CLAUDE.local.md`（Claude Code 原生 per-user 路径）
  - 设置文件写入 `.claude/settings.local.json`（Claude Code 原生 per-user override）
  - State / logs 写入 `.claude/local-only/` 命名空间
  - 所有路径自动加入 `.git/info/exclude`，**零 .gitignore 改动**，团队 pull 后完全看不到 onboard 痕迹
  - Hook 引用全局 skill 路径 `~/.claude/skills/onboard/hooks/...`，无项目内 skill 副本
  - Forbidden zones 仅通过 hook env 强制，**不注入** PROJECT 的 lint ignore 文件
- **`--share` 模式（opt-in）**：v2.5 及之前的入仓行为；现需显式声明
- **Git host adapter 抽象**：统一支持 GitHub (`gh`) / GitLab (`glab`) / Gitea-Forgejo (`tea`) / Bitbucket / unknown
  - Phase 0 自动探测 host + CLI 可用性
  - `--share --isolate-branch` 模式 Phase 8 末尾按 host 调用对应 PR/MR 命令（只 offer 不自动执行）
  - PR/MR body 从状态文件自动生成
- **Git 拓扑 hard-block**：submodule / bare repo / detached HEAD 三种状态 Phase 0 立即 abort；shallow / worktree 仅 warn
- **Team-signal 评分**（6 信号 / 阈值 ≥2 判 team）：CODEOWNERS、PR template、6 月内 committer ≥3、CI 分支保护规则、企业 remote URL、CONTRIBUTING.md
- **分支前缀自动探测**：从 `git for-each-ref` 推断团队习惯前缀（chore / infra / feat / platform / tooling），fallback `chore`
- **Doctor mode D8–D10**：模式一致性 + `.git/info/exclude` 完整性 + host adapter 就绪度
- **元规则 13–16**（v2.6 新增 4 条）：默认 local-only / 拓扑 hard-block / 模式不可单方面切换 / PR-MR 决不自动执行
- **`settings.local.template.json`**：新增 local-only 模式参考模板

### Changed

- **默认行为反转**：无 `--share` 参数 = local-only。需要团队共享必须显式 `--share`
- **状态文件路径分流**：local-only → `.claude/local-only/onboarding-state.json`；share → `.claude/onboarding-state.json`
- **Phase 0 增 4 个子步骤**：git 拓扑检测、team-signal 评分、host 探测、模式确认
- **Phase 3 决策树拆 mode 分支**：local-only 写 `CLAUDE.local.md`，share 写 `CLAUDE.md`
- **Phase 7 加 mode 维度**：local-only 模式 settings → `settings.local.json` + hook 引用全局路径
- **Phase 8 完全重构**：local-only 不动 .gitignore，share 模式保留原 Case A/B
- **状态文件 schema 升级到 v2.6**：新增 `mode` / `mode_migration` / `git_topology` / `team_signals` / `git_host` / `git_info_exclude_injected`
- **阶段卡片契约**：新增 `mode` 字段
- **Phase 0.5 Migration**：补 v2.5→v2.6 字段映射；v2.5 之前默认 share → 升级保留 share 模式

### Fixed

- 老 spec 默认入仓的设计盲点：未考虑大多数公司"个别人用 AI"的真实场景
- 缺乏 GitLab / Gitea 等平台支持：v2.5 之前 PR 概念隐含 GitHub
- 没有 git 拓扑检测：submodule / bare / detached HEAD 下跑会出诡异故障

### Known limits

- PR/MR 自动开 = offer + ASK，永不自动执行（设计选择，开 PR 是不可逆外部副作用）
- Bitbucket 缺主流 CLI → fallback 到 web URL
- Windows 原生仍不支持（用 WSL2）

---

## v2.5 — 跨平台 + Doctor 模式

短期补丁版。解决 v2.4 ship 后暴露的几个真实痛点：macOS 无 `timeout` 命令、跑完 onboard 后没健康检查、与 `claudemd` 插件无明确分工、缺开源协议声明。

### Added

- **跨平台 `timeout` shim**：`stop-verify.sh` / `post-edit-check.sh` 顶部内联兼容代码——缺 `timeout` 时优先用 `gtimeout`（macOS coreutils），仍缺失则退化为无超时（保命，不再让 macOS 用户首个 Stop hook 触发就挂）
- **Doctor 模式** (`/onboard --doctor`)：7 项健康检查（state schema / 栈一致性 / forbidden 路径存活 / hook 引用 / 脚本语法 / settings JSON 合法性 / 可执行权限），输出 `healthy | drifted | broken` 三态 + actionable 建议；不跑任何 Phase，不写 PROJECT/OUTPUT
- **Phase 3 claudemd 共存声明**：探测到 claudemd 插件存在时，onboard 只生成 `## Stacks` / `## Forbidden` / `## Testing` / `## Change Policy` 节，不动 claudemd 管辖的规范节，避免双工具打架
- **LICENSE (MIT)**：补开源协议声明，扫清团队 / 商业使用的合规障碍

### Changed

- Frontmatter `argument-hint` 加 `--doctor`
- 标题去掉"v2 系列收官版"措辞——`--doctor` 证明 evidence-driven 流程仍在产出，v2 系列未必终结于 v2.4
- README 「环境要求」节明确：v2.5 起 macOS 只需 `brew install coreutils` 即可（脚本会自动选 `gtimeout`），不再需要改脚本

### Known limits

- v2.5 仍是补丁版；结构性升级（SKILL.md 模块化、tests/fixtures 自动回归、入口粒度拆分）留给 v3.0
- Doctor 模式为 spec-only：检查逻辑由 consumer Claude 按 spec 解释执行，无独立 CI runner

---

## v2.4 — v2 系列阶段性收尾

四大 backlog 一次性解决：多语言混合栈、第三方 hook 共存、跨版本迁移、Skill 形式专属。

### Added

- **`--update` 参数 + Phase 0.5 Migration**：跨版本状态文件升级，自动备份 + 字段映射表 + 决策继承
- **`--isolate-branch` 参数**：在专用 git 分支跑写入阶段，整体回滚只需切回原分支
- **多语言栈一等公民**：`stack` → `stacks[]`，每栈独立 paths/工具/size；命令命名空间化（`lint:ts` / `lint:py` / `lint` 聚合）
- **Phase 7 § 发布路径决策表**：Skill 形式直接引用 `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks/`，不复制脚本
- **Phase 7 § 第三方 hook 共存约束**（5 条规则）：独立 matcher 块合并策略；onboard hook 必须满足 deny 优先、故障静默、只读 stdin、日志隔离、幂等且交换
- **多栈配置文件** `.claude/onboarding-logs/stacks.json`：hook 脚本通过 `ONBOARD_STACKS_FILE` env 读取，按扩展名分发到对应栈的命令
- **CI 命令按 job 分类**：提取后映射到对应 stack，便于 Phase 4 按栈对齐
- **CLAUDE.md 多栈变体模板**：`## Stacks` 节 + 每栈子节
- **阶段卡片 `elapsed` 字段** + Phase 0 输出预估总耗时（按规模分级）

### Changed

- **Iron Law 3 精化**："禁止跨栈混搭"改为"同一语言栈内禁止冲突工具，允许多语言项目并存"
- **Iron Law 14 拆分**：禁止 file-level reset，但允许 `git checkout -b` 创建新分支
- **元规则收敛**：删除与 Iron Laws 16-19 重复的条目；现 12 条元规则全是 Iron Law 不直接涵盖的执行指引
- **包管理器冲突检测加栈归属**：不同目录的 lockfile 不算冲突；只有同栈内冲突才记 conflicting
- **总行数从 1311 → 1248**：v2.4 是 v2 系列**第一个减行的版本**，spec 开始成熟

### Fixed

- v2.3 的 `--resume` 与"修订模式"语义不清问题
- 多语言项目里 `ONBOARD_LINT_CMD` 单变量塞不下多栈的结构性失配
- `.git/hooks/*` 误入 `touches` 字段导致概念混乱（v2.3 已部分修，v2.4 完成）
- 状态文件跨版本迁移无规则导致老项目无法升级

---

## v2.3 — Execution-semantics convergence

第三轮压测后产出。审核员指出 14 项工程实现细节问题，全部采纳。

### Added

- **`mutex_group` 字段**：plan item schema 加互斥组；Phase 2 授权阶段就拒绝冲突，不延后到 Phase 6/7
- **`local_side_effects` 字段** + **文件四分类**：`.git/hooks/*` 等不入仓的写入目标独立分类，不参与 touch_budget
- **Forbidden zone candidates vs confirmed**：Phase 1 探测一律标 candidate，Phase 1.5 用户确认升级为 confirmed
- **Phase 1.5 DSL 严格枚举**：每个 decision item 必须输出 `allowed_values`，value 不匹配一律拒绝
- **Phase 3 CLAUDE.md `## Change Policy` 章节**：Safe-to-edit / Ask-before-edit / Read-only 三级
- **Phase 3 / Phase 5 测试级别**：`none / smoke / unit / integration / e2e` 分级
- **Iron Law 18**：Mutex group authorization
- **Iron Law 19**：warn-only must exit 0
- **Phase 6 自动修复后 re-stage 规则**：lint-staged 自动 / 裸脚本必须显式 `git add` / 无法可靠 re-stage 时只能 check
- **Stop hook light/standard/strict 三模式**：按 `stack.size` 默认推荐
- **guard-edit 多路径 + 路径边界标准化**：jq 提取 file_path / files[] / edits[]；前缀匹配改边界精确匹配

### Changed

- 文件三分类术语精化为"PROJECT 默认不得修改；授权后可改"
- Phase 6 重命名为 "Commit & CI Gates"，CI 配置修改归入
- `proceed safe` 严格定义为 `installs == [] && risk == low`
- Phase 8 入口动态化：`git ls-files .claude/` 动态填入最终报告

---

## v2.2 — 模拟跑出来的 13 项补丁

第一次以使用者身份模拟跑一遍完整流程，标号记录 13 个问题。

### Added

- **Phase 1.5 · Blocking Decisions**（独立阶段）：lockfile 冲突、CI 重新对齐、stale Makefile target 等用户必决项专门通道
- **Iron Law 16**：Forbidden zones 全局一致（CLAUDE.md / lint ignore / hook env / guard-edit 同步）
- **Iron Law 17**：新增检查首次失败标 deferred，不阻塞 onboarding
- **任务运行器健康检查**（Phase 4 前置）
- **CI 命令提取协议明文化**（按 yaml 字段提取）
- **Phase 6 重命名为 Commit & CI Gates**，包含 CI 配置修改
- **guard-edit.sh 新增**：PreToolUse on Edit|Write|MultiEdit 拦截禁区编辑
- **Stop hook 增量模式**：依赖 `post-edit-check.sh` 维护的 touched-files.txt
- **`.git/info/exclude` 本地 ignore 过渡**：Phase 0 创建 RUNTIME 目录时同步写入

### Fixed

- Phase 0 创建 RUNTIME 目录后 git status 显示噪音问题
- Phase 4 验证逻辑对"新增检查"的结构性盲点（typecheck 首次跑必红）
- `lockfile 变更`没在 `touches` 里导致 Iron Law 13 误触发
- 禁区拦截位置从 PostToolUse 改到 PreToolUse（无法回滚 → 编辑前 deny）
- Phase 6 验证假设不成立时的 fallback（`verification_skipped`）

---

## v2.1 — 第二轮审核 15 条全采

收紧 frontmatter 权限、明确 hook 决策输出规范、修复一批安全风险。

### Added

- **frontmatter `disable-model-invocation: true`**：防止 Claude 自动触发副作用流程
- **frontmatter `allowed-tools: Read, Glob, Grep`**：只读权限，写操作走正文授权
- **Iron Law 13**：Touch budget
- **Iron Law 14**：No reset / checkout on PROJECT
- **Iron Law 15**：Exit code or JSON, never both
- **Phase 6 验证用 `.claude/tmp/` 临时文件**：禁止对 PROJECT 文件做 reset/checkout
- **Phase 4 验证改为 exit code + log 摘要**：不再依赖跨工具解析 error 类型集合
- **测试豁免条件**：library/CLI/SDK/infra/config-only 项目不强制写冒烟测试

### Changed

- Hook 决策输出推荐 `exit 0 + JSON`（permissionDecision: deny），exit 2 作为兼容回退
- `proceed safe` 边界明确
- Phase 0 工具检查分级（git 始终 blocking，jq 仅 Phase 7 blocking）

---

## v2 — 初版正式 spec

第一份完整的"治理协议"形式 spec，6 化（通用/标准/规范/自动/智能/科学）落地。

### Added

- Iron Laws 1-12 + 元规则
- Phase 0-8 完整流程
- 文件三分类：PROJECT / RUNTIME / OUTPUT
- 阶段卡片输出契约
- Plan item schema（touches / installs / reversible / risk）
- 授权 DSL（`proceed safe` / `approve install` / `approve risk` / `skip` / `abort`）

---

## v1 — 初版

把"旧项目接入 Claude Code"流程沉淀为 slash command 的第一次尝试。基础结构成立但有大量工程化细节缺失。

---

## Versioning Philosophy

每次迭代都遵循 evidence-driven refinement：

1. 模拟或真实跑一遍现版本
2. 标号记录所有问题（P-A、P-B、...）
3. 按 Critical / High / Medium / Low 分级
4. 全部采纳或拒绝（说理由）
5. 写入下一版本

不做无 evidence 的"前瞻性设计"。
