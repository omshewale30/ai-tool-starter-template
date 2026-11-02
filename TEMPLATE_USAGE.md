# Maintaining the template

The generated project lives in `{{cookiecutter.project_slug}}/`. Cookiecutter renders
every file in it with Jinja, except the paths listed in `_copy_without_render`
(`cookiecutter.json`).

## The verification loop

```bash
bash scripts/verify-template.sh              # both variants (RAG off / on)
bash scripts/verify-template.sh --variant no # one variant
bash scripts/verify-template.sh --docker     # also build images + scripts/smoke.sh
bash scripts/verify-template.sh --keep       # keep the generated projects (prints the path)
```

For each variant it renders the template, commits the result to a fresh git repo,
installs dependencies, and runs the generated project's own `scripts/ci.sh backend`
and `frontend` (lint, tests, deploy-script tests, generated-types check, build),
`scripts/ci.sh infra` (`terraform fmt -check` and `validate` on every root; needs
Terraform ≥ 1.11, required in CI), `docker compose config`, and actionlint. It also
asserts that RAG files exist only in the RAG variant and that no `cookiecutter.`
placeholder survives rendering. The template repo's `.github/workflows/ci.yml` runs
it through the FO-AI reusable CI.

It refuses to run if ignored files (caches, `node_modules`) are inside the template
directory, since Cookiecutter would try to render them.

Fast iteration: render once with `--keep`, edit inside the generated project until
its checks pass, then copy the changes back into the template.

## Jinja pitfalls

- `{{`, `{%` and `{#` start Jinja. In TSX, never write `style={{...}}` or
  `components={{...}}`; hoist the object into a constant. In shell, avoid `${#var}`.
  Rendering fails loudly if you slip.
- Files that must not be rendered (GitHub workflows, `scripts/*.sh`, `scripts/*.py`,
  `scripts/tests/*`, `web/package-lock.json`, `web/src/lib/api/schema.ts`) are in
  `_copy_without_render`. They can't use `{{ cookiecutter.* }}`, so the scripts derive
  names at run time (e.g. `IMAGE_PREFIX` from the repository name).
- Keep conditionals rare. RAG is the only option: its own files are deleted by
  `hooks/post_gen_project.py`, and only three shared files carry `{% if %}` blocks
  (`api/app/api/v1/router.py`, `api/pyproject.toml`, `web/src/components/AppShell.tsx`)
  plus docs. Add new optional features the same way and list their paths in both the
  hook and `scripts/verify-template.sh`.
- Templated files aren't valid Python/TOML/TS until rendered, so tools pointed at the
  template directory (ruff, tsc) may complain. Run them in a rendered project.

## Generated artifacts committed in the template

| File | Regenerate with (in a rendered project) |
| --- | --- |
| `web/package-lock.json` | `npm --prefix web install` after editing `web/package.json` |
| `web/src/lib/api/schema.ts` | `make generate-api` after changing API routes or schemas |

Copy the result back into the template. CI fails if either is stale. The OpenAPI
document contains no project-specific text, and the RAG route is excluded from it, so
one `schema.ts` serves both variants.

## Updating pinned things

- **FO-AI/automation**: the commit pin appears in the template's `.github/workflows/ci.yml`
  and the generated `.github/workflows/ci.yml` and `cd.yml`; bump all three together.
- **Next.js**: read `web/node_modules/next/dist/docs/` for the new version; keep
  `web/AGENTS.md` as `next dev` writes it.
- **Azure AI Search API**: `API_VERSION` in `infra/scripts/setup-search-index.sh`.
- **Terraform / providers**: `required_version` and provider constraints in each root's
  `versions.tf`; the Terraform version CI installs in the template's and the generated
  `.github/workflows/ci.yml`. After changing a constraint, regenerate the lock files in
  a rendered project (`terraform init -backend=false -upgrade && terraform providers lock
  -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=darwin_amd64
  -platform=windows_amd64` in `bootstrap` and each `envs/*`) and copy them back.
- **Terraform in the template**: `infra/terraform/modules/*` and the lock files are in
  `_copy_without_render`; cookiecutter values belong only in each root's
  `terraform.tfvars`. RAG's Terraform lives in `search.tf` files the hook deletes.
