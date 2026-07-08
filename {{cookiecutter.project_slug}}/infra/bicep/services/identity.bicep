targetScope = 'resourceGroup'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

module identity '../modules/identity.bicep' = {
  name: 'identity-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
  }
}

output id string = identity.outputs.id
output principalId string = identity.outputs.principalId
output clientId string = identity.outputs.clientId
