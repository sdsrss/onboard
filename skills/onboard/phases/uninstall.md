# Uninstall Mode（v2.8 新增；v2.11 三层模型 + 双模式重写）

> 本文件是 SKILL.md `## Uninstall Mode` 章节的完整 spec（v3.0 起从 SKILL.md 拆出）。
> SKILL.md 原位置保留 sentinel + summary；进入 uninstall 流前 consumer Claude 必须 Read 本文件。
> 引用本文件 Iron Law 20/21/22 + 元规则 26 → 见 SKILL.md 顶部 §0 总则与底部「元规则」段。

---

## Uninstall Mode（v2.8 新增；v2.11 三层模型 + 双模式重写）

**触发**：`/onboard --uninstall[=skill|all]`。**不跑任何 Phase**，按 manifest + marker 反向移除 onboard 写入。

**前置**：当前目录是 git 仓库 + 存在 onboard manifest（`.claude/local-only/onboard-manifest.json` 或 `.claude/onboard-manifest.json`）。无 manifest 时拒绝自动卸载（fallback 到手动指引）。

### 三层状态模型（v2.11 新增）

onboard 的"状态"分布在三层，卸载语义按层精确切分：

| 层 | 状态位置 | `=skill` 清 | `=all` 清 |
|---|---|---|---|
| **L1 user-global** | `~/.claude/skills/onboard/`、`~/.claude/plugins/cache/onboard@<ver>/`（plugin 安装时）、`~/.claude/onboard-runtime/hooks/`（mirror dir） | ✓ | ✓ |
| **L2 project-config** | `.claude/settings.local.json`（或 `settings.json`）中的 hook 条目 + env keys、CLAUDE.local.md / CLAUDE.md 中的 marker 块、`.git/info/exclude` / `.gitignore` 中的 marker 块 | ✗（保留） | ✓ |
| **L3 project-files** | hook 脚本本体（share 模式：`.claude/skills/onboard/hooks/*.sh`；local-only 模式：原本指向 L1，`=skill` 时被本地化到 `.claude/onboard-keeper/hooks/`）、`.claude/local-only/onboarding-state.json`、`stacks.json`、snapshots 目录 | ✗（保留，必要时本地化） | ✓ |

**直观区分**：`=skill` "禁用 `/onboard` 命令但不影响已 onboarded 项目运转"；`=all` "彻底卸 + 项目还原到 pre-onboard"。

### 模式 1：`--uninstall=skill` 流程

**目标**：移除 L1 user-global，保留 L2 + L3。**前置不变量**：执行后所有已 onboarded 项目的 hook 路径仍指向有效文件。

```
─── /onboard --uninstall=skill ───
status: in-progress
mode:   skill (L1 only; L2 + L3 preserved)
```

1. **检测 install source**（从 manifest 或 `.claude/settings*.json` hook command 路径反推）：
   - `user-skill`（`install.sh install`） → L1 在 `~/.claude/skills/onboard/`
   - `plugin`（`/plugin install onboard`） → L1 在 `~/.claude/plugins/cache/onboard@<ver>/` + mirror
   - `project-skill`（共享 skill clone 到项目内） → L1 = L3，`=skill` 在此场景 no-op-on-L1（仅清 mirror dir）
