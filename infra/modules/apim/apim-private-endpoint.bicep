// Private Endpoint for APIM — enables AFD Private Link origin to reach APIM
// This PE is what AFD's managed VNet connects to via Private Link

@description('Azure region')
param location string

@description('Resource naming prefix')
param prefix string

@description('Environment name (dev, staging, prod)')
param environment string

@description('Resource ID of the APIM service')
param apimId string

@description('Resource ID of the subnet for private endpoints')
param privateEndpointSubnetId string

@description('Resource ID of the APIM private DNS zone')
param apimDnsZoneId string

@description('Tags to apply to resources')
param tags object = {}

var privateEndpointName = '${prefix}-pe-apim-${environment}'

resource apimPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: apimId
          groupIds: [
            'Gateway'
          ]
        }
      }
    ]
  }
}

// DNS zone group for automatic A record registration
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: apimPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azure-api-net'
        properties: {
          privateDnsZoneId: apimDnsZoneId
        }
      }
    ]
  }
}

@description('Resource ID of the APIM private endpoint')
output privateEndpointId string = apimPrivateEndpoint.id

@description('Name of the APIM private endpoint')
output privateEndpointName string = apimPrivateEndpoint.name

@description('Network interface IDs of the private endpoint')
output networkInterfaceIds array = apimPrivateEndpoint.properties.networkInterfaces
