# Chatwoot fork build. Built OFF-HOST and pushed to GHCR; the host only pulls.
# The fork ships its own Dockerfile under apps/chatwoot/upstream/docker/Dockerfile —
# build THAT against the submodule (see README). This file pins the base for
# reference / a thin overlay path until the fork's own image is wired in CI.
FROM chatwoot/chatwoot:v3.16.0
# Our Kanban + feature changes ride in the fork image built from apps/chatwoot/upstream.
