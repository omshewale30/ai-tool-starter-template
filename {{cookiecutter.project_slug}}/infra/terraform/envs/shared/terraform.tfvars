prefix   = "{{ cookiecutter.resource_prefix }}"
location = "{{ cookiecutter.azure_location }}"

tags = {
  application = "{{ cookiecutter.project_slug }}"
}

# Object id of the CI/CD service principal (GitHub OIDC), to build and push images:
# deploy_principal_id = "00000000-0000-0000-0000-000000000000"