2. **本地化 hooks**（**仅 local-only 模式 + L1 即将消失时执行**，per 元规则 26）。**步骤顺序固定**（v2.11.1 收紧：snapshot 必须在任何写动作之前；记录已完成步骤索引以便精确回滚）：

   **步骤 2.0 snapshot**（先于一切写动作，per 元规则 21）：
   ```bash
   SNAP=".claude/local-only/onboard-snapshots/settings.local.json.$(date -u +%Y%m%dT%H%M%SZ).uninstall-skill.pre"
   cp .claude/settings.local.json "$SNAP"   # 不存在 → abort，没什么可保的
   ```

   **步骤 2.1 keeper 目录与 hook 副本**：
   ```bash
   KEEPER="$CLAUDE_PROJECT_DIR/.claude/onboard-keeper/hooks"
   SKILL_SRC="$HOME/.claude/skills/onboard"   # 或 ${CLAUDE_PLUGIN_ROOT}/skills/onboard

   mkdir -p "$KEEPER" "$KEEPER/../scripts"
   cp -a "$SKILL_SRC/hooks/." "$KEEPER/"
   cp -a "$SKILL_SRC/scripts/mirror-hooks.sh" "$KEEPER/../scripts/" 2>/dev/null || true
   chmod +x "$KEEPER"/*.sh "$KEEPER/../scripts/"*.sh 2>/dev/null || true
   ```

   **步骤 2.2 atomic jq 重写**（tmp + mv，per Iron Law 14）：
   ```bash
   jq '(.hooks[][]?.hooks[]?.command) |= sub("\\$\\{HOME\\}/\\.claude/skills/onboard/"; "${CLAUDE_PROJECT_DIR}/.claude/onboard-keeper/")' \
     .claude/settings.local.json > .claude/settings.local.json.tmp \
     && mv .claude/settings.local.json.tmp .claude/settings.local.json
   ```

   **步骤 2.3 `.git/info/exclude`**（marker 块内）：追加 `.claude/onboard-keeper/`

   **步骤 2.4 onboard-manifest.json 更新**：追加 `keeper_dir: ".claude/onboard-keeper/"` + `mode_after_skill_uninstall: "keeper-localized"`

   **精确回滚矩阵**（per 元规则 22 重入 + 元规则 26 原子回滚 — 按已完成的最高步骤号 N 逆序撤销 N..0）：

   | 失败发生在 | 已完成 | 回滚动作（按序） |
   |---|---|---|
   | 2.0 | 无 | abort，没有副作用 |
   | 2.1 | snap | abort（settings 未改；snap 留着备查） |
   | 2.2 (mv 前) | snap, keeper | `rm -rf .claude/settings.local.json.tmp .claude/onboard-keeper/`；abort |
   | 2.2 (mv 中/后但后续失败) | snap, keeper, settings 已 mv | `cp "$SNAP" .claude/settings.local.json`；`rm -rf .claude/onboard-keeper/`；abort |
   | 2.3 | snap, keeper, settings | 同上 + 撤销已写入的 exclude 行 |
   | 2.4 | snap, keeper, settings, exclude | 同上 + 撤销 manifest 追加 |

   绝不允许 settings.local.json 处于已重写状态但 keeper 不存在的悬空态——这就是 元规则 26 禁止的"broken hook path"残留。
3. **干跑预览 + 单次 hard AUTH**：
   ```
   Skill-uninstall plan:
     [L1] Remove: ~/.claude/skills/onboard/                       (or via /plugin uninstall onboard)
     [L1] Remove: ~/.claude/onboard-runtime/hooks/                (plugin mode mirror, if present)
     [L1] Remove: ~/.claude/.cache/onboard-source/                (install.sh stage cache)
     [L3] Localized: .claude/onboard-keeper/hooks/{4 hooks,scripts/mirror-hooks.sh}  ← 上一步已就位
     [L2] Preserved: .claude/settings.local.json (paths rewritten to onboard-keeper)
     [L2] Preserved: CLAUDE.local.md (managed block intact)
     [L2] Preserved: .git/info/exclude (marker block intact + keeper line appended)

   /onboard slash command will become unavailable after this step.
   Hooks continue to run from .claude/onboard-keeper/.
   Proceed? [Y/n]
   ```
4. **执行 L1 移除**（非交互调用 install.sh，per 元规则 25 + 元规则 22 hard-AUTH-per-mode 已在 step 3 一次拿下）：
   - **`install.sh install` 来源**：`ONBOARD_CONFIRM_UNINSTALL=yes ONBOARD_UNINSTALL_MODE=skill bash "$SKILL_DIR/install.sh" uninstall`
   - **`/plugin install` 来源**：consumer Claude 不能驱动 `/plugin uninstall`（slash 命令归用户）；stdout 打印：
     ```
     L1 cleanup (run manually in your Claude Code session):
       /plugin uninstall onboard

     The mirror dir at ~/.claude/onboard-runtime/hooks/ has been cleared.
     ```
     + 写 state file `phase_uninstall.plugin_cleanup_pending: true`，下次 `--doctor` 提示用户跑
   - **`project-skill` 来源**：L1 = L3，跳过 L1 移除步骤
