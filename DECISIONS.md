# DECISIONS — VPS Dev Tools

Living architecture/ops ledger. Each entry: **Decision · Why · Status**. Dates
absolute. Read this first when changing servers, forking, or revisiting a choice —
it captures the *why*, not just the *what*. Specs hold the detail
(`docs/superpowers/specs/`); this is the index of intent.

_Last updated: 2026-06-25._

---

## Platform & host

- **Multi-host group model, one repo.** · Groups (Dev, Support, Monitoring) each
  deploy to their own host; one repo, `deploy/<group>/` per host. · Why: clean
  isolation, independent cadence, each host self-contained. · **Locked.**
- **Cloud = AWS Lightsail; region us-east-1.** · Why: flat price incl. transfer,
  simpler than EC2. · **Locked** (pivot from EC2 — see Pivots).
- **Provision via AWS CLI script (`infra/scripts/`), no OpenTofu.** · Why: cheaper/
  simpler for a personal box; reproducible without IaC. · **Locked.**
- **Host sizes:** Dev **16 GB `xlarge_2_0`**, Support **8 GB `large_2_0`**,
  Monitoring TBD. · Why: Plane's stack is heavy (~11 containers); Support is light.
  · **Locked.**
- **4 GB swap per host.** · Why: safety net on an 8/16 GB box, not headroom. · **Locked.**
- **Data on a separate Lightsail block disk at `/data`.** · Why: survives instance
  recreation (instance = cattle, disk = pet). · **Locked.**
- **No backups.** · Why: accepted risk for a personal dev platform; block disk is
  the only durability. · **Locked (accepted risk).**
- **Secrets in `deploy/<group>/.env` on host, `chmod 600`, gitignored. No SSM.** ·
  Why: simple; Lightsail has no IAM instance role anyway. · **Locked.**

## Apps per group

