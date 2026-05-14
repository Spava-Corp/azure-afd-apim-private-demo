// Azure API Management — Private Endpoint connectivity, stv2 platform
// APIM does not use VNet integration; private access is provided via Private Endpoint

@description('Azure region for APIM')
param location string

@description('Resource naming prefix')
param prefix string

@description('Environment name (dev, staging, prod)')
param environment string

@description('APIM publisher email')
param publisherEmail string

@description('APIM publisher name')
param publisherName string

@description('APIM SKU name')
@allowed(['Developer', 'Standard', 'Premium'])
param skuName string = 'Developer'

@description('APIM SKU capacity (units)')
param skuCapacity int = 1

@description('Log Analytics workspace resource ID for diagnostics')
param workspaceId string

@description('Tags to apply to resources')
param tags object = {}

var apimName = '${prefix}-apim-${environment}-${substring(uniqueString(resourceGroup().id), 0, 6)}'

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'None'
    // Private connectivity is handled via Private Endpoint (apim-private-endpoint module)
    // AFD connects via shared Private Link origin
    // NOTE: X-Azure-FDID header validation should be enforced via APIM policy
    // Kima will add the inbound policy to validate the AFD instance ID
    // Policy should check: <check-header name="X-Azure-FDID" failed-check-httpcode="403">
    //   <value>{afd-profile-id}</value>
    // </check-header>
  }
}

// Diagnostic settings for APIM (also handled centrally in diagnostic-settings module)
resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${apimName}-diagnostics'
  scope: apimService
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

@description('Resource ID of the APIM service')
output apimId string = apimService.id

@description('Name of the APIM service')
output apimName string = apimService.name

@description('Private IP addresses of APIM when VNet-integrated; empty when using Private Endpoint-only connectivity')
output apimPrivateIpAddresses array = apimService.properties.?privateIPAddresses ?? []

@description('APIM gateway URL')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('System-assigned managed identity principal ID')
output apimPrincipalId string = apimService.identity.principalId
