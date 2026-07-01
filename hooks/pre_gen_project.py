"""Cookiecutter pre-generation hook: validate inputs before rendering."""
import re
import sys

SLUG = "{{ cookiecutter.project_slug }}"
PACKAGE = "{{ cookiecutter.python_package_name }}"
RESOURCE_PREFIX = "{{ cookiecutter.resource_prefix }}"
BACKEND_APP_ID_URI = "{{ cookiecutter.backend_app_id_uri }}"

if not re.match(r"^[a-z][a-z0-9-]+$", SLUG):
    sys.exit(
        f"ERROR: project_slug '{SLUG}' is invalid. "
        "Use lowercase letters, numbers, and hyphens (must start with a letter)."
    )

if not re.match(r"^[a-z][a-z0-9_]+$", PACKAGE):
    sys.exit(
        f"ERROR: python_package_name '{PACKAGE}' is invalid. "
        "Use lowercase letters, numbers, and underscores (must start with a letter)."
    )

# Used across multiple Azure resources (including storage-account-derived names).
if not re.match(r"^[a-z][a-z0-9]{1,11}$", RESOURCE_PREFIX):
    sys.exit(
        f"ERROR: resource_prefix '{RESOURCE_PREFIX}' is invalid. "
        "Use 2-12 lowercase letters/numbers (must start with a letter)."
    )

if not re.match(r"^api://[A-Za-z0-9._-]+$", BACKEND_APP_ID_URI):
    sys.exit(
        f"ERROR: backend_app_id_uri '{BACKEND_APP_ID_URI}' is invalid. "
        "Use a value like 'api://internal-ai-tool'."
    )

print(f"Generating project '{SLUG}' (python package: {PACKAGE})")
