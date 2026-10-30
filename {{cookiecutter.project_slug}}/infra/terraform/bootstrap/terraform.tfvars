prefix   = "{{ cookiecutter.resource_prefix }}"
location = "{{ cookiecutter.azure_location }}"

tags = {
  application = "{{ cookiecutter.project_slug }}"
}

# Everyone who runs Terraform needs state access. Default: whoever applies. For a team,
# list an Entra group everyone who applies belongs to (include yourself):
# state_contributor_principal_ids = { operators = "00000000-0000-0000-0000-000000000000" }
