// Optional Azure AI Search service for RAG scenarios. Grants the app's managed
// identity the "Search Index Data Reader" role for keyless query access.
@description('Prefix used for resource names.')
param namePrefix string
param location string = resourceGroup().location
param tags object = {}

@description('Principal id of the managed identity that queries the index.')
param appPrincipalId string

var searchName = take('srch-${replace(namePrefix, '-', '')}${uniqueString(resourceGroup().id)}', 60)

// Built-in role: Search Index Data Reader
var searchReaderRoleId = '1407120a-92aa-4202-b7e9-c0e197c71c8f'

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchName
  location: location
  tags: tags
  sku: {
    name: 'basic'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

resource searchReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, appPrincipalId, searchReaderRoleId)
  scope: search
  properties: {
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchReaderRoleId)
  }
}

output searchEndpoint string = 'https://${search.name}.search.windows.net'
output searchName string = search.name
