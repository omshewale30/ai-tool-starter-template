"""Cookiecutter post-generation hook.

Removes the optional Azure AI Search scaffolding when the user opts out, so the
generated project only contains code paths it actually uses.
"""
import os
import shutil

ENABLE_SEARCH = "{{ cookiecutter.enable_ai_search }}" == "yes"


def remove(path: str) -> None:
    if os.path.isdir(path):
        shutil.rmtree(path, ignore_errors=True)
    elif os.path.isfile(path):
        os.remove(path)


if not ENABLE_SEARCH:
    # Remove the optional backend search service. The Bicep search module is
    # kept but gated by the `enableSearch` parameter (false by default), so the
    # infrastructure stays internally consistent whether or not it's deployed.
    remove(os.path.join("apps", "api", "app", "services", "search"))

print("")
print("Project generated. Next steps:")
print("  1. cd {{ cookiecutter.project_slug }}")
print("  2. Read README.md and docs/local-development.md")
print("  3. cp .env.example .env  &&  make dev")
