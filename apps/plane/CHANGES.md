# Plane fork — divergences from upstream

Work on branch `code42` off `upstream`. Log every change so rebases stay sane.

| Date | File(s) | Change | Why | Upstreamable |
|------|---------|--------|-----|--------------|
| 2026-06-25 | deploy compose (ours) | dropped upstream `plane-db`; point at shared Postgres `plane` | one Postgres for the whole group host + reporting | no (deploy-specific) |

<!-- Add a row per code change to the fork. Keep newest at the bottom. -->
