# Using this as a GitHub template (without Cookiecutter)

The recommended way to create a project is with Cookiecutter (see the root
`README.md`). If you instead copy the `{{cookiecutter.project_slug}}/` tree by
hand — for example by turning this into a GitHub "template repository" — you must
replace the Cookiecutter placeholders yourself.

## Placeholders to replace

Search the generated tree for these tokens and replace every occurrence:

| Placeholder token | Replace with | Example |
| --- | --- | --- |
| `{{ cookiecutter.project_name }}` | Human-readable name | `Internal AI Tool` |
| `{{ cookiecutter.project_slug }}` | kebab-case slug | `internal-ai-tool` |
| `{{ cookiecutter.python_package_name }}` | snake_case package | `internal_ai_tool` |
| `{{ cookiecutter.project_description }}` | One-line description | `Internal AI tool` |
| `{{ cookiecutter.azure_location }}` | Azure region | `eastus` |
| `{{ cookiecutter.resource_prefix }}` | Azure resource prefix | `aitool` |
| `{{ cookiecutter.entra_tenant_id }}` | Entra tenant GUID | `1111...` |
| `{{ cookiecutter.frontend_client_id }}` | SPA client GUID | `2222...` |
| `{{ cookiecutter.backend_client_id }}` | API client GUID | `3333...` |
| `{{ cookiecutter.backend_app_id_uri }}` | API audience | `api://internal-ai-tool` |

Handy one-liner (macOS/BSD `sed`; review before running):

```bash
grep -rl 'cookiecutter\.' . | while read -r f; do
  sed -i '' \
    -e 's/{{ cookiecutter.project_name }}/Internal AI Tool/g' \
    -e 's/{{ cookiecutter.project_slug }}/internal-ai-tool/g' \
    -e 's/{{ cookiecutter.python_package_name }}/internal_ai_tool/g' \
    -e 's/{{ cookiecutter.resource_prefix }}/aitool/g' \
    -e 's/{{ cookiecutter.azure_location }}/eastus/g' \
    "$f"
done
```

## After replacing

1. Rename the top-level project directory to your slug.
2. If you don't need Azure AI Search, delete
   `apps/api/app/services/search/` and `infra/bicep/modules/search.bicep`.
3. Fill in real GUIDs via environment variables / Key Vault — **do not** commit
   real tenant or client secrets. See `docs/security.md`.
