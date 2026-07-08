targetScope = 'resourceGroup'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Principal id of the managed identity that accesses blobs.')
param appPrincipalId string

@description('Blob container name for uploads.')
param containerName string = 'uploads'

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

module storage '../modules/storage.bicep' = {
  name: 'storage-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: appPrincipalId
    containerName: containerName
  }
}

output storageAccountName string = storage.outputs.storageAccountName
output blobEndpoint string = storage.outputs.blobEndpoint
output containerName string = storage.outputs.containerName
