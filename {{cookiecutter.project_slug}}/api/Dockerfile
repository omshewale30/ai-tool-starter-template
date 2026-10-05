# {{ cookiecutter.project_name }} API image.
#
# Environment-agnostic: all configuration arrives as environment variables at
# run time (see deploy/env-contract.json), so one image digest is promoted
# across environments.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY pyproject.toml alembic.ini ./
COPY app ./app
RUN pip install ".[foundry]" \
    && useradd --system --uid 1001 --no-create-home appuser

USER appuser
EXPOSE 8000

# Migrations are fail-closed: serving on the wrong schema is worse than not
# serving. Container Apps retries the revision until the database is reachable.
# Tune --workers per workload (each worker holds its own DB pool).
CMD ["/bin/sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --proxy-headers --forwarded-allow-ips='*'"]
