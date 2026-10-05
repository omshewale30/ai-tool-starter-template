targetScope = 'resourceGroup'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Microsoft Entra tenant id.')
param tenantId string = '{{ cookiecutter.entra_tenant_id }}'

@description('Backend container image, e.g. myacr.azurecr.io/api:sha.')
param image string

@description('Container Apps managed environment resource id.')
param environmentId string

@description('Container Apps managed environment default domain.')
param defaultDomain string

@description('User-assigned managed identity resource id.')
param userAssignedIdentityId string

@description('Client id for the user-assigned managed identity.')
param userAssignedIdentityClientId string

@description('ACR login server, e.g. myacr.azurecr.io.')
param registryServer string

@description('Storage blob endpoint URL.')
param storageBlobEndpoint string

@description('Storage container name for uploads.')
param storageContainerName string

@description('Key Vault URI, e.g. https://mykv.vault.azure.net/.')
param keyVaultUri string

@description('Entra backend (API) app registration client id.')
param entraBackendClientId string = '{{ cookiecutter.backend_client_id }}'

@description('Entra backend app id URI (expected token audience).')
param entraBackendAppIdUri string = '{{ cookiecutter.backend_app_id_uri }}'

@description('Group object id (or app role) granting admin access.')
param adminGroupId string = ''

@description('AI provider: mock or foundry.')
@allowed(['mock', 'foundry'])
param aiProvider string = 'foundry'

@description('Auth mode: entra or disabled. NEVER use disabled outside local dev.')
@allowed(['entra', 'disabled'])
param authMode string = 'entra'

@description('Azure AI Foundry endpoint (used when aiProvider=foundry).')
param foundryEndpoint string = ''

@description('Azure AI Foundry model deployment name.')
param foundryDeploymentName string = 'gpt-4o-mini'

@description('Azure AI Foundry API version.')
param foundryApiVersion string = '2024-08-01-preview'

@description('Optional Azure AI Search endpoint.')
param searchEndpoint string = ''

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

var apiAppName = 'ca-${namePrefix}-api'
var webAppName = 'ca-${namePrefix}-web'
var apiFqdn = '${apiAppName}.${defaultDomain}'
var apiUrl = 'https://${apiFqdn}'
var webOrigin = 'https://${webAppName}.${defaultDomain}'

// DATABASE_URL comes from the Key Vault secret `database-url`, owned by scripts/cd.sh.
var databaseUrlSecretUrl = '${keyVaultUri}secrets/database-url'
var appInsightsSecretUrl = '${keyVaultUri}secrets/appinsights-connection-string'

module apiApp '../modules/container-app.bicep' = {
  name: 'api-app-${namePrefix}'
  params: {
    name: apiAppName
    location: location
    tags: tags
    environmentId: environmentId
    userAssignedIdentityId: userAssignedIdentityId
    registryServer: registryServer
    image: image
    targetPort: 8000
    external: true
    envVars: [
      { name: 'ENVIRONMENT', value: environmentName }
      { name: 'AI_PROVIDER', value: aiProvider }
      { name: 'AUTH_MODE', value: authMode }
      { name: 'AZURE_TENANT_ID', value: tenantId }
      { name: 'ENTRA_BACKEND_CLIENT_ID', value: entraBackendClientId }
      { name: 'ENTRA_BACKEND_APP_ID_URI', value: entraBackendAppIdUri }
      { name: 'ADMIN_GROUP_ID', value: adminGroupId }
      { name: 'CORS_ALLOW_ORIGINS', value: webOrigin }
      { name: 'AZURE_STORAGE_ACCOUNT_URL', value: storageBlobEndpoint }
      { name: 'AZURE_STORAGE_CONTAINER', value: storageContainerName }
      { name: 'AZURE_AI_FOUNDRY_ENDPOINT', value: foundryEndpoint }
      { name: 'AZURE_AI_FOUNDRY_DEPLOYMENT_NAME', value: foundryDeploymentName }
      { name: 'AZURE_AI_FOUNDRY_API_VERSION', value: foundryApiVersion }
      { name: 'AZURE_SEARCH_ENDPOINT', value: searchEndpoint }
      { name: 'AZURE_CLIENT_ID', value: userAssignedIdentityClientId }
    ]
    secretRefs: [
      { name: 'appinsights-connection-string', keyVaultUrl: appInsightsSecretUrl }
      { name: 'database-url', keyVaultUrl: databaseUrlSecretUrl }
    ]
    secretEnvVars: [
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights-connection-string' }
      { name: 'DATABASE_URL', secretRef: 'database-url' }
    ]
  }
}

output apiAppName string = apiApp.outputs.name
output apiFqdn string = apiApp.outputs.fqdn
output apiUrl string = apiUrl
