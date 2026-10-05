targetScope = 'resourceGroup'

// The web Container App: the only public endpoint. It serves the Next.js app and
// forwards /api/* to the API's internal address (BACKEND_ORIGIN).
//
// Creates the app shell. After the first deploy, scripts/cd.sh owns the image and the
// env (deploy/env-contract.json), re-deriving BACKEND_ORIGIN from the API app the same
// way this template does.

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

@description('ACR login server, e.g. myacr.azurecr.io.')
param registryServer string

@description('Entra tenant id.')
param tenantId string = '{{ cookiecutter.entra_tenant_id }}'

@description('Client id of the web (SPA) app registration.')
param entraClientId string = '{{ cookiecutter.frontend_client_id }}'

@description('Delegated API scope the web requests, e.g. api://<api client id>/access_as_user.')
param entraApiScope string = '{{ cookiecutter.backend_app_id_uri }}/access_as_user'

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

// Read the API's real ingress FQDN: with internal ingress it is
// <app>.internal.<environment domain>, so it must not be assembled from strings.
resource apiApp 'Microsoft.App/containerApps@2024-03-01' existing = {
  name: 'ca-${namePrefix}-api'
}

module webApp '../modules/container-app.bicep' = {
  name: 'web-app-${namePrefix}'
  params: {
    name: 'ca-${namePrefix}-web'
    location: location
    tags: tags
    environmentId: environmentId
    userAssignedIdentityId: userAssignedIdentityId
    registryServer: registryServer
    image: image
    targetPort: 3000
    external: true
    livenessPath: '/healthz'
    readinessPath: '/healthz'
    envVars: [
      { name: 'BACKEND_ORIGIN', value: 'https://${apiApp.properties.configuration.ingress.fqdn}' }
      { name: 'ENTRA_CLIENT_ID', value: entraClientId }
      { name: 'ENTRA_TENANT_ID', value: tenantId }
      { name: 'ENTRA_API_SCOPE', value: entraApiScope }
    ]
  }
}

output webAppName string = webApp.outputs.name
output webFqdn string = webApp.outputs.fqdn
output webUrl string = 'https://${webApp.outputs.fqdn}'
