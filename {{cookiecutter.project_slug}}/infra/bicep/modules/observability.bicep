// Log Analytics workspace + Application Insights (workspace-based).
@description('Prefix used for resource names, e.g. aitool-dev')
param namePrefix string
param location string = resourceGroup().location
param tags object = {}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${namePrefix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${namePrefix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

output logAnalyticsId string = logAnalytics.id
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
@description('Name (not value) of the Log Analytics workspace for shared-key lookup.')
output logAnalyticsName string = logAnalytics.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
