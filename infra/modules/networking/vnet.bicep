// Hub VNet with subnets for APIM, AKS, Private Endpoints, and Bastion
// All subnets get NSGs with reasonable defaults (Kima will refine rules)

@description('Azure region for the VNet')
param location string

@description('Resource naming prefix')
param prefix string

@description('Environment name (dev, staging, prod)')
param environment string

@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('APIM subnet address prefix')
param apimSubnetPrefix string = '10.0.1.0/24'

@description('AKS subnet address prefix')
param aksSubnetPrefix string = '10.0.2.0/22'

@description('Private Endpoints subnet address prefix')
param privateEndpointSubnetPrefix string = '10.0.6.0/24'

@description('Bastion subnet address prefix (must be named AzureBastionSubnet)')
param bastionSubnetPrefix string = '10.0.7.0/26'

@description('Tags to apply to resources')
param tags object = {}

var vnetName = '${prefix}-vnet-${environment}'
var apimNsgName = '${prefix}-nsg-apim-${environment}'
var aksNsgName = '${prefix}-nsg-aks-${environment}'
var peNsgName = '${prefix}-nsg-pe-${environment}'
var bastionNsgName = '${prefix}-nsg-bastion-${environment}'

// NSG for APIM subnet
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: apimNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-APIM-Management'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-Azure-Storage-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
        }
      }
      {
        name: 'Allow-Azure-SQL-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
        }
      }
      {
        name: 'Allow-Azure-KeyVault-Outbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
        }
      }
    ]
  }
}

// NSG for AKS subnet
resource aksNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: aksNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-APIM-to-AKS'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: apimSubnetPrefix
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// NSG for Private Endpoints subnet
resource peNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: peNsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// NSG for Bastion subnet
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: bastionNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Https-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-GatewayManager-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-RDP-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['22', '3389']
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-AzureCloud-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
        }
      }
    ]
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-apim'
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: {
            id: apimNsg.id
          }
          delegations: []
        }
      }
      {
        name: 'snet-aks'
        properties: {
          addressPrefix: aksSubnetPrefix
          networkSecurityGroup: {
            id: aksNsg.id
          }
          delegations: []
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: peNsg.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: {
            id: bastionNsg.id
          }
        }
      }
    ]
  }
}

@description('Resource ID of the VNet')
output vnetId string = vnet.id

@description('Name of the VNet')
output vnetName string = vnet.name

@description('Resource ID of the APIM subnet')
output apimSubnetId string = vnet.properties.subnets[0].id

@description('Resource ID of the AKS subnet')
output aksSubnetId string = vnet.properties.subnets[1].id

@description('Resource ID of the Private Endpoints subnet')
output privateEndpointSubnetId string = vnet.properties.subnets[2].id

@description('Resource ID of the Bastion subnet')
output bastionSubnetId string = vnet.properties.subnets[3].id
