// Azure Key Vault with RBAC authorization. Grants the app's managed identity the
// "Key Vault Secrets User" role so containers can read secrets via Key Vault
// references — no secrets are stored in app settings or source. Optionally grants
// the deploy pipeline's identity "Key Vault Secrets Officer" so `scripts/cd.sh`
// can write the secrets it owns (e.g. database-url).
@description('Prefix used for resource names.')
param namePrefix string
param location string = resourceGroup().location
param tags object = {}

@description('Principal id of the managed identity that reads secrets.')
param appPrincipalId string

@description('Object id of the CD pipeline identity that writes secrets. Empty to skip.')
param pipelinePrincipalId string = ''

@description('Optional seed secrets to create (name -> value). Only for values infra owns.')
@secure()
param seedSecrets object = {}

var keyVaultName = take('kv-${replace(namePrefix, '-', '')}${uniqueString(resourceGroup().id)}', 24)

// Built-in roles: Key Vault Secrets User / Key Vault Secrets Officer
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var secretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

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

resource secretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(pipelinePrincipalId)) {
  name: guid(keyVault.id, pipelinePrincipalId, secretsOfficerRoleId)
  scope: keyVault
  properties: {
    principalId: pipelinePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsOfficerRoleId)
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