5. **最终输出**：
   ```
   status: done
   mode:   skill
   actions:
     - L1 removed:   ~/.claude/skills/onboard/  (+ mirror, + stage cache)
     - L3 localized: .claude/onboard-keeper/ (4 hooks + mirror-hooks.sh, +x)
     - L2 rewritten: .claude/settings.local.json (4 command paths → keeper)
   next: hooks continue firing from keeper; CLAUDE.local.md and forbidden zones unchanged.
         To fully remove later:  /onboard --uninstall=all
   ```

### 模式 2：`--uninstall=all` 流程（v2.8 行为 + L1 整合）

**目标**：清三层。等同于"`=skill` + project-side manifest-driven removal"。

1. **读取 manifest**：确定 mode 与 managed files / blocks / settings paths
2. **干跑预览**（强制 hard AUTH；每类删除单独 AUTH，**不**用 batch AUTH，per 元规则 22）：
   ```
   Uninstall plan (mode=all):
     [L1] Remove file:    ~/.claude/skills/onboard/  (or /plugin uninstall onboard)
     [L1] Remove file:    ~/.claude/onboard-runtime/hooks/  (if present)
     [L1] Remove file:    ~/.claude/.cache/onboard-source/
     [L2] Edit file:      .claude/settings.local.json (4 hook entries + 4 env keys)
     [L2] Edit file:      CLAUDE.local.md (managed block; non-onboard content preserved)
     [L2] Edit file:      .git/info/exclude (remove block between markers, 7 lines)
     [L3] Remove file:    .claude/local-only/onboarding-state.json (12 KB)
     [L3] Remove file:    .claude/local-only/onboarding-logs/ (5 files, 84 KB)
     [L3] Remove file:    .claude/local-only/onboard-snapshots/ (12 files, 256 KB)
     [L3] Remove file:    .claude/local-only/stacks.json
     [L3] Remove file:    .claude/onboard-keeper/  (if previously created by =skill)

   Snapshots available for restore (oldest first):
     - CLAUDE.local.md.20260514T160000Z.phase3.pre  → pre-onboard state (recommended)
     - settings.local.json.20260514T163000Z.phase7.pre

   Proceed? [Y/n/restore-snapshot]
   ```
3. **用户确认后执行**（**重要**：本 step 2 干跑预览的 hard AUTH 已覆盖整套 `=all` 的所有删除类——L1 + L2 + L3——不在子步骤里重新弹 AUTH，否则违反 元规则 25 单次审批契约 + UX 暴击；元规则 22 "每类删除单独 hard AUTH" 在 `=all` 里以"在 step 2 预览里逐类列出 + 用户一次性 Y"的形式满足）：
   - L1 清理：跑 `=skill` 流程的 step 4 命令清单（user-skill / plugin / project-skill 三种来源的对应动作），但**跳过** `=skill` step 2 keeper 本地化——`=all` 下 L3 也要删，本地化无意义；AUTH 不重弹
   - L2 清理：逐 file 编辑 marker 块；JSON 用 jq 过滤 `_onboard_managed: true` + 删除 `_onboard_managed_env_keys` 列出的 env key；删除空 hook 数组 / 空 env 对象（若 onboard 是 settings 唯一来源）；保留 settings 文件本身
   - L3 清理：rm `.claude/local-only/`、rm `.claude/onboard-keeper/`（若存在）
4. **restore-snapshot 流程**（用户选 restore 而非 remove）：
   - 列出每个 managed file 的最早 pre-modify snapshot
   - 用 `cp <snapshot> <original>` 恢复
   - 删除 onboard 在该文件之外的写入（如 `.git/info/exclude` 块）
   - L1 仍然移除（snapshot 不涵盖 L1）
