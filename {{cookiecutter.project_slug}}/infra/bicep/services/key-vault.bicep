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

@description('Optional SQL admin password to seed as sql-admin-password.')
@secure()
param sqlAdminPassword string = ''

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

var builtInSeedSecrets = union(
  empty(appInsightsConnectionString)
    ? {}
    : {
        'appinsights-connection-string': appInsightsConnectionString
      },
  empty(sqlAdminPassword)
    ? {}
    : {
        'sql-admin-password': sqlAdminPassword
      }
)

var seedSecrets = union(builtInSeedSecrets, additionalSeedSecrets)

module keyVault '../modules/key-vault.bicep' = {
  name: 'key-vault-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    appPrincipalId: appPrincipalId
    seedSecrets: seedSecrets
  }
}

output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output keyVaultId string = keyVault.outputs.keyVaultId
