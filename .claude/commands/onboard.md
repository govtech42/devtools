---
description: Add a new app (or group) to the stack using the project recipe + skill
argument-hint: <app name> [group]
---

Onboard **$1** to the stack. Use the `onboard-app` skill and follow
`docs/recipes/onboarding-a-new-app.md` exactly, pre-empting the documented gotchas
(non-trusted Postgres extensions, CREATEDB, init-once, psql DO-block vars, YAML brace,
shallow compose-anchor merge, cross-arch builds, FDW enum handling).

Verify with `devtools up`, `devtools reporting`, and `devtools smoke` for the target
group before declaring done. Pin image tags; never publish a host port for
Postgres/PostgREST/Adminer/MinIO (N2).
