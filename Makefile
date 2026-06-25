# Dev Tools — local (Colima) + VPS (Docker) operations.
# GROUP selects the deployment group (host). Default: dev.
GROUP   ?= dev
DIR      = deploy/$(GROUP)
COMPOSE  = docker compose -f $(DIR)/docker-compose.yml --env-file $(DIR)/.env

.PHONY: help datadirs lint up down ps logs smoke test clean colima-up

help:
	@echo "make lint            # static checks (compose config, bash -n, caddy validate)"
	@echo "make up              # create data dirs + bring the group stack up (build+pull)"
	@echo "make smoke           # run the live smoke suite against the running stack"
	@echo "make test            # lint + up + smoke"
	@echo "make down            # stop containers (KEEPS data)"
	@echo "make ps / make logs  # status / follow logs"
	@echo "GROUP=$(GROUP)  (override: make up GROUP=support)"

colima-up:
	@colima status >/dev/null 2>&1 || colima start --cpu 4 --memory 8 --disk 60

datadirs:
	@set -a; . $(DIR)/.env; set +a; \
	  mkdir -p "$$DATA_ROOT"/caddy/data "$$DATA_ROOT"/caddy/config "$$DATA_ROOT"/postgres \
	           "$$DATA_ROOT"/forgejo "$$DATA_ROOT"/mattermost/data "$$DATA_ROOT"/mattermost/config \
	           "$$DATA_ROOT"/plane/minio "$$DATA_ROOT"/plane/redis "$$DATA_ROOT"/plane/rabbitmq; \
	  echo "data dirs ready under $$DATA_ROOT"

lint:
	@bash test/lint.sh $(GROUP)

# Local build: dev box is arm64, the VPS is amd64. Mattermost is amd64-only, so
# cross-build it with buildx; the rest build native. On the VPS use plain
# `docker compose up -d --build` (everything native amd64) — see docs/RUNBOOK.md.
build: colima-up
	@command -v docker-buildx >/dev/null 2>&1 || docker buildx version >/dev/null 2>&1 || \
	  { echo "docker buildx required locally (brew install docker-buildx)"; exit 1; }
	docker buildx build --platform linux/amd64 --load -t devtools/mattermost:0.1.0 apps/mattermost
	$(COMPOSE) build postgres forgejo caddy

up: colima-up datadirs build
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f $(SVC)

smoke:
	@GROUP=$(GROUP) bash test/smoke.sh $(GROUP)

# Apply the reporting FDW + views (run after the apps have migrated).
reporting:
	@set -a; . $(DIR)/.env; set +a; \
	  cat apps/postgres/reporting.sql | $(COMPOSE) exec -T postgres \
	    psql -v ON_ERROR_STOP=1 -U postgres -d reporting -v fdw_pass="$$FDW_READER_PASSWORD"
	@echo "reporting layer applied"

test: lint up smoke

clean:
	$(COMPOSE) down
	@echo "NOTE: data under DATA_ROOT is NOT removed (no backups). Remove manually if intended."
