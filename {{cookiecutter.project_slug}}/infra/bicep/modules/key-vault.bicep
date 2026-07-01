// Azure Key Vault with RBAC authorization. Grants the app's managed identity the
// "Key Vault Secrets User" role so containers can read secrets via Key Vault
// references — no secrets are stored in app settings or source.
@description('Prefix used for resource names.')
param namePrefix string
param location string = resourceGroup().location
param tags object = {}

@description('Principal id of the managed identity that reads secrets.')
param appPrincipalId string

@description('Optional seed secrets to create (name -> value). Prefer pipeline-set secrets.')
@secure()
param seedSecrets object = {}

var keyVaultName = take('kv-${replace(namePrefix, '-', '')}${uniqueString(resourceGroup().id)}', 24)

// Built-in role: Key Vault Secrets User
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource secretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appPrincipalId, secretsUserRoleId)
  scope: keyVault
  properties: {
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
  }
}

resource secrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [
  for item in items(seedSecrets): {
    parent: keyVault
    name: item.key
    properties: {
      value: item.value
    }
  }
]

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultId string = keyVault.id
