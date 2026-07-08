targetScope = 'resourceGroup'

// Service entrypoint name matches the deployment workflow's "postgres" step.
// It currently reuses the existing Azure SQL module for the app database.

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('SQL administrator login name.')
param sqlAdminLogin string = '${resourcePrefix}admin'

@description('SQL administrator password (provide via secure pipeline or env var).')
@secure()
param sqlAdminPassword string

@description('Entra admin object id (managed identity principal id or group object id).')
param entraAdminObjectId string = ''

@description('Entra admin display name.')
param entraAdminLogin string = 'sql-admins'

@description('Database name.')
param databaseName string = 'appdb'

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

module sql '../modules/sql.bicep' = {
  name: 'postgres-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    entraAdminObjectId: entraAdminObjectId
    entraAdminLogin: entraAdminLogin
    databaseName: databaseName
  }
}

output serverName string = sql.outputs.serverName
output serverFqdn string = sql.outputs.serverFqdn
output databaseName string = sql.outputs.databaseName
