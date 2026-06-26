# VPS Dev Tools — Monitoring Group Design Spec

**Date:** 2026-06-25
**Status:** Implemented (local, Colima) — Monitoring group
**Owner:** code42
**Parent:** `2026-06-25-vps-devtools-design.md` (§11 group model)

## Goal

Lightweight server monitoring across the fleet, starting with **Beszel**.

## Locked decisions (by precedent)

| Item | Decision |
|---|---|
| Host | Lightsail **small** (~2 GB) — Beszel is tiny; cheapest sensible plan |
| App | **Beszel** hub + agent (official multi-arch images, used directly) |
| Store | Beszel's own **SQLite/PocketBase** (`/beszel_data`) — **no shared Postgres**, so this group has **no `postgres`/`reporting`** (best-service-is-no-service) |
| Domain | `status.code42.dev` (Caddy → `beszel:8090`) |
| Network | N2 — only Caddy public; hub/agent no host port |
| Agents | one per monitored host; `agents` compose profile (off by default). Remote agents (Dev/Support/Admin hosts) are **cross-host** → deferred (same posture as cross-host BI) |

## Services (`deploy/monitoring/docker-compose.yml`)

`caddy` · `beszel` (hub, 8090, SQLite volume) · `beszel-agent` (profile `agents`,
needs `BESZEL_KEY` from the hub UI + docker.sock ro).

## Verification (done locally)

`make up GROUP=monitoring` + `make smoke GROUP=monitoring` → hub `/api/health` OK,
N2 (no host ports), agent skipped (profile off). `devtools ... --monitoring` works.

## Out of scope

Remote agents on the other hosts (cross-host); alerting integrations; metrics
beyond Beszel's defaults.
