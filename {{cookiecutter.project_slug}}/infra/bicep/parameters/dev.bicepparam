using '../main.bicep'

// Legacy monolithic deployment parameters.
// Preferred per-service workflow uses infra/bicep/services + infra/scripts.

// Non-secret values are safe to keep here. Secrets and image tags are read from
// environment variables (set by the CI pipeline), never committed.

param environmentName = 'dev'
param resourcePrefix = '{{ cookiecutter.resource_prefix }}'
param location = '{{ cookiecutter.azure_location }}'
param tenantId = '{{ cookiecutter.entra_tenant_id }}'

param apiImage = readEnvironmentVariable('API_IMAGE', 'REPLACE_ME.azurecr.io/{{ cookiecutter.project_slug }}-api:latest')
param webImage = readEnvironmentVariable('WEB_IMAGE', 'REPLACE_ME.azurecr.io/{{ cookiecutter.project_slug }}-web:latest')

param sqlAdminLogin = '{{ cookiecutter.resource_prefix }}admin'
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')

param entraBackendClientId = '{{ cookiecutter.backend_client_id }}'
param entraBackendAppIdUri = '{{ cookiecutter.backend_app_id_uri }}'
param entraFrontendClientId = '{{ cookiecutter.frontend_client_id }}'
param adminGroupId = readEnvironmentVariable('ADMIN_GROUP_ID', '')

param aiProvider = 'foundry'
param authMode = 'entra'
param foundryEndpoint = readEnvironmentVariable('AZURE_AI_FOUNDRY_ENDPOINT', '')
param enableSearch = {{ 'true' if cookiecutter.enable_ai_search == 'yes' else 'false' }}
