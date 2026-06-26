# Recipes

Hard-won fixes from building the Dev/Support/Admin groups, written so future app
installs don't rediscover them. Start with **onboarding-a-new-app** — it's the
checklist; the others are deep-dives it links to.

- [onboarding-a-new-app.md](onboarding-a-new-app.md) — add an app to a group, end to end
- [postgres-shared-db.md](postgres-shared-db.md) — shared Postgres: APP_DBS, CREATEDB, non-trusted extensions, init-once, psql gotchas
- [cross-arch-builds.md](cross-arch-builds.md) — amd64-only images on the arm64 dev box (buildx / Rosetta), GHCR forks
- [fdw-reporting.md](fdw-reporting.md) — curated reporting views over app DBs via postgres_fdw

The same knowledge is encoded as a skill at `.claude/skills/onboard-app/` so Claude
applies it automatically.
