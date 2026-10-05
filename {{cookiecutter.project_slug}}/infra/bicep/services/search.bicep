targetScope = 'resourceGroup'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Principal id of the managed identity that queries search.')
param appPrincipalId string

@description('Existing storage account that holds the documents container.')
param storageAccountName string

@description('Blob container the indexer reads.')
param documentsContainerName string = 'documents'

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

module search '../modules/search.bicep' = {
  name: 'search-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: appPrincipalId
    storageAccountName: storageAccountName
    documentsContainerName: documentsContainerName
  }
}

output searchName string = search.outputs.searchName
output searchEndpoint string = search.outputs.searchEndpoint
output searchPrincipalId string = search.outputs.searchPrincipalId
output storageAccountId string = search.outputs.storageAccountId
output documentsContainerName string = search.outputs.documentsContainerName
