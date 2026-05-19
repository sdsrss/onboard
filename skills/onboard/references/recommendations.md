# Claude Code plugin recommendation matrix (v2.7+；v3.2 抽到 sub-file)

> 本文件是 SKILL.md `## Claude Code plugin recommendation matrix` 章节的完整 spec（v3.2 起从 SKILL.md 拆出）。
> Phase 2.5 类 4 `Claude Code plugins` 安装协议消费本文件 trigger 矩阵；consumer Claude 进入 Phase 2.5 前必须 Read 本文件（元规则 27）。
> 引用本文件 Iron Law / 元规则编号 → 见 SKILL.md 顶部 §0 总则与底部「元规则」段。

---

## 设计原则

Phase 2.5 按项目信号匹配此矩阵；矩阵未覆盖的项目特征 → 走"open recommendation" 通道（consumer Claude 自由推荐，用户确认后写入 state，未来可促请 spec 维护者收编进矩阵）。

**绝不自动安装** — Iron Law 7 + 元规则 19：所有 plugin 推荐只输出 `/plugin install <id>` 命令字符串，等用户自己跑。

## 硬编码矩阵

| Plugin | Trigger 条件 | 推荐理由 |
|---|---|---|
| `claudemd` | always | 统一 CLAUDE.md 治理、规范节归属、banned vocab |
| `claude-mem-lite` | always | 跨会话记忆 + 经验沉淀 |
| `code-graph-mcp` | `stack_overall_size ∈ {medium, large}` OR `len(stacks) >= 2` | 大型 / 多语言代码库的引用关系、影响面分析 |
| `serena` | `len(stacks) >= 2` OR 单栈文件数 > 3000 | 跨语言语义搜索 |
| `frontend-design` | 任一 stack frameworks 含 `react / vue / svelte / nuxt / next` | UI 质量、避免 AI 套路化 |
| `design-review` | 上一条命中 + 检出 `dev` script + 可访问的 web 入口 | 实时视觉 QA |
| `qa` / `qa-only` | 检出 dev server config（vite/next/webpack devServer/uvicorn reload 等） | 系统化 QA 流程 |
| `setup-deploy` | `.github/workflows/*.yml` 含 deploy job OR `.gitlab-ci.yml` 含 deploy stage | 标准化部署流 |
| `cso` | 存在 `Dockerfile` / `*.k8s.yml` / `kustomization.yaml` / `terraform/` | 基础设施类项目安全审查 |
| `document-release` | 存在 `CHANGELOG.md` AND `git tag` 数量 ≥ 3 | 发版后文档同步 |
| `mcp-builder` | 检出 `fastmcp` / `@modelcontextprotocol/sdk` 引用 | MCP server 开发支持 |
| `seo-technical` / `seo-content` | 检出 docs 站点配置（`mkdocs.yml` / `docusaurus.config.js` / `astro.config.*` blog） | SEO + 内容质量 |
| `claude-api` | 检出 `anthropic` SDK 引用（`anthropic` Python / `@anthropic-ai/sdk` TS） | Claude API 应用专项 |
| `webapp-testing` | 上述 qa 触发但项目无 e2e 测试 | Playwright 工具箱接入 |
| `make-pdf` | 检出 `docs/` 含 markdown 报告 | 文档转 PDF |

## Open recommendation 协议

当 consumer Claude 觉得某 plugin 适合此项目但**不在矩阵中**：

1. 写入 state file `phase_2_5.plugin_recommendations.from_open[]`，结构：
   ```json
   { "name": "<plugin-id>", "reason": "<one line>", "trigger_signal": "<观察到的项目特征>" }
   ```
2. 在 Phase 2.5 卡片"Open recommendations"小节列出，标 `[open]`
3. 用户 `approve plugin <id>` 同样的 DSL 处理
4. 矩阵升级建议：每次 `--update` 时，若同一 open recommendation 在 ≥ 3 个项目中出现 → Phase 0 输出"建议给 spec 维护者反馈：把 X 加入硬编码矩阵"

## 用户确认协议

Plugin 推荐**绝不自动安装**，按 v2.7 设计逐项让用户选：

```
Suggested Claude Code plugins (review each):
  [Y/n] claudemd              统一 CLAUDE.md 治理               (always-on)
  [Y/n] claude-mem-lite       跨会话记忆                        (always-on)
  [Y/n] code-graph-mcp        2 栈 + medium size                (matrix:size)
  [Y/n] frontend-design       react detected                    (matrix:stack)
  [open] flask-explorer       推断自 apps/api flask 路由        (open-rec)
```

Phase 2.5 类 4 默认显示 Top 3 matrix + open 全列（v3.1+ Top-N 折叠）；`--verbose-plan` 展示全部矩阵项（参见 SKILL.md `--verbose-plan` flag）。授权 DSL：`approve plugin <id>` 单批 / `approve plugin-all-matrix` 接受全部矩阵 / `[open]` 项分开确认。
