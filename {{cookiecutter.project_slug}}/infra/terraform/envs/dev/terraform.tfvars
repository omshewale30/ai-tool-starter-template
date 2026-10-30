prefix      = "{{ cookiecutter.resource_prefix }}"
environment = "dev"
location    = "{{ cookiecutter.azure_location }}"

tags = {
  application = "{{ cookiecutter.project_slug }}"
}

# Object id of the CI/CD service principal (GitHub OIDC). Granted Contributor on the
# resource group and Key Vault Secrets Officer. See docs/runbook.md.
# deploy_principal_id = "00000000-0000-0000-0000-000000000000"

# Who runs Terraform (Key Vault Secrets Officer). Default: whoever applies. For a
# team, list an Entra group everyone who applies belongs to:
# operator_principal_ids = { operators = "00000000-0000-0000-0000-000000000000" }

# Initial web env (CD owns it after the first deploy).
entra_tenant_id     = "{{ cookiecutter.entra_tenant_id }}"
entra_web_client_id = "{{ cookiecutter.frontend_client_id }}"
entra_api_scope     = "{{ cookiecutter.backend_app_id_uri }}/access_as_user"

# Prototype sizing: Burstable Postgres, LRS storage, 1-3 replicas per app.
