// Azure AI Search for RAG, built around a Blob indexer:
//   - a `documents` container in the app's storage account (drop files there);
//   - the search service's system-assigned identity, granted Storage Blob Data
//     Reader on the account so the indexer reads documents keylessly;
//   - the app's managed identity granted Search Index Data Reader to query.
// The index, data source, skillset and indexer are data-plane objects Bicep cannot
// create: infra/scripts/setup-search-index.sh does that.
//
// Hand-off (not done here, because UNC owns the resource): the search service's
// identity also needs "Cognitive Services OpenAI User" on UNC's Azure OpenAI
// resource, to embed chunks and queries. See docs/rag.md.
@description('Prefix used for resource names.')
param namePrefix string
param location string = resourceGroup().location
param tags object = {}

@description('Principal id of the app managed identity that queries the index.')
param appPrincipalId string

@description('Existing storage account (infra/bicep/modules/storage.bicep) that holds documents.')
param storageAccountName string

@description('Blob container the indexer reads.')
param documentsContainerName string = 'documents'

@description('Search SKU. Basic supports vector search and is enough for a prototype.')
param skuName string = 'basic'

var searchName = take('srch-${replace(namePrefix, '-', '')}${uniqueString(resourceGroup().id)}', 60)

// Built-in roles
var searchIndexReaderRoleId = '1407120a-92aa-4202-b7e9-c0e197c71c8f'
var blobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    // Entra ID (RBAC) and keys both accepted; the app and indexer use Entra only.
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: storage
  name: 'default'
}

resource documents 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: documentsContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource appSearchReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, appPrincipalId, searchIndexReaderRoleId)
  scope: search
  properties: {
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexReaderRoleId)
  }
}

resource indexerBlobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, searchName, blobDataReaderRoleId)
  scope: storage
  properties: {
    principalId: search.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataReaderRoleId)
  }
}

output searchEndpoint string = 'https://${search.name}.search.windows.net'
output searchName string = search.name
output searchPrincipalId string = search.identity.principalId
output storageAccountId string = storage.id
output documentsContainerName string = documents.name
