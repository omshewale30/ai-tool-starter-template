// Azure SQL logical server + database.
//
// Uses Microsoft Entra authentication (an Entra admin) so the app can connect
// with its managed identity — no SQL password in the app. A SQL admin login is
// still created because Azure requires one; keep its password in Key Vault /
// pipeline secrets and avoid using it from the app.
@description('Prefix used for resource names.')
param namePrefix string
param location string = resourceGroup().location
param tags object = {}

@description('SQL administrator login name.')
param sqlAdminLogin string

@description('SQL administrator password (store in Key Vault / pipeline secret).')
@secure()
param sqlAdminPassword string

@description('Entra admin object id (e.g. the app managed identity or a group).')
param entraAdminObjectId string = ''

@description('Entra admin display name.')
param entraAdminLogin string = 'sql-admins'

param databaseName string = 'appdb'

var serverName = 'sql-${namePrefix}-${uniqueString(resourceGroup().id)}'

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: empty(entraAdminObjectId)
      ? null
      : {
          administratorType: 'ActiveDirectory'
          principalType: 'Application'
          login: entraAdminLogin
          sid: entraAdminObjectId
          tenantId: subscription().tenantId
          azureADOnlyAuthentication: false
        }
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: 'GP_S_Gen5_1'
    tier: 'GeneralPurpose'
  }
  properties: {
    autoPauseDelay: 60
    minCapacity: json('0.5')
  }
}

// Allow other Azure services (e.g. Container Apps) to reach the server.
resource allowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output serverName string = sqlServer.name
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = database.name
