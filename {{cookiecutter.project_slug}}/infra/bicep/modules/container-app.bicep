// Generic Azure Container App used for both the web app and the API.
//
// Authenticates to ACR and Key Vault with a user-assigned managed identity. Single
// revision mode and minReplicas >= 1 are what scripts/cd.sh's health gate requires.
// After creation, scripts/cd.sh owns the image and the application env; this module
// owns everything else (identity, registry, ingress, probes, secrets, scale).
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

@description('Expose publicly (true) or only within the Container Apps environment (false).')
param external bool

@description('Plain environment variables: array of { name, value }.')
param envVars array = []

@description('Key Vault reference secrets: array of { name, keyVaultUrl }.')
param secretRefs array = []

@description('Env vars sourced from secrets: array of { name, secretRef }.')
param secretEnvVars array = []

@description('HTTP path for the liveness probe. Empty uses the platform default (TCP).')
param livenessPath string = ''

@description('HTTP path for the readiness probe. Empty uses the platform default (TCP).')
param readinessPath string = ''

param cpu string = '0.5'
param memory string = '1.0Gi'

@minValue(1)
param minReplicas int = 1
param maxReplicas int = 3

var livenessProbes = empty(livenessPath)
  ? []
  : [
      {
        type: 'Liveness'
        httpGet: { path: livenessPath, port: targetPort }
        initialDelaySeconds: 10
        periodSeconds: 30
        failureThreshold: 3
      }
    ]
var readinessProbes = empty(readinessPath)
  ? []
  : [
      {
        type: 'Readiness'
        httpGet: { path: readinessPath, port: targetPort }
        initialDelaySeconds: 5
        periodSeconds: 10
        failureThreshold: 3
      }
    ]

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
            cpu: json(cpu)
            memory: memory
          }
          env: concat(envVars, secretEnvVars)
          probes: concat(livenessProbes, readinessProbes)
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
