# {{ cookiecutter.project_name }} — developer shortcuts.
# Run `make help` to list targets.

.DEFAULT_GOAL := help
SHELL := /bin/bash
PYTHON ?= python3.11

.PHONY: help dev up down logs api web install-api install-web \
        test test-api test-web e2e lint typecheck fmt migrate

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

dev: up ## Alias for `up` (full local stack)

up: ## Start frontend + backend + db locally (mock AI, disabled auth)
	docker compose up --build

down: ## Stop and remove the local stack
	docker compose down -v

logs: ## Tail logs from the local stack
	docker compose logs -f

install-api: ## Install backend dependencies into a venv
	cd apps/api && $(PYTHON) -m venv .venv && . .venv/bin/activate && pip install -e ".[dev]"

install-web: ## Install frontend dependencies
	cd apps/web && npm install

api: ## Run the backend with autoreload (needs a reachable DB)
	cd apps/api && . .venv/bin/activate && uvicorn app.main:app --reload

web: ## Run the frontend dev server
	cd apps/web && npm run dev

migrate: ## Apply database migrations
	cd apps/api && . .venv/bin/activate && alembic upgrade head

test: test-api test-web ## Run all unit/component tests

test-api: ## Run backend tests (mock AI, in-memory DB)
	cd apps/api && . .venv/bin/activate && pytest

test-web: ## Run frontend unit/component tests
	cd apps/web && npm run test

e2e: ## Run Playwright smoke tests
	cd apps/web && npm run test:e2e

lint: ## Lint frontend
	cd apps/web && npm run lint

typecheck: ## Type-check frontend
	cd apps/web && npm run typecheck

fmt: ## Format backend (ruff)
	cd apps/api && . .venv/bin/activate && ruff format app && ruff check --fix app
