# .claude/

Claude Code configuration for this repo (committed; shared with the team).

- **`settings.toml`** — Conductor repo settings (setup/run/archive scripts,
  `run_mode`). See the `conductor` skill / https://conductor.build/docs.
- **`skills/`** — repo skills Claude loads on demand. `onboard-app/` encodes how to
  add an app to the stack (and the gotchas to pre-empt). Mirrors `docs/recipes/`.
- **`commands/`** — slash commands (`/smoke`, `/onboard`) — thin wrappers over the
  `devtools` CLI / recipes.

Project memory lives in **`CLAUDE.md`** at the repo root (the Anthropic-recommended
location), with the operating doctrine and a pointer to `DECISIONS.md`. Personal,
uncommitted overrides go in `.claude/settings.local.toml` (gitignored).

Layout follows Anthropic's guidance: root `CLAUDE.md` for always-on memory; `.claude/`
for skills, commands, and settings that should travel with the repo.