- **Dev:** Forgejo (git), Mattermost (chat), Plane (project mgmt). · **Built, merged (PR #1).**
- **Support:** Planka (kanban), Chatwoot (helpdesk). · **Spec done.**
- **Admin:** Twenty CRM (shared Postgres `twenty` + own Redis). · Why: CRM on the
  standard Postgres; build/host decided in its own brainstorm. · **Backlog.**
- **Monitoring:** Beszel (lightweight server monitoring). · **Radar — to confirm.**

## Build strategy

- **Overlay official image:** Forgejo, Mattermost, **Planka (branding only)**. ·
  Why: no code changes → cheap updates. · **Locked.**
- **Fork from source:** **Plane**, **Chatwoot**. · Why: we modify their code
  (Plane customizations; Chatwoot += Kanban + features). · **Locked.**
- **Fork images → GHCR, built off-host, host pulls.** · Why: Lightsail has no IAM
  role (ECR painful); building Plane/Chatwoot on host risks OOM. · **Locked**
  (pivot from ECR).
- **Fork layout:** submodule `apps/<app>/upstream`, long-lived `code42` branch,
  `CHANGES.md` divergence log. · Why: diffable, rebasable against upstream. · **Locked.**

## Database & BI

- **One shared Postgres per host; one DB per app; reporting DB via `postgres_fdw`.**
  · Why: single backing service; apps stay attached resources; Plane's bundled
  `plane-db` dropped. · **Locked.**
- **Curated read-only `reporting` views, never raw app tables.** · Why: app schemas
  change between versions and lack external-facing RLS; views are the stable seam.
  · **Locked.**
- **PostgREST over `reporting` + read-only roles (`bi_reader`, `authenticator`);
  Adminer as SQL explorer.** · Why: auto REST API for BI; Supabase Studio dropped
  (too heavy). · **Locked.**
- **Per-group reporting** (each host runs its own Postgres+FDW+PostgREST). · Why:
  keeps N2 — no Postgres exposed between hosts. Cross-host BI deferred. · **Locked.**
- **Metabase/Superset deferred** (read-only role left ready). · **Deferred.**

## Access & network

- **Auth A1 — each app its own login, no SSO.** · Why: fewest moving parts to start.
  · **Locked.**
- **Network N2 — Caddy is the only public ingress (80/443, auto-TLS); SSH 22
  owner-IP only; Postgres/PostgREST/Adminer publish no host port (SSH tunnel).** ·
  Why: minimal attack surface; BI never public. · **Locked.**
- **Domains on `code42.dev`:** Dev `git.`/`chat.`/`plane.`; Support
  `board.` (Planka) / `support.` (Chatwoot). · **Locked.**
- **Ingress = Caddy, not Traefik.** · Why: our per-host set is small and static
  (3–5 subdomains), so Traefik's dynamic discovery adds little. Caddy gives a single
  readable Caddyfile, zero-config auto-TLS, an offline `caddy validate` lint step,
  and — key — **no Docker socket** (Traefik's Docker provider needs `docker.sock` =
  root-equivalent, against N2's minimal surface; avoiding it via file-provider or a
  socket-proxy negates Traefik's main benefit). · **Locked.** · _Reconsider if:_
  forward-auth **SSO** (Authelia/Authentik middleware), many dynamic/autoscaling
  services, or Traefik middlewares (rate-limit/headers) become needed.

## Repo & tooling

- **Layout:** `infra/` (provisioning) · `apps/<app>/` (shared per-app contexts) ·
  `deploy/<group>/` (compose + .env per host). · Why: provisioning, the app
  library, and per-host composition change for different reasons. · **Locked.**
- **`DATA_ROOT` env for dev/prod parity** (`/data` on VPS, `<repo>/.data` local). ·
  Why: same compose everywhere, no per-env edits. · **Locked.**
- **Local dev via Colima (not Docker Desktop); VPS uses Docker.** · Why: user
  preference; amd64-only images (Mattermost) cross-built with buildx on the arm64
  dev box. · **Locked.**
- **Tests = `Makefile` + `test/` (lint + live smoke; HTTP via curl sidecar).** ·
  Why: infra needs lint+smoke, not unit tests; sidecar because app images lack
  curl. · **Locked.**

## Support group (2026-06-25 brainstorm)

- **Chatwoot fork = add Kanban + product features.** · **Locked.**
- **WhatsApp = Cloud API (Meta official).** · Why: ToS-safe, no extra container,
  webhook via Caddy; avoids ban risk of unofficial bridges (Evolution API). ·
  **Locked.**
- **Chatwoot attachments = MinIO** (own container, bucket `chatwoot`, S3 Active
  Storage). · Why: decouples storage from disk, ready for scale/S3 backup. · **Locked.**
- **Chatwoot needs own Redis (Sidekiq) + shared Postgres `chatwoot` DB.** · **Locked.**

## Pivots (history — matters when changing servers)

- **EC2 + OpenTofu → Lightsail + AWS CLI script.** · Cheaper, simpler, no IaC.
- **ECR → GHCR** for fork images. · Lightsail has no IAM instance role.
- **Support apps: same Dev host (phase 2) → separate 8 GB host (own group).** ·
  Cleaner isolation; per-group reporting.
- **Dev host 8 GB → 16 GB.** · Plane's self-host stack grew (admin, live, RabbitMQ;
  ~11 containers).
- **Supabase-as-shared-DB idea → shared Postgres + curated `reporting` views.** ·
  Exposing app tables raw via PostgREST is brittle + insecure.

## Open decisions

- **Chatwoot Kanban feature design** — detailed once the base Chatwoot is up.
- **Admin group (Twenty CRM)** — own brainstorm: build (overlay vs fork), host size,
  Redis sizing. **Backlog.**
- **Monitoring stack (Beszel?)** — to confirm before building the Monitoring group.
- **Cross-host BI (Dev+Support correlation)** — deferred; default per-group, revisit
  when a concrete need appears.
