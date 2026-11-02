# ADR 0007: Terraform for infrastructure

- Status: Accepted
- Date: 2026-10-30

## Context

Infrastructure was Bicep, deployed by one shell script per resource, with outputs
passed between scripts through a local JSON file. Nothing recorded what was deployed,
nothing detected drift, and a second environment meant repeating every step by hand.
Container apps could not be re-deployed without resetting the image CD had rolled out.

## Decision

Terraform (≥ 1.11, `hashicorp/azurerm` 5.x) in `infra/terraform`:

| Path | Holds | State |
| --- | --- | --- |
| `bootstrap/` | State storage account; resource provider registration | local, once per subscription |
| `modules/<resource>/` | One small module per Azure concern | — |
| `modules/app-stack/` | One whole environment, composed from the modules | — |
| `envs/shared/` | The container registry every environment pulls from | `shared.tfstate` |
| `envs/dev/`, `envs/prod/` | One `app-stack` call; settings in `terraform.tfvars` | `<env>.tfstate` |

- **Thin environment roots.** An environment differs from another only in its tfvars,
  so dev and prod cannot drift structurally, and prod gets every change dev was tested
  with.
- **One shared registry.** CI publishes each image once; CD promotes the same digest
  through environments ([0005](0005-publish-once-runtime-config.md)).
- **Remote state** in Azure Storage with Entra ID auth only (no shared keys), blob
  versioning and soft delete; blob leases lock it.
- **Secrets stay out of state.** The Postgres admin password is an ephemeral value
  written through write-only arguments (`administrator_password_wo`, `value_wo`) to
  the server and to Key Vault.
- **Infra creates, CD owns** stays: the container app module ignores image and env,
  so `terraform apply` is always safe on running apps.
- **Applied by an operator**, never by CI/CD ([0006](0006-fo-ai-script-contract.md)).
  CI runs `terraform fmt -check` and `validate` on every root (`scripts/ci.sh infra`).
- **Plain azurerm modules**, not Azure Verified Modules: fewer providers and no
  telemetry, readable by anyone who knows azurerm.
- **Not automated**: Entra app registrations, the GitHub OIDC identity, and access to
  UNC's Azure OpenAI.

## Consequences

- Drift shows up in `terraform plan`. Changes are reviewed as plans before they apply.
- Adding an environment is a new `envs/<name>` directory and a tfvars file.
- Operators need subscription-level Owner (or Contributor + User Access Administrator).
- Running applies from CI later means giving the CI identity state access and role
  assignment rights, and amending ADR 0006.
