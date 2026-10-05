"""Cookiecutter post-generation hook.

Removes the optional RAG (Azure AI Search) feature when the user opts out, so the
generated project only contains code paths it actually uses. The few shared files
that mention RAG (API router, pyproject.toml, web navigation) are gated with Jinja
conditionals instead.
"""
import os
import shutil

ENABLE_SEARCH = "{{ cookiecutter.enable_ai_search }}" == "yes"

RAG_PATHS = [
    # API
    os.path.join("api", "app", "services", "search"),
    os.path.join("api", "app", "api", "v1", "routes", "rag.py"),
    os.path.join("api", "app", "prompts", "rag.md"),
    os.path.join("api", "app", "tests", "test_rag.py"),
    # Web
    os.path.join("web", "src", "app", "documents"),
    # Infra
    os.path.join("infra", "bicep", "modules", "search.bicep"),
    os.path.join("infra", "bicep", "services", "search.bicep"),
    os.path.join("infra", "scripts", "deploy-search.sh"),
    os.path.join("infra", "scripts", "setup-search-index.sh"),
    os.path.join("infra", "search"),
    # Docs
    os.path.join("docs", "rag.md"),
]


def remove(path: str) -> None:
    if os.path.isdir(path):
        shutil.rmtree(path)
    elif os.path.isfile(path):
        os.remove(path)


if not ENABLE_SEARCH:
    for path in RAG_PATHS:
        remove(path)

print("")
print("Project generated. Next steps:")
print("  1. cd {{ cookiecutter.project_slug }}")
print("  2. Read README.md (local development, then docs/runbook.md to deploy)")
print("  3. make install && make dev")
