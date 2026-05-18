# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo is **not** an application — it is the `/onboard` **Claude Code Skill** itself (current version: v3.0.0-rc.1). The "code" being maintained is:

- `skills/onboard/SKILL.md` (v2.10 moved here from repo root) — the workflow spec defining a 10-phase onboarding protocol (Phase 0 / 0.5 / 1 / 1.5 / 1.7 / 2 / 2.5 / 3-8), Doctor Mode (`--doctor`, v2.5+; D1-D15 checks), Mode model (`--local-only` default vs `--share`, v2.6+), Install Plan / Plugin recommendation matrix (v2.7+), Uninstall Mode + marker/snapshot protocols (v2.8+), and Plugin marketplace install-source detection (v2.9+). **v3.0 起 Phase 7 / Uninstall Mode / 状态文件结构 三段抽到 sub-file** (`skills/onboard/phases/phase-7.md` / `skills/onboard/phases/uninstall.md` / `skills/onboard/references/state-schema.md`)；SKILL.md 原位置保留 sentinel header + 4-8 bullet summary + `Read sub-file.md` 指令；consumer Claude 进入对应 phase 前必须 Read sub-file（元规则 27）。This file's frontmatter (`name: onboard`, `disable-model-invocation: true`, `allowed-tools: Read, Glob, Grep`) registers it as a Skill — at `skills/<name>/` for plugin discovery, or under standalone `.claude/skills/onboard/` after install.sh.
- `skills/onboard/hooks/*.sh` (v2.10 moved) — 4 hook scripts; git index mode `100755` (executable).
- `skills/onboard/settings.template.json` + `skills/onboard/settings.local.template.json` (v2.10 moved) — reference configs for `--share` / `--local-only` modes; co-located with SKILL.md.
- `install.sh` (v2.8, v2.10 redesigned) — universal installer (install/update/uninstall/doctor); uses staging cache at `~/.claude/.cache/onboard-source/` for fast updates; copies `skills/onboard/*` into install target.
- `.claude-plugin/plugin.json` (v2.8, v2.9 schema-corrected) — Claude Code plugin manifest, canonical schema only.
- `.claude-plugin/marketplace.json` (v2.9) — Claude Code plugin marketplace catalog at repo root; required for `/plugin marketplace add sdsrss/onboard` to find the plugin.
- `tests/run.sh` + `tests/integration/*.sh` — in-repo sandbox tests for plugin install / hook execution / installer round-trip / SKILL.md link consistency / hook runtime behavior / v2.11 uninstall modes / v2.12 state-schema validation (214 assertions across 10 integration tests: `plugin-install.sh` 24 + `hook-mirror.sh` 33 + `install-roundtrip.sh` 34 + `skillmd-links.sh` 21 + `hook-behavior.sh` 49 + `cc-plugin-detection.sh` 8 + `prepare-script-detection.sh` 2 + `sync-versions-detection.sh` 1 + `uninstall-modes.sh` 21 + `state-schema.sh` 21); run via `bash tests/run.sh`. v2.11.1 adds `scripts/verify-counts.sh` to auto-check the headline+per-test claims here / in CHANGELOG against actual `pass:` counts — drift triggers non-zero exit. v2.11.2 adds `scripts/release-preflight.sh` which bundles `verify-counts.sh` + version-bump completeness + `git update-index --chmod=+x` on new `.sh` + staged-file sanity into a single pre-commit check. v2.11.3 adds `.env` boundary-anchored deny in `guard-bash.sh` (H1; 12 new hook-behavior assertions) + `mirror-hooks.sh` cmp -s fast path (L1; 4 new hook-mirror assertions) + inline `_keeper_command_after_skill_uninstall` doc fields in `settings.local.template.json` (M5) + `install.sh` Iron Law 14 stage-cache exemption comment (M4) + README "never auto-installs" 设计承诺 section. v2.12.0 adds `ONBOARD_FORBIDDEN_COMMANDS` newline-separated regex env in `guard-bash.sh` (H2; 11 new hook-behavior assertions) + per-stack `lint_timeout_sec` / `typecheck_timeout_sec` / `format_timeout_sec` / `format_check_timeout_sec` in stacks.json (H3; 4 new hook-behavior assertions) + `scripts/validate-state.sh` runtime state-schema validator + `state-schema.sh` integration test (C2; 21 new assertions). Persisted post-v2.10 from the prior `/tmp/onboard-plugin-test.sh`; `hook-behavior.sh` added in v2.10.2; `cc-plugin-detection.sh` / `prepare-script-detection.sh` / `sync-versions-detection.sh` / `uninstall-modes.sh` added in v2.11.0 for the 8 P-A items; `state-schema.sh` added in v2.12.0 for C2.
- `README.md` — install + usage guide for end users.
- `CHANGELOG.md` — version history.

