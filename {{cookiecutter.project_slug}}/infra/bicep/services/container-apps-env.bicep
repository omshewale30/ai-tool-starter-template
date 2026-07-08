targetScope = 'resourceGroup'

@description('Prefix for resource names.')
param resourcePrefix string = '{{ cookiecutter.resource_prefix }}'

@description('Environment name used in resource names and tags.')
param environmentName string = 'dev'

@description('Azure region for the resource.')
param location string = resourceGroup().location

@description('Log Analytics workspace name in this resource group.')
param logAnalyticsName string

@description('Optional tags merged with default tags.')
param extraTags object = {}

var namePrefix = '${resourcePrefix}-${environmentName}'
var defaultTags = {
  application: '{{ cookiecutter.project_slug }}'
  environment: environmentName
}
var tags = union(defaultTags, extraTags)

module env '../modules/container-apps-env.bicep' = {
  name: 'container-apps-env-${namePrefix}'
  params: {
    namePrefix: namePrefix
    location: location
    tags: tags
    logAnalyticsName: logAnalyticsName
  }
}

output environmentId string = env.outputs.environmentId
output defaultDomain string = env.outputs.defaultDomain
