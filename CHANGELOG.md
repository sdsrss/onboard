# Changelog

按 [Keep a Changelog](https://keepachangelog.com/) 风格记录。整个 v2 系列经过 4 轮 simulation-based stress testing 演进，每轮都基于真实压测 evidence 而非理论设计。

---

## v2.4 — v2 系列收官版（current）

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
