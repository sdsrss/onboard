# Changelog

按 [Keep a Changelog](https://keepachangelog.com/) 风格记录。整个 v2 系列经过 4 轮 simulation-based stress testing 演进，每轮都基于真实压测 evidence 而非理论设计。

---

## v2.10.2 — v2.10.1 后全仓审计（current）

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
