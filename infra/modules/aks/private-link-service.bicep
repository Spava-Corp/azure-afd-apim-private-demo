// Private Link Service exposing AKS internal Load Balancer for APIM
// APIM connects to backend via this PLS — no public exposure

@description('Azure region')
param location string

@description('Resource naming prefix')
param prefix string

@description('Environment name (dev, staging, prod)')
param environment string

@description('Resource ID of the AKS subnet (where the internal LB frontend lives)')
param aksSubnetId string

@description('Resource ID of the internal load balancer frontend IP configuration. Obtain this from the AKS-managed internal LB in the node resource group after deploying services with azure-load-balancer-internal annotation.')
param loadBalancerFrontendIpConfigId string

@description('Tags to apply to resources')
param tags object = {}

var plsName = '${prefix}-pls-aks-${environment}'

resource privateLinkService 'Microsoft.Network/privateLinkServices@2023-11-01' = {
  name: plsName
  location: location
  tags: tags
  properties: {
    enableProxyProtocol: false
    loadBalancerFrontendIpConfigurations: [
      {
        id: loadBalancerFrontendIpConfigId
      }
    ]
    ipConfigurations: [
      {
        name: 'pls-ip-config'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: aksSubnetId
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    visibility: {
      subscriptions: [
        subscription().subscriptionId
      ]
    }
    autoApproval: {
      subscriptions: [
        subscription().subscriptionId
      ]
    }
  }
}

@description('Resource ID of the Private Link Service')
output privateLinkServiceId string = privateLinkService.id

@description('Name of the Private Link Service')
output privateLinkServiceName string = privateLinkService.name

@description('Alias of the Private Link Service (used in PE connections)')
output privateLinkServiceAlias string = privateLinkService.properties.alias
