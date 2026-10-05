targetScope = 'resourceGroup'

// The API Container App: internal ingress only. Browsers reach it through the web
// app's /api/* forwarder, which is pointed at this app's internal FQDN.
//
// Creates the app shell. After the first deploy, scripts/cd.sh owns the image and the
// application env (deploy/env-contract.json); this template owns identity, registry,
// ingress, probes, Key Vault references, and scale. Its env holds only names the
// contract treats as infra-owned or secret-bound, so CD never has to prune them.

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Bootstrap image; scripts/cd.sh replaces it with the published digest.')
param image string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Container Apps managed environment resource id.')
param environmentId string

@description('User-assigned managed identity resource id.')
param userAssignedIdentityId string

@description('Client id of the user-assigned identity (DefaultAzureCredential uses it).')
param userAssignedIdentityClientId string

@description('ACR login server, e.g. myacr.azurecr.io.')
param registryServer string

@description('Key Vault URI, e.g. https://mykv.vault.azure.net/.')
param keyVaultUri string

@description('Bind APPLICATIONINSIGHTS_CONNECTION_STRING (the Key Vault secret must exist).')
param enableAppInsights bool = true

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

// database-url is owned by scripts/cd.sh (from the DATABASE_URL GitHub secret);
// appinsights-connection-string is seeded by infra (deploy-key-vault.sh).
var databaseSecret = [{ name: 'database-url', keyVaultUrl: '${keyVaultUri}secrets/database-url' }]
var appInsightsSecret = enableAppInsights
  ? [{ name: 'appinsights-connection-string', keyVaultUrl: '${keyVaultUri}secrets/appinsights-connection-string' }]
  : []
var appInsightsEnv = enableAppInsights
  ? [{ name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights-connection-string' }]
  : []

module apiApp '../modules/container-app.bicep' = {
  name: 'api-app-${namePrefix}'
  params: {
    name: 'ca-${namePrefix}-api'
    location: location
    tags: tags
    environmentId: environmentId
    userAssignedIdentityId: userAssignedIdentityId
    registryServer: registryServer
    image: image
    targetPort: 8000
    external: false
    livenessPath: '/health/live'
    readinessPath: '/health/ready'
    envVars: [
      // Infra-owned (deploy/env-contract.json `infra`): which identity the SDKs use.
      { name: 'AZURE_CLIENT_ID', value: userAssignedIdentityClientId }
    ]
    secretRefs: concat(databaseSecret, appInsightsSecret)
    secretEnvVars: concat([{ name: 'DATABASE_URL', secretRef: 'database-url' }], appInsightsEnv)
  }
}

output apiAppName string = apiApp.outputs.name
// The internal FQDN (<app>.internal.<environment domain>); the web app's BACKEND_ORIGIN.
output apiFqdn string = apiApp.outputs.fqdn
