targetScope = 'resourceGroup'

// PostgreSQL Flexible Server for the API. After deploying, store the full
// connection URL as the `DATABASE_URL` secret of the GitHub `dev` environment;
// `scripts/cd.sh` writes it to Key Vault as `database-url` (see docs/runbook.md):
//   postgresql+psycopg://<adminLogin>:<password>@<serverFqdn>:5432/<databaseName>?sslmode=require

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('PostgreSQL administrator login name.')
param adminLogin string = '${resourcePrefix}admin'

@description('PostgreSQL administrator password (letters and digits; supply at deploy time).')
@secure()
param adminPassword string

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

module postgres '../modules/postgres.bicep' = {
  name: 'postgres-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    adminLogin: adminLogin
    adminPassword: adminPassword
    databaseName: databaseName
  }
}

output serverName string = postgres.outputs.serverName
output serverFqdn string = postgres.outputs.serverFqdn
output databaseName string = postgres.outputs.databaseName
output adminLogin string = adminLogin
