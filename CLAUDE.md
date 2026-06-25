# CLAUDE.md — VPS Dev Tools

Self-hosted dev-tools stack: **Forgejo** (git), **Mattermost** (chat), **Plane**
(project mgmt) on **one AWS Lightsail host** (16 GB plan), Docker Compose, shared
Postgres, provisioned by an **AWS CLI script** (no OpenTofu). Design spec:
`docs/superpowers/specs/2026-06-25-vps-devtools-design.md`. Read it before changing
architecture.

**Multi-host group model:** one repo deploys several **groups**, one Lightsail host
each. **Dev** (16 GB: Forgejo, Mattermost, Plane) is built first; **Support** (8 GB:
Planka, Chatwoot) is next; **Monitoring** (Beszel, *to confirm*) is on the radar.

**Layout:** `infra/` = cloud/host provisioning (`infra/scripts/` = Lightsail script,
`user-data.sh`, teardown). `apps/` = **shared per-app contexts**, one self-contained
dir each (`apps/caddy`, `apps/postgres`, `apps/forgejo`, `apps/mattermost`,
`apps/plane`, `apps/postgrest`, …). `deploy/<group>/docker-compose.yml` = one
composition per group → one host, referencing `../../apps/<app>` build contexts;
secrets in `deploy/<group>/.env`. **Plane is our fork** — `apps/plane/upstream/` is a
submodule; log every divergence in `apps/plane/CHANGES.md`. Each group host is
self-contained (own Caddy + Postgres + reporting); cross-host BI is an open decision
(spec §11) — default to per-group reporting to keep N2.

---

## Karpathy Doctrines (how to build here)

Operating principles for anyone (human or agent) working in this repo.

1. **Always have a working system.** Every change keeps the stack bootable.
   Small, reversible steps over big-bang rewrites. If `docker compose up` is red,
   stop and fix before adding anything.

2. **Make it work, make it right, make it fast — in that order.** Don't optimize
   the t3.large memory budget before the three apps actually boot and talk to
   Postgres. Premature tuning is wasted motion.

3. **Verify the real thing, not the idea of it.** Don't claim "Forgejo is up"
   from a clean `tofu apply`. `curl https://git.code42.dev`, read the container
   logs, `psql` the table. Look at the actual bytes. Evidence before assertion.

4. **The best code is no code; the best service is no service.** Every container
   added costs RAM on an 8 GB box and a thing that can break at 3 a.m. Justify
   each service. Prefer an app's native feature over a new sidecar.

5. **Minimize moving parts and keep them loosely coupled.** Apps talk to Postgres
   as an attached resource, not as a shared schema. The `reporting` view layer is
   the only seam between BI and app internals — keep that boundary clean.

6. **Tight feedback loops.** Lint locally (`docker compose config`, `tofu
   validate`) before you push a 6-minute boot cycle. Reproduce on the smallest
   surface that shows the bug.

7. **Be suspicious of your own setup.** Most "it's broken" is a config/env/path
   mistake, not the upstream software. Check `.env`, the Caddyfile, the DNS
   record, the security group — in that order — before blaming Plane.

8. **Code (and config) is read far more than written.** Match the surrounding
   style. A Compose file or Dockerfile someone can scan top-to-bottom beats a
   clever one.

---

## Deploy Logic (Heroku / Twelve-Factor)

This host behaves like a Heroku-style platform. Honor these:

- **I. Codebase → deploy.** One repo, one deployable stack. `infra/scripts/create-lightsail.sh`
  builds the host; `docker compose up -d` runs the apps. No snowflake hand-clicks
  in the Lightsail console — if it isn't in a script in the repo, it doesn't exist.

- **III. Config in the environment.** All secrets/tunables live in `stack/.env`
  (gitignored, `chmod 600`). **Never** hardcode a password, key, or hostname in
  a Dockerfile, Compose file, or committed config. New setting → new env var.

- **IV. Backing services are attached resources.** Postgres, Redis, MinIO are
  attached by URL/credentials from `.env`. An app must not assume a local socket
  or a fixed host — swap the resource by changing the env var, nothing else.

- **V. Strictly separate build / release / run.**
  - **Build:** images are built (Plane from the fork → **GHCR**; Forgejo/Mattermost
    overlays) ahead of time, **off-host** (local or GitHub Actions). **Never build
    Plane on the host** (OOM risk). Lightsail has no IAM role — host pulls from GHCR
    with a token from `.env`, not ECR.
  - **Release:** `.env` + pinned image tags = the release. Pin tags; no `:latest`
    in production paths.
  - **Run:** `docker compose up -d` only pulls and runs. Run does no compilation.

- **VI. Processes are stateless; state lives in backing services.** Containers are
  disposable. All durable data is in the Postgres volume / MinIO / named volumes
  on the `/data` EBS. Deleting and recreating any app container loses nothing.

- **VII. Port binding behind one front door.** Apps bind internally; **Caddy** is
  the only public ingress (80/443, auto-TLS). Postgres/PostgREST/Studio publish
  **no host port** — reach them via `ssh -L`.

- **IX. Disposability.** Fast startup, graceful shutdown. Assume the box can be
  recreated; the attached **Lightsail block disk** (`/data`) and `.env` are what
  must survive. Treat the instance as cattle, the block disk as the pet.

- **X. Dev/prod parity.** The same Compose stack and pinned images run everywhere.
  Don't special-case the host with manual `docker run` commands.

- **XI. Logs are event streams.** Read `docker compose logs -f <svc>`; don't write
  app logs to files inside containers.

---

## Guardrails

- **Secrets:** never commit `.env`, `*.tfvars`, `*.tfstate`. `.gitignore` enforces
  this — don't weaken it.
- **No backups exist.** Be careful with `docker compose down -v`, volume prunes,
  deleting the **Lightsail block disk**, and `destroy-lightsail.sh` — they are
  irreversible data loss. The block disk survives instance deletion, but only if
  you delete the *instance*, not the *disk*. Confirm before running any.
- **Network model is N2:** keep Postgres/PostgREST/Studio off public ports. If a
  change would publish one, stop and flag it.
- **16 GB host.** Adding a service? Account for its idle RAM and update the budget
  in the spec. Plane's stack alone is ~3 GB across ~11 containers. Swap is a safety
  net, not headroom.
- **App tables are upstream-owned.** Expose data through `reporting` views and the
  apps' native APIs — never wire BI directly to an app's internal tables.

## Commands

```bash
bash infra/scripts/create-lightsail.sh                       # provision host (AWS CLI; per group)
docker compose -f deploy/dev/docker-compose.yml config       # lint (group = dev)
docker compose -f deploy/dev/docker-compose.yml up -d         # run
docker compose -f deploy/dev/docker-compose.yml logs -f <svc> # logs
ssh -L 5432:127.0.0.1:5432 <host>                            # reach Postgres/BI (N2)

# Plane fork
git -C apps/plane/upstream fetch upstream                 # track upstream
# edit on the code42 branch, log in apps/plane/CHANGES.md, build off-host, push GHCR
```
