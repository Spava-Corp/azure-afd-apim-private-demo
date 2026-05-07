// Azure API Management — Developer SKU, Internal VNet mode, stv2 platform
// Internal mode means APIM has no public endpoint — only reachable via Private Endpoint

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

@description('Resource ID of the APIM subnet (required for VNet integration)')
param apimSubnetId string

@description('Log Analytics workspace resource ID for diagnostics')
param workspaceId string

@description('Tags to apply to resources')
param tags object = {}

var apimName = '${prefix}-apim-${environment}'

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
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    // stv2 platform is the default for new deployments
    platformVersion: 'stv2'
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

@description('Private IP addresses of APIM (internal mode)')
output apimPrivateIpAddresses array = apimService.properties.privateIPAddresses

@description('APIM gateway URL')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('System-assigned managed identity principal ID')
output apimPrincipalId string = apimService.identity.principalId