Consumers install this package into their project at `.claude/skills/onboard/`, then `/onboard` becomes available as a slash command in their Claude Code session.

## Architecture you must know

**SKILL.md is law.** When asked to change behavior of the `/onboard` flow, edit SKILL.md — do not write code elsewhere expecting it to take effect. SKILL.md is consumed by *another* Claude instance reading the file at slash-command invocation; behavior lives in the prose, not in any runtime.

**Two artifact layers, never confuse them:**
1. *This repo* (the skill package) — what you edit here.
2. *The installer project's `.claude/`* — where the skill lands after `cp -r onboard/ .claude/skills/`. Paths like `.claude/onboarding-state.json`, `.claude/onboarding-logs/`, `${CLAUDE_PROJECT_DIR}/...` all refer to *that* layer, not this repo's working tree.

**Hook scripts in `hooks/` are referenced, not copied** (v2.4 Skill-form change). The installer project's `settings.json` points at `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks/<name>.sh` directly. Phase 7 in SKILL.md does NOT generate scripts in Skill mode. (Command-mode fallback still dynamic-generates — see `skills/onboard/phases/phase-7.md` "发布路径决策" §, v3.0+.)

**The 4-hook contract** (the protocol exposed to Claude Code's hook system):

| Hook | Event/Matcher | Purpose |
|------|---|---|
| `guard-bash.sh` | PreToolUse / `Bash` | Deny dangerous shell patterns (`rm -rf /`, force-push to main, `curl \| sh`, …) |
| `guard-edit.sh` | PreToolUse / `Edit\|Write\|MultiEdit` | Deny edits inside confirmed forbidden zones (`$ONBOARD_FORBIDDEN_PATHS`) |
| `post-edit-check.sh` | PostToolUse / `Edit\|Write\|MultiEdit` | Append edited file to touched-files log; multi-stack format-check dispatch |
| `stop-verify.sh` | Stop | Run lint/typecheck on touched files per `$ONBOARD_STOP_MODE` (`light` / `standard` / `strict`); emit `{decision: "block"}` JSON if any check fails |

All four read `ONBOARD_STACKS_FILE` (a JSON list at `.claude/onboarding-logs/stacks.json` for share mode or `.claude/local-only/onboarding-logs/stacks.json` for local-only mode) for multi-language dispatch.

**Mode model (v2.6, default-flipping change)** — `/onboard` runs in one of two modes:
- `--local-only` (default): zero PROJECT changes. Knowledge → `CLAUDE.local.md`; settings → `.claude/settings.local.json`; state → `.claude/local-only/`. All paths injected into `.git/info/exclude`, **.gitignore untouched**. Hook references use user-global `~/.claude/skills/onboard/` path. Team pull sees zero onboard artifacts.
- `--share` (opt-in): the v2.5-and-earlier behavior. OUTPUT files committed; .gitignore revised; Phase 8 offers PR/MR via host adapter.

Default-flipping was deliberate: most companies have only a few AI-tool early adopters, so "default commit" forces AI tooling on uninvolved teammates. Default local-only = zero team-pollution risk.

**CLAUDE.md philosophy (v2.7, extraction-first)** — Phase 3 enforces a hard token budget. Soft cap warn at 2500 tokens (~10KB), hard refusal at 5000 tokens (~20KB) unless `--allow-large-claude-md` is given. Any section with no extracted content is omitted entirely (no placeholders). Line-format constraints are enforced on `## Run` / `## Layout` / `## Don't` / `## Watch out` — violations fail Phase 3.

**Install orchestration (v2.7)** — Phase 2.5 batches missing dev tools, system CLIs, language runtimes, and Claude Code plugins into four authorization lists. System CLIs and Claude Code plugins are NEVER auto-executed; only command strings are offered. Iron Law 7 holds: batch AUTH = explicit AUTH (granularity changes, semantics don't).

**Reversibility (v2.8, Iron-grade)** — every PROJECT write is bracketed by markers (line-based files: `# >>> /onboard v<ver> >>>`; markdown: `<!-- >>> -->`; JSON: `_onboard_managed: true`) and tracked in a manifest at `<state-dir>/onboard-manifest.json`. Phase 3/4/6/7/8 snapshot original PROJECT files to `<state-dir>/onboard-snapshots/` BEFORE first modification. `/onboard --uninstall` uses manifest + markers to surgically reverse; users can also choose `restore-snapshot` to recover the pre-onboard state.

**Plugin marketplace install (v2.9)** — repo supports `/plugin marketplace add sdsrss/onboard` via `.claude-plugin/marketplace.json` (catalog) + `.claude-plugin/plugin.json` (canonical schema only). Phase 7 detects install source (Plugin / User-skill / Project-skill / Command) and chooses the correct hook path variable (`${CLAUDE_PLUGIN_ROOT}` / `${HOME}/.claude/skills/onboard/` / `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/` / `${CLAUDE_PROJECT_DIR}/.claude/hooks/`). Critical: `${CLAUDE_PLUGIN_ROOT}` is ephemeral (changes with every plugin update), so onboard's default in plugin mode is to invoke `skills/onboard/scripts/mirror-hooks.sh` (v2.10.1 helper; idempotent; writes `.mirror-manifest.json` for diagnostics) to mirror hook scripts to a stable `~/.claude/onboard-runtime/hooks/` location and reference *that* in user settings — not `${CLAUDE_PLUGIN_ROOT}` directly. Plugin updates require `/onboard --update` (or re-running `mirror-hooks.sh` directly) to refresh the mirror.

## Iron Laws and meta-rules (non-negotiable when editing SKILL.md)

SKILL.md §0 defines **19 Iron Laws** and §"元规则" defines **23 meta-rules** (v2.6 added 13–16; v2.7 added 17–19; v2.8 added 20–22; v2.9 added 23). They are not advisory — they have load-bearing references throughout the spec. Editing rules to keep in mind:

- **Iron Law 15 (Exit code OR JSON, never both)** — every hook script must pick one output protocol. Mixing exit 2 with stdout JSON makes Claude Code ignore the JSON. Existing hooks always use `exit 0 + stdout JSON`.
- **Iron Law 19 (warn-only must exit 0)** — checks marked deferred (e.g. preexisting typecheck violations) MUST output warnings via stderr but never return non-zero, or they block `git push`.
- **Iron Law 16 (Forbidden zones global)** — `confirmed_forbidden_zones` flow through CLAUDE.md `## Forbidden`, lint ignore files, `ONBOARD_FORBIDDEN_PATHS` env, and `guard-edit.sh`. In local-only mode forbidden zones are enforced **only via hook env**, NOT injected into lint ignore files (avoids PROJECT modification).
- **File four-classification** (PROJECT / RUNTIME / OUTPUT / LOCAL-SIDE-EFFECT) — touch budget governance only applies to PROJECT. `.git/hooks/*` and the isolation branch are LOCAL-SIDE-EFFECT and not counted. In local-only mode all OUTPUT effectively becomes LOCAL-SIDE-EFFECT.
- **Multi-stack first-class** (v2.4) — any per-stack behavior in SKILL.md must iterate `stacks[]`, namespace commands (`lint:ts` / `lint:py` / `lint` aggregate), and rely on `stacks.json` for hook dispatch. Do not regress to a single-stack assumption.
- **Meta-rule 13 (v2.6 default local-only)** — default behavior reversed. Any new SKILL.md content describing OUTPUT must specify behavior under both modes; if you forget the local-only branch you've introduced a regression.
- **Meta-rule 16 (v2.6 PR/MR never auto-execute)** — host adapter offers commands, never executes. Adding auto-execute would violate §5 hard AUTH on external state changes.
- **Meta-rule 17 (v2.7 CLAUDE.md hard token ceiling)** — Phase 3 refuses CLAUDE.md ≥ 5000 tokens (`wc -c / 4` estimation) unless explicitly overridden. Soft cap 2500 triggers auto-compression. Editing the template to add content requires checking it stays in budget.
- **Meta-rule 18 (v2.7 `## Don't` one-line)** — each item ≤ 100 chars, never wraps. Long reasons go to commit msg / ADR / issue; CLAUDE.md keeps only the reference ID.
- **Meta-rule 19 (v2.7 no auto-execute system installs)** — Phase 2.5 system CLIs are offer-only, Claude Code plugins are offer-only. Project dev deps install only in `--share` mode after batch AUTH. Iron Law 7 in v2.7 explicitly forbids "dev-only blanket exemption" — every install must be on an AUTH'd list.
- **Meta-rule 20 (v2.8 all PROJECT writes must be reversible)** — write without marker / without manifest entry = §8 SAFETY violation. When adding a new Phase that touches PROJECT files, you must (a) define the marker form (line-based / markdown / JSON), (b) update the manifest schema, (c) update `/onboard --uninstall` to recognize it.
- **Meta-rule 21 (v2.8 snapshot before first modify)** — Phase 3/4/6/7/8 must snapshot existing PROJECT files to `<state-dir>/onboard-snapshots/<name>.<ISO>.phase<N>.pre` before first modification. No snapshot = no write.
- **Meta-rule 22 (v2.8 uninstall is single-direction)** — `--uninstall` does NOT use batch AUTH; each removal class gets its own hard AUTH; uninstall must be re-entrant (resumable on mid-way failure).
- **Meta-rule 23 (v2.9 plugin paths are ephemeral; v2.10.1 executable helper)** — `${CLAUDE_PLUGIN_ROOT}` changes with every plugin update. Never hard-code it into user settings.json. In plugin install mode, Phase 7 default is to invoke `skills/onboard/scripts/mirror-hooks.sh` (v2.10.1 — idempotent; writes `.mirror-manifest.json` recording version/source/dest/timestamp) which mirrors hook scripts to stable `~/.claude/onboard-runtime/hooks/`; settings.json references that mirror. Direct `${CLAUDE_PLUGIN_ROOT}` reference requires explicit user opt-in (accepting short-lived hook failure during plugin updates until Claude Code reloads).

When in doubt about whether a change requires bumping versions or only an edit, read the relevant Phase section of SKILL.md end-to-end — phases reference Iron Laws by number.

## Versioning philosophy (CHANGELOG.md)

The v2 series shipped four iterations (v2.0 → v2.4); each ratcheted only on evidence from a simulated or real onboarding run. **v2.4 is the v2 finale and the first version that net-decreased line count** (1311 → 1248). Future work follows the same protocol:

1. Run current version (simulated or real)
2. Number each issue (P-A, P-B, …) with Critical/High/Medium/Low severity
3. Accept-or-reject each with a written rationale
4. Roll the accepted set into the next version

Do NOT add speculative/forward-looking features to SKILL.md without an evidence trail.

## Validation commands

This repo ships scripts and prose — there is no application build/lint. The mechanical checks that gate a release:

```bash
# Syntax-check every shell script (must pass with no output)
bash -n skills/onboard/hooks/*.sh skills/onboard/scripts/*.sh install.sh tests/run.sh tests/integration/*.sh

# Validate all manifests + templates are well-formed JSON
jq empty < skills/onboard/settings.template.json
jq empty < skills/onboard/settings.local.template.json
jq empty < .claude-plugin/plugin.json
jq empty < .claude-plugin/marketplace.json

# Full end-to-end sandbox test (/plugin marketplace add + /plugin install simulation)
bash tests/run.sh   # 87 assertions / 4 tests (plugin-install 24 + hook-mirror 29 + install-roundtrip 25 + skillmd-links 9); sandboxes /tmp/onboard-{plugin,mirror,install}-sandbox; ~/.claude untouched
# or a single test: bash tests/run.sh plugin-install

# Make hooks executable (consumers do this; verify mode after edits)
ls -l skills/onboard/hooks/*.sh   # expect -rwxr-xr-x
```

Add a new integration test by dropping an executable `.sh` into `tests/integration/`; `tests/run.sh` picks it up automatically and aggregates exit codes.

When editing a hook script, also re-read SKILL.md's "示例脚本" section for that hook — the spec embeds canonical versions, and drift between the embedded version and `hooks/*.sh` is a real failure mode (the embedded copy is what `/onboard` would regenerate in Command mode).

## Conventions when editing

- **Language**: prose, comments, commit messages — match what's already there. Chinese is fine in spec prose and in commit/PR bodies; English-only for code identifiers, paths, hook JSON keys.
- **Smallest-diff edits to SKILL.md** are preferred. The spec is the artifact; rewrites cost simulation cycles.
- **Don't add a hook**, don't change the matcher set, and don't add a new env var without updating: (a) `skills/onboard/phases/phase-7.md` (canonical Phase 7 spec, v3.0+) AND the corresponding SKILL.md `## Phase 7` sentinel summary bullets (they must stay semantically synced per 元规则 27), (b) `settings.template.json` AND `settings.local.template.json` (both must match the matcher/env set), (c) the relevant `hooks/*.sh`, (d) README.md install/verify section, and (e) CHANGELOG.md. These are tied together — partial edits cause silent drift in the installed Skill.
- **`disable-model-invocation: true`** in SKILL.md frontmatter is intentional (prevents Claude from auto-running this side-effecting workflow). If removing it temporarily for testing, restore before committing.