5. **最终清理**：删除 manifest 自身、state file、snapshots 目录（用户也可保留备查）
6. **不动**：
   - 用户在 marker 块外的内容
   - 用户在 `.claude/settings.local.json` 中自己加的、不带 `_onboard_managed` 标记的 hook 项
   - 项目内已 commit 的内容（share 模式：用户应自行 `git revert` 之前 commit 的 onboard PR）

### 默认值约定（v2.11）

- 裸 `--uninstall`（无 `=value`） ≡ `--uninstall=all`（向后兼容 v2.8+ 用户）
- consumer Claude 在 Phase 0 解析参数时按此映射

### Iron Law 边界

- **Iron Law 14（No file-level reset on PROJECT）**：卸载使用 atomic write（写到临时文件 + rename）而非 `git checkout` / `git restore`
- **Iron Law 16（Forbidden zones global）**：`=all` 卸载完毕后 `confirmed_forbidden_zones` 在所有派生位置必须同步消失（manifest / settings env / lint ignore（share 模式）/ hook env）。`=skill` 保留 zones，因为项目仍处于 onboarded 状态
- **Iron Law 2（No silent overwrite）**：删除 / 编辑前一律展示 diff，**绝不**静默移除

### 卸载后状态

成功 `=all` 卸载后 `git status` 应只显示：
- `--local-only` 模式：0 项变更（local-only 本来就没动 PROJECT）
- `--share` 模式：列出 onboard 之前 commit 过的入仓文件（提示用户用 `git revert <commit>` 撤回 commit 历史，或保留作为审计痕迹）

成功 `=skill` 卸载后：
- L2 + L3 完全保留；项目继续按 onboarded 状态运转
- `/onboard` slash 命令不可用（直到下次 `install.sh install` 或 `/plugin install onboard`）
- `.claude/onboard-keeper/` 是 LOCAL-SIDE-EFFECT（在 `.git/info/exclude`），不入仓

### 错误处理

- Manifest 找不到 → 拒绝自动卸载，输出手动清理 checklist：
  ```
  Manual cleanup (no manifest found — earlier version or corruption):
    1. rm -rf .claude/local-only/  (or .claude/onboarding-*)
    2. Edit .git/info/exclude: remove lines between '# >>> /onboard' and '# <<< /onboard'
    3. Edit .gitignore (share mode only): same marker pair
    4. Edit .claude/settings.local.json: remove entries with "_onboard_managed": true
    5. Edit CLAUDE.local.md: remove content between <!-- >>> /onboard --> markers
       (or delete the file if onboard was the only writer)
    6. (v2.11) rm -rf .claude/onboard-keeper/  (only if a previous =skill localized hooks here)
  ```
- Snapshot 损坏 / 缺失 → 跳过 restore 选项，仅提供 remove
- 任一删除失败 → 中止剩余步骤，输出已完成 / 未完成清单（卸载本身要可重入）
- `=skill` 模式 hook 本地化任一步失败 → 整个 `=skill` 流程回滚（不允许残留 broken hook 路径，per 元规则 26）

### 与 install.sh uninstall 的分工（v2.11 修订）

| 作用域 | 命令 | 清理什么 |
|---|---|---|
| L1（user-global）| `install.sh uninstall` 或 SKILL.md 在 `=skill` 流程中非交互调用它 | `~/.claude/skills/onboard/` + stage cache + mirror dir |
| L1（plugin 安装）| `/plugin uninstall onboard`（用户手动；consumer Claude 仅打印命令） | plugin cache + mirror dir |
| L2 + L3（项目侧）| `/onboard --uninstall=all` | 本节 §模式 2 定义的所有内容 |
| 仅 L1（保留项目）| `/onboard --uninstall=skill` | 本节 §模式 1 定义的内容 + 必要时 hook 本地化 |
| 项目级 skill 副本（share 模式） | `git rm -r .claude/skills/onboard && commit` | 用户手动 |

**v2.11 新建议顺序**：
- 想暂停 `/onboard` 但保留项目配置 → `/onboard --uninstall=skill`
- 想彻底卸载 → 直接 `/onboard --uninstall=all`（含 L1 + L2 + L3 清理）
- 旧 v2.8-v2.10 用户：`/onboard --uninstall`（裸） ≡ `=all`，行为不变

---

