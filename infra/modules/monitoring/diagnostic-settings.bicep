// Diagnostic Settings for AFD, APIM, and AKS
// Routes platform logs and metrics to Log Analytics workspace

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Azure Front Door profile resource ID')
param afdProfileId string

@description('APIM service resource ID')
param apimId string

@description('AKS cluster resource ID')
param aksClusterId string

// AFD Diagnostic Settings
resource afdDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'afd-diagnostics'
  scope: afdProfile
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// APIM Diagnostic Settings
resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-diagnostics'
  scope: apimService
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// AKS Diagnostic Settings
resource aksDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'aks-diagnostics'
  scope: aksCluster
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Existing resource references for scoping diagnostic settings
resource afdProfile 'Microsoft.Cdn/profiles@2023-05-01' existing = {
  name: last(split(afdProfileId, '/'))
}

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: last(split(apimId, '/'))
}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' existing = {
  name: last(split(aksClusterId, '/'))
}
