targetScope = 'resourceGroup'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Microsoft Entra tenant id.')
param tenantId string = '{{ cookiecutter.entra_tenant_id }}'

@description('Frontend container image, e.g. myacr.azurecr.io/web:sha.')
param image string

@description('Container Apps managed environment resource id.')
param environmentId string

@description('Container Apps managed environment default domain.')
param defaultDomain string

@description('User-assigned managed identity resource id.')
param userAssignedIdentityId string

@description('ACR login server, e.g. myacr.azurecr.io.')
param registryServer string

@description('Entra frontend (SPA) app registration client id.')
param entraFrontendClientId string = '{{ cookiecutter.frontend_client_id }}'

@description('Entra backend app id URI used to request API scope.')
param entraBackendAppIdUri string = '{{ cookiecutter.backend_app_id_uri }}'

@description('Set true only for local/dev troubleshooting.')
param authDisabled bool = false

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
var apiBaseUrl = 'https://${apiAppName}.${defaultDomain}'
var webOrigin = 'https://${webAppName}.${defaultDomain}'

module webApp '../modules/container-app.bicep' = {
  name: 'web-app-${namePrefix}'
  params: {
    name: webAppName
    location: location
    tags: tags
    environmentId: environmentId
    userAssignedIdentityId: userAssignedIdentityId
    registryServer: registryServer
    image: image
    targetPort: 3000
    external: true
    envVars: [
      { name: 'NEXT_PUBLIC_API_BASE_URL', value: apiBaseUrl }
      { name: 'NEXT_PUBLIC_AUTH_DISABLED', value: authDisabled ? 'true' : 'false' }
      { name: 'NEXT_PUBLIC_ENTRA_CLIENT_ID', value: entraFrontendClientId }
      { name: 'NEXT_PUBLIC_ENTRA_TENANT_ID', value: tenantId }
      { name: 'NEXT_PUBLIC_ENTRA_REDIRECT_URI', value: webOrigin }
      { name: 'NEXT_PUBLIC_ENTRA_API_SCOPE', value: '${entraBackendAppIdUri}/access_as_user' }
    ]
  }
}

output webAppName string = webApp.outputs.name
output webFqdn string = webApp.outputs.fqdn
output webUrl string = webOrigin
output apiBaseUrl string = apiBaseUrl
