targetScope = 'resourceGroup'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Principal id of the managed identity that reads secrets.')
param appPrincipalId string

@description('Optional Application Insights connection string to seed as appinsights-connection-string.')
@secure()
param appInsightsConnectionString string = ''

@description('Object id of the CD pipeline identity (granted Key Vault Secrets Officer). Empty to skip.')
param secretsOfficerPrincipalId string = ''

@description('Optional additional seed secrets (name -> value).')
@secure()
param additionalSeedSecrets object = {}

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

// Infra seeds only the values it owns. Application secrets such as
// `database-url` are written by scripts/cd.sh from GitHub environment secrets, so
// re-running this deployment never overwrites them.
var builtInSeedSecrets = empty(appInsightsConnectionString)
  ? {}
  : {
      'appinsights-connection-string': appInsightsConnectionString
    }

var seedSecrets = union(builtInSeedSecrets, additionalSeedSecrets)

module keyVault '../modules/key-vault.bicep' = {
  name: 'key-vault-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: appPrincipalId
    secretsOfficerPrincipalId: secretsOfficerPrincipalId
    seedSecrets: seedSecrets
  }
}

output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output keyVaultId string = keyVault.outputs.keyVaultId
