// Azure Container Registry. Grants the app's managed identity "AcrPull" so Container
// Apps pull images without admin credentials, and optionally the CI/CD pipeline
// identity "AcrPush" so scripts/publish.sh can build into it (az acr build).
@description('Prefix used for resource names.')
param namePrefix string
param location string = resourceGroup().location
param tags object = {}

@description('Principal id of the managed identity that pulls images.')
param appPrincipalId string

@description('Object id of the CI/CD pipeline identity that pushes images. Empty to skip.')
param pipelinePrincipalId string = ''

var registryName = take('acr${replace(namePrefix, '-', '')}${uniqueString(resourceGroup().id)}', 50)

// Built-in roles: AcrPull / AcrPush
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var acrPushRoleId = '8311e382-0749-4cb8-b61a-304f252e45ec'

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, appPrincipalId, acrPullRoleId)
  scope: registry
  properties: {
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
  }
}

resource acrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(pipelinePrincipalId)) {
  name: guid(registry.id, pipelinePrincipalId, acrPushRoleId)
  scope: registry
  properties: {
    principalId: pipelinePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPushRoleId)
  }
}

output registryName string = registry.name
output loginServer string = registry.properties.loginServer
