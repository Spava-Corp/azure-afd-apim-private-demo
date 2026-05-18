// Private DNS Zones linked to VNet
// Required for private-only service name resolution within the VNet

@description('Resource ID of the VNet to link DNS zones to')
param vnetId string

@description('Tags to apply to resources')
param tags object = {}

// Private DNS zone for APIM internal gateway resolution
resource apimDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'azure-api.net'
  location: 'global'
  tags: tags
}

// Private DNS zone for Key Vault
resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

// VNet link for APIM DNS zone
resource apimDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: apimDnsZone
  name: 'link-apim'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// VNet link for Key Vault DNS zone
resource keyVaultDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultDnsZone
  name: 'link-keyvault'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// Private DNS zone for AKS private cluster
resource aksDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.westus2.azmk8s.io'
  location: 'global'
  tags: tags
}

// VNet link for AKS DNS zone
resource aksDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: aksDnsZone
  name: 'link-aks'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

@description('Resource ID of the APIM private DNS zone')
output apimDnsZoneId string = apimDnsZone.id

@description('Resource ID of the Key Vault private DNS zone')
output keyVaultDnsZoneId string = keyVaultDnsZone.id

@description('Resource ID of the AKS private DNS zone')
output aksDnsZoneId string = aksDnsZone.id
