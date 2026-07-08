// LEGACY top-level deployment for {{ cookiecutter.project_name }}.
//
// This monolithic subscription-scoped template creates the resource group and
// all services in one run. It is kept for backward compatibility.
//
// Preferred path: deploy one service at a time with group-scoped entrypoints in
// infra/bicep/services and scripts in infra/scripts.
//
// Legacy deploy command:
//   az deployment sub create \
//     --location {{ cookiecutter.azure_location }} \
//     --template-file infra/bicep/main.bicep \
//     --parameters infra/bicep/parameters/dev.bicepparam
targetScope = 'subscription'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Azure region.')
param location string = '{{ cookiecutter.azure_location }}'

@allowed(['dev', 'prod'])
param environmentName string = 'dev'

@description('Microsoft Entra tenant id.')
param tenantId string = '{{ cookiecutter.entra_tenant_id }}'

@description('Backend container image, e.g. myacr.azurecr.io/api:sha.')
param apiImage string

@description('Frontend container image, e.g. myacr.azurecr.io/web:sha.')
param webImage string

@description('SQL administrator login name.')
param sqlAdminLogin string = '${resourcePrefix}admin'

@description('SQL administrator password. Supply via a pipeline secret, never in source.')
@secure()
param sqlAdminPassword string

@description('Entra backend (API) app registration client id.')
param entraBackendClientId string = '{{ cookiecutter.backend_client_id }}'

@description('Entra backend app id URI (expected token audience).')
param entraBackendAppIdUri string = '{{ cookiecutter.backend_app_id_uri }}'

@description('Entra frontend (SPA) app registration client id.')
param entraFrontendClientId string = '{{ cookiecutter.frontend_client_id }}'

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
param foundryDeploymentName string = 'gpt-4o-mini'
param foundryApiVersion string = '2024-08-01-preview'

@description('Provision Azure AI Search.')
param enableSearch bool = false

var namePrefix = '${resourcePrefix}-${environmentName}'
var tags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${namePrefix}'
  location: location
  tags: tags
}

module identity 'modules/identity.bicep' = {
  scope: rg
  name: 'identity'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
  }
}

module observability 'modules/observability.bicep' = {
  scope: rg
  name: 'observability'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
  }
}

module registry 'modules/registry.bicep' = {
  scope: rg
  name: 'registry'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: identity.outputs.principalId
  }
}

module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'storage'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: identity.outputs.principalId
  }
}

module sql 'modules/sql.bicep' = {
  scope: rg
  name: 'sql'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    entraAdminObjectId: identity.outputs.principalId
    entraAdminLogin: 'id-${namePrefix}'
  }
}

module keyVault 'modules/key-vault.bicep' = {
  scope: rg
  name: 'keyVault'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: identity.outputs.principalId
    seedSecrets: {
      'appinsights-connection-string': observability.outputs.appInsightsConnectionString
      'sql-admin-password': sqlAdminPassword
    }
  }
}

module search 'modules/search.bicep' = if (enableSearch) {
  scope: rg
  name: 'search'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: identity.outputs.principalId
  }
}

module env 'modules/container-apps-env.bicep' = {
  scope: rg
  name: 'containerAppsEnv'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    logAnalyticsName: observability.outputs.logAnalyticsName
  }
}

// Precompute FQDNs from the environment default domain to avoid a circular
// dependency between the frontend and backend apps.
var apiAppName = 'ca-${namePrefix}-api'
var webAppName = 'ca-${namePrefix}-web'
var apiFqdn = '${apiAppName}.${env.outputs.defaultDomain}'
var webFqdn = '${webAppName}.${env.outputs.defaultDomain}'
var apiBaseUrl = 'https://${apiFqdn}'
var webOrigin = 'https://${webFqdn}'

var databaseUrl = 'mssql+pyodbc://@${sql.outputs.serverFqdn}:1433/${sql.outputs.databaseName}?driver=ODBC+Driver+18+for+SQL+Server&Authentication=ActiveDirectoryMsi&Encrypt=yes'
var appInsightsSecretUrl = '${keyVault.outputs.keyVaultUri}secrets/appinsights-connection-string'

module apiApp 'modules/container-app.bicep' = {
  scope: rg
  name: 'apiApp'
  params: {
    name: apiAppName
    location: location
    tags: tags
    environmentId: env.outputs.environmentId
    userAssignedIdentityId: identity.outputs.id
    registryServer: registry.outputs.loginServer
    image: apiImage
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
      { name: 'DATABASE_URL', value: databaseUrl }
      { name: 'AZURE_STORAGE_ACCOUNT_URL', value: storage.outputs.blobEndpoint }
      { name: 'AZURE_STORAGE_CONTAINER', value: storage.outputs.containerName }
      { name: 'AZURE_AI_FOUNDRY_ENDPOINT', value: foundryEndpoint }
      { name: 'AZURE_AI_FOUNDRY_DEPLOYMENT_NAME', value: foundryDeploymentName }
      { name: 'AZURE_AI_FOUNDRY_API_VERSION', value: foundryApiVersion }
      { name: 'AZURE_SEARCH_ENDPOINT', value: search.?outputs.searchEndpoint ?? '' }
      // Tells DefaultAzureCredential which user-assigned identity to use.
      { name: 'AZURE_CLIENT_ID', value: identity.outputs.clientId }
    ]
    secretRefs: [
      { name: 'appinsights-connection-string', keyVaultUrl: appInsightsSecretUrl }
    ]
    secretEnvVars: [
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights-connection-string' }
    ]
  }
}

module webApp 'modules/container-app.bicep' = {
  scope: rg
  name: 'webApp'
  params: {
    name: webAppName
    location: location
    tags: tags
    environmentId: env.outputs.environmentId
    userAssignedIdentityId: identity.outputs.id
    registryServer: registry.outputs.loginServer
    image: webImage
    targetPort: 3000
    external: true
    envVars: [
      // NOTE: NEXT_PUBLIC_* values are inlined at image BUILD time. Set these as
      // build args in CI; the runtime values below are a convenience/fallback.
      { name: 'NEXT_PUBLIC_API_BASE_URL', value: apiBaseUrl }
      { name: 'NEXT_PUBLIC_AUTH_DISABLED', value: 'false' }
      { name: 'NEXT_PUBLIC_ENTRA_CLIENT_ID', value: entraFrontendClientId }
      { name: 'NEXT_PUBLIC_ENTRA_TENANT_ID', value: tenantId }
      { name: 'NEXT_PUBLIC_ENTRA_REDIRECT_URI', value: webOrigin }
      { name: 'NEXT_PUBLIC_ENTRA_API_SCOPE', value: '${entraBackendAppIdUri}/access_as_user' }
    ]
  }
}

output resourceGroupName string = rg.name
output apiUrl string = apiBaseUrl
output webUrl string = webOrigin
output apiAppName string = apiAppName
output webAppName string = webAppName
output registryLoginServer string = registry.outputs.loginServer
output managedIdentityClientId string = identity.outputs.clientId
output keyVaultName string = keyVault.outputs.keyVaultName
