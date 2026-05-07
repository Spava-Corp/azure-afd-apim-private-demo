// Log Analytics Workspace
// Centralized logging for all resources in the architecture

@description('Azure region for the workspace')
param location string

@description('Resource naming prefix')
param prefix string

@description('Environment name (dev, staging, prod)')
param environment string

@description('Log retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('SKU for Log Analytics workspace')
@allowed(['PerGB2018', 'Free', 'Standalone', 'PerNode'])
param sku string = 'PerGB2018'

@description('Tags to apply to resources')
param tags object = {}

var workspaceName = '${prefix}-law-${environment}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1 // Unlimited
    }
  }
}

@description('Resource ID of the Log Analytics workspace')
output workspaceId string = logAnalyticsWorkspace.id

@description('Name of the Log Analytics workspace')
output workspaceName string = logAnalyticsWorkspace.name

@description('Customer ID (workspace ID) for agent configuration')
output customerId string = logAnalyticsWorkspace.properties.customerId
