# 状态文件结构 (v2.9+ schema)

> 本文件是 SKILL.md `## 状态文件结构` 章节的完整 spec（v3.0 起从 SKILL.md 拆出）。
> Runtime 校验工具：`scripts/validate-state.sh` (v2.12.0+)；Doctor mode D1 也将引用本文件 schema。
> 引用本文件 Iron Law / 元规则编号 → 见 SKILL.md 顶部 §0 总则与底部「元规则」段。

---

## 状态文件结构（v2.9 schema）

**路径**：
- `--local-only` 模式（默认）：`.claude/local-only/onboarding-state.json`
- `--share` 模式：`.claude/onboarding-state.json`

```json
{
  "version": "2.9",
  "migrated_from": "1 | 2.0 | 2.1 | 2.2 | 2.3 | 2.4 | 2.5 | 2.6 | 2.7 | 2.8 | null",
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
    "allow_large_claude_md": false,
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
    "1_7": {
      "status": "done",
      "extracted": {
        "A1_build_test": [],
        "A2_test_subset": [],
        "A3_module_dep": [],
        "A4_generated_dirs": [],
        "A5_naming_anomaly": "none | <observation>",
        "A6_behavioral_donts": [],
        "A7_coverage": { "threshold": null, "enforcement": "ci|pre-commit|none" },
        "A8_forbidden_v2": []
      },
      "claude_md_token_estimate": 0
    },
    "2":   { "status": "done", "plan": [], "approved_items": [], "approved_installs": [], "approved_risks": [], "skipped": [], "mutex_resolutions": {} },
    "2_5": {
      "status": "done",
      "dev_tools": { "needed": [], "approved": [], "installed": [], "skipped": [] },
      "system_clis": { "missing": [], "commands_offered_per_os": {}, "user_confirmed_installed": [] },
      "language_runtimes": { "required": [], "tool_versions_written": false },
      "plugin_recommendations": {
        "from_matrix": [],
        "from_open": [],
        "approved": [],
        "skipped": [],
        "install_commands_offered": []
      }
    },
    "3":   { "status": "done", "outputs": ["CLAUDE.md | CLAUDE.local.md"], "change_policy_set": true, "testing_level": "unit + integration", "stacks_section_format": "single | multi", "claudemd_coexistence": {}, "claude_md_tokens": 0, "token_budget_override": false, "auto_compressions_applied": [] },
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
  },
  "onboard_manifest_path": ".claude/local-only/onboard-manifest.json | .claude/onboard-manifest.json",
  "snapshots": {
    "dir": ".claude/local-only/onboard-snapshots/ | .claude/onboard-snapshots/",
    "index_path": "<dir>/index.jsonl",
    "count_pre_modify": 0,
    "count_post_install": 0,
    "count_post_update": 0,
    "retention_per_file": 5
  }
}
```

---

