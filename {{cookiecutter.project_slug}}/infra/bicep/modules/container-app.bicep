// Generic Azure Container App used for both the frontend and backend.
// Authenticates to ACR and Key Vault via a user-assigned managed identity.
@description('Container app name.')
param name string
param location string = resourceGroup().location
param tags object = {}

@description('Managed environment resource id.')
param environmentId string

@description('User-assigned managed identity resource id.')
param userAssignedIdentityId string

@description('ACR login server, e.g. myacr.azurecr.io.')
param registryServer string

@description('Fully-qualified container image reference.')
param image string

@description('Port the container listens on.')
param targetPort int

@description('Expose publicly (true) or only within the environment (false).')
param external bool = true

@description('Plain environment variables: array of { name, value }.')
param envVars array = []

@description('Key Vault reference secrets: array of { name, keyVaultUrl }.')
param secretRefs array = []

@description('Env vars sourced from secrets: array of { name, secretRef }.')
param secretEnvVars array = []

param minReplicas int = 1
param maxReplicas int = 3

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: external
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryServer
          identity: userAssignedIdentityId
        }
      ]
      secrets: [
        for s in secretRefs: {
          name: s.name
          keyVaultUrl: s.keyVaultUrl
          identity: userAssignedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: name
          image: image
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: concat(envVars, secretEnvVars)
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
output name string = containerApp.name
