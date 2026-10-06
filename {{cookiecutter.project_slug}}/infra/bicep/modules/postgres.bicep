// Azure Database for PostgreSQL Flexible Server + the application database.
//
// Password authentication: the admin password is supplied at deploy time (never
// committed), and the app receives a full DATABASE_URL through the Key Vault
// secret `database-url`, which `scripts/cd.sh` owns (see docs/runbook.md).
// Keep the password URL-safe (letters and digits) because it is embedded in
// that URL.
@description('Prefix used for resource names.')
param namePrefix string
param location string = resourceGroup().location
param tags object = {}

@description('PostgreSQL administrator login name.')
param adminLogin string

@description('PostgreSQL administrator password.')
@secure()
param adminPassword string

param databaseName string = 'appdb'

@description('Compute SKU. Burstable B1ms suits a prototype; scale up for production load.')
param skuName string = 'Standard_B1ms'
param skuTier string = 'Burstable'

// Server names are globally unique (they form the public FQDN).
var serverName = 'pg-${namePrefix}'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: '16'
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// Allowlist pgvector so a migration can `CREATE EXTENSION vector` if a tool
// stores embeddings in Postgres. Flexible Server rejects unlisted extensions.
resource extensionsAllowlist 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: server
  name: 'azure.extensions'
  properties: {
    value: 'VECTOR'
    source: 'user-override'
  }
  dependsOn: [database]
}

// Lets Azure services (the Container Apps environment's outbound IPs) connect.
// This admits any Azure-hosted client, so the password is the real control;
// use VNet integration + private access when a tool handles sensitive data.
resource allowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: server
  name: 'AllowAllAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output serverName string = server.name
output serverFqdn string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
