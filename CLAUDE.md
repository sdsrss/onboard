# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo is **not** an application — it is the `/onboard` **Claude Code Skill** itself (current version: v2.7). The "code" being maintained is:

- `SKILL.md` — the workflow spec defining a 10-phase onboarding protocol (Phase 0 / 0.5 / 1 / 1.5 / 1.7 / 2 / 2.5 / 3-8), Doctor Mode (`--doctor`, v2.5+; D1-D14 checks), Mode model (`--local-only` default vs `--share`, v2.6+), and Install Plan / Plugin recommendation matrix (v2.7+). This file's frontmatter (`name: onboard`, `disable-model-invocation: true`, `allowed-tools: Read, Glob, Grep`) is what registers it as a Skill when placed under `.claude/skills/onboard/`.
- `hooks/*.sh` (4 scripts) — supporting files referenced from settings files by the *installer project*, not run inside this repo.
- `settings.template.json` — reference config for `--share` mode (`.claude/settings.json`).
- `settings.local.template.json` (v2.6) — reference config for `--local-only` mode (`.claude/settings.local.json`); hooks reference user-global `~/.claude/skills/onboard/` install path.
- `README.md` — install + usage guide for end users (the project installing this skill).
- `CHANGELOG.md` — version history.

Consumers install this package into their project at `.claude/skills/onboard/`, then `/onboard` becomes available as a slash command in their Claude Code session.

## Architecture you must know

**SKILL.md is law.** When asked to change behavior of the `/onboard` flow, edit SKILL.md — do not write code elsewhere expecting it to take effect. SKILL.md is consumed by *another* Claude instance reading the file at slash-command invocation; behavior lives in the prose, not in any runtime.

**Two artifact layers, never confuse them:**
1. *This repo* (the skill package) — what you edit here.
2. *The installer project's `.claude/`* — where the skill lands after `cp -r onboard/ .claude/skills/`. Paths like `.claude/onboarding-state.json`, `.claude/onboarding-logs/`, `${CLAUDE_PROJECT_DIR}/...` all refer to *that* layer, not this repo's working tree.

**Hook scripts in `hooks/` are referenced, not copied** (v2.4 Skill-form change). The installer project's `settings.json` points at `${CLAUDE_PROJECT_DIR}/.claude/skills/onboard/hooks/<name>.sh` directly. Phase 7 in SKILL.md does NOT generate scripts in Skill mode. (Command-mode fallback still dynamic-generates — see SKILL.md "Publishing path decision".)

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

## Iron Laws and meta-rules (non-negotiable when editing SKILL.md)

SKILL.md §0 defines **19 Iron Laws** and §"元规则" defines **19 meta-rules** (v2.6 added 13–16; v2.7 added 17–19). They are not advisory — they have load-bearing references throughout the spec. Editing rules to keep in mind:

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

When in doubt about whether a change requires bumping versions or only an edit, read the relevant Phase section of SKILL.md end-to-end — phases reference Iron Laws by number.

## Versioning philosophy (CHANGELOG.md)

The v2 series shipped four iterations (v2.0 → v2.4); each ratcheted only on evidence from a simulated or real onboarding run. **v2.4 is the v2 finale and the first version that net-decreased line count** (1311 → 1248). Future work follows the same protocol:

1. Run current version (simulated or real)
2. Number each issue (P-A, P-B, …) with Critical/High/Medium/Low severity
3. Accept-or-reject each with a written rationale
4. Roll the accepted set into the next version

Do NOT add speculative/forward-looking features to SKILL.md without an evidence trail.

## Validation commands

There is no build, lint, or test framework for this repo itself — it ships scripts and prose. The only mechanical checks SKILL.md mandates (see §"Phase 7 自动验证"):

```bash
# Syntax-check every hook script (must pass with no output)
bash -n hooks/*.sh

# Validate both settings templates are well-formed JSON
jq empty < settings.template.json
jq empty < settings.local.template.json

# Make hooks executable (consumers do this; verify mode after edits)
ls -l hooks/*.sh   # expect -rwxr-xr-x
```

When editing a hook script, also re-read SKILL.md's "示例脚本" section for that hook — the spec embeds canonical versions, and drift between the embedded version and `hooks/*.sh` is a real failure mode (the embedded copy is what `/onboard` would regenerate in Command mode).

## Conventions when editing

- **Language**: prose, comments, commit messages — match what's already there. Chinese is fine in spec prose and in commit/PR bodies; English-only for code identifiers, paths, hook JSON keys.
- **Smallest-diff edits to SKILL.md** are preferred. The spec is the artifact; rewrites cost simulation cycles.
- **Don't add a hook**, don't change the matcher set, and don't add a new env var without updating: (a) SKILL.md Phase 7, (b) `settings.template.json` AND `settings.local.template.json` (both must match the matcher/env set), (c) the relevant `hooks/*.sh`, (d) README.md install/verify section, and (e) CHANGELOG.md. These are tied together — partial edits cause silent drift in the installed Skill.
- **`disable-model-invocation: true`** in SKILL.md frontmatter is intentional (prevents Claude from auto-running this side-effecting workflow). If removing it temporarily for testing, restore before committing.
