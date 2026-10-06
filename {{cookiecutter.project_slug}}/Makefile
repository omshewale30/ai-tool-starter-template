# {{ cookiecutter.project_name }} — developer shortcuts. `make help` lists targets.

.DEFAULT_GOAL := help
SHELL := /bin/bash
PYTHON ?= python3.11
VENV := .venv/bin

.PHONY: help install dev up down logs migrate migration check test test-api test-web e2e \
        lint fmt generate-api

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

install: ## Create .venv, install API (editable) and web dependencies
	$(PYTHON) -m venv .venv
	$(VENV)/pip install --upgrade pip
	$(VENV)/pip install -e "./api[dev]"
	npm --prefix web ci

dev: ## Postgres in docker + API and web with hot reload (mock AI, sign-in off)
	bash scripts/dev.sh

up: ## Whole stack in docker compose (API image, next dev, Postgres)
	docker compose up --build

down: ## Stop docker compose and delete its volumes
	docker compose down -v

logs: ## Tail docker compose logs
	docker compose logs -f

migrate: ## Apply database migrations (uses DATABASE_URL from .env)
	set -a; . ./.env; set +a; cd api && ../$(VENV)/alembic upgrade head

migration: ## New migration from model changes: make migration m="add widgets"
	set -a; . ./.env; set +a; cd api && ../$(VENV)/alembic revision --autogenerate -m "$(m)"

check: ## Everything CI's checks run (scripts/ci.sh backend + frontend)
	PATH="$(CURDIR)/.venv/bin:$$PATH" bash scripts/ci.sh backend
	PATH="$(CURDIR)/.venv/bin:$$PATH" bash scripts/ci.sh frontend

test: test-api test-web ## Unit tests only (fast)

test-api: ## API tests (mock AI, in-memory SQLite)
	cd api && ENVIRONMENT=test AUTH_MODE=disabled AI_PROVIDER=mock ../$(VENV)/pytest

test-web: ## Web unit/component tests
	npm --prefix web test

e2e: ## Playwright against the real API behind a production web build
	PYTHON="$(CURDIR)/.venv/bin/python" npm --prefix web run test:e2e

lint: ## Lint API (ruff) and web (eslint)
	cd api && ../$(VENV)/ruff check app scripts
	npm --prefix web run lint

fmt: ## Format and auto-fix the API
	cd api && ../$(VENV)/ruff format app scripts && ../$(VENV)/ruff check --fix app scripts

generate-api: ## Regenerate web/src/lib/api/schema.ts after changing API routes/schemas
	PYTHON="$(CURDIR)/.venv/bin/python" npm --prefix web run generate:api
