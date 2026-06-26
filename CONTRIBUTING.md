# Contributing

## Workflow
1. Read [CLAUDE.md](CLAUDE.md) (doctrine) and [DECISIONS.md](DECISIONS.md) (the *why*)
   before changing architecture. Check DECISIONS before reversing a choice.
2. Branch off `main`. Keep the stack bootable at every commit (always-working).
3. Make the change in the right layer: `infra/` (provisioning), `apps/<app>/` (shared
   context), `deploy/<group>/` (composition). Adding an app? Follow
   [docs/recipes/onboarding-a-new-app.md](docs/recipes/onboarding-a-new-app.md).
4. **Verify the real thing:** `devtools lint`, then `devtools up --<group>` +
   `devtools smoke --<group>` green before you push. Evidence, not assertion.
5. Commit small and often (Conventional Commits). Open a PR `--base main`.

## Rules
- **Secrets:** never commit `.env`, `*.env.plane`, `*.pem`, `*.tfstate`/`*.tfvars`.
  `.gitignore` enforces this — don't weaken it. New setting → new env var (twelve-factor).
- **Pin image tags.** No `:latest` in production env.
- **N2:** don't publish a host port for Postgres/PostgREST/Adminer/MinIO. If a change
  would, stop and flag it.
- **Forks (Plane, Chatwoot):** edit on the `code42` branch of the submodule, log every
  divergence in `apps/<app>/CHANGES.md`, build off-host → GHCR.
- **No backups exist.** Be careful with `down -v`, volume prunes, deleting the block
  disk, `destroy-lightsail.sh`. Confirm before running.

## Tests
Infra tests are lint + live smoke (`test/`). Add app checks to the group branch in
`test/smoke.sh`. HTTP checks use a curl sidecar (app images often lack curl).
