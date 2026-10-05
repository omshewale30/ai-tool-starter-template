targetScope = 'resourceGroup'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Principal id of the managed identity that pulls images.')
param appPrincipalId string

@description('Object id of the CI/CD pipeline identity (granted AcrPush). Empty to skip.')
param pipelinePrincipalId string = ''

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

module registry '../modules/registry.bicep' = {
  name: 'registry-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: appPrincipalId
    pipelinePrincipalId: pipelinePrincipalId
  }
}

output registryName string = registry.outputs.registryName
output loginServer string = registry.outputs.loginServer
