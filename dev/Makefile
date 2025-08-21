SHELL := /bin/bash
PROJECT ?= codex-embeddings-dev
COMPOSE := docker compose -f docker-compose.yaml

up:
	$(COMPOSE) up -d --build

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) down && $(COMPOSE) up -d --build

lint:
	python3 -m ruff check services runners || true

format:
	python3 -m ruff format services runners || true

