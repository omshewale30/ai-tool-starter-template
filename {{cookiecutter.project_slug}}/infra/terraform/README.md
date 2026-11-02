# Terraform

All Azure infrastructure for {{ cookiecutter.project_name }}. Why it looks like this:
[ADR 0007](../../docs/adr/0007-terraform-infrastructure.md). How to run it the first
time: [runbook](../../docs/runbook.md#3-azure-resources-terraform).

```
infra/terraform/
├── backend.hcl          # state account details (from bootstrap), shared by every root
├── bootstrap/           # state storage + provider registration; local state, run once
├── modules/
│   ├── naming/          # every resource name, derived the same way in every root
│   ├── app-stack/       # one whole environment, composed from the modules below
│   ├── identity/  observability/  key-vault/  storage/  postgres/
│   ├── container-apps-env/  container-app/  registry/  search/
└── envs/
    ├── shared/          # container registry (all environments pull from it)
    ├── dev/             # module "app" { source = "../../modules/app-stack" } + tfvars
    └── prod/            # same, production-sized tfvars
```

Apply order: `bootstrap` → `envs/shared` → `envs/<env>`.

```bash
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
make tf-init tf-plan ENV=dev     # review the plan
make tf-apply ENV=dev
```

## Rules

- **Environments differ only in `terraform.tfvars`.** Structural changes go in
  `modules/app-stack` (or a resource module), so every environment gets them.
- **Never change container app image or env here.** CD owns both and the
  `container-app` module ignores them; use `deploy/env-contract.json`.
- **No secrets in variables or state.** Generate them as ephemeral values and write
  them with write-only (`*_wo`) arguments, as `modules/app-stack/secrets.tf` does.
- **Commit `.terraform.lock.hcl`** in each root. After changing a provider constraint,
  run `terraform init -upgrade` and
  `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64 -platform=windows_amd64`.
- `scripts/ci.sh infra` (in `make check` and CI) runs `terraform fmt -check` and
  `validate` on every root without touching Azure.
