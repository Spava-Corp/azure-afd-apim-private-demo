// APIM private gateway DNS wiring for Internal VNet mode
// AFD creates the managed private endpoint through Shared Private Link; this module only publishes
// the APIM gateway's private IP into the VNet-linked azure-api.net private DNS zone.

@description('APIM service name')
param apimName string

@description('Private IP addresses assigned to the APIM gateway')
param apimPrivateIpAddresses array

@description('Resource ID of the APIM private DNS zone')
param apimDnsZoneId string

resource apimDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: last(split(apimDnsZoneId, '/'))
}

resource gatewayRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = if (length(apimPrivateIpAddresses) > 0) {
  parent: apimDnsZone
  name: apimName
  properties: {
    ttl: 300
    aRecords: [for ip in apimPrivateIpAddresses: {
      ipv4Address: ip
    }]
  }
}

@description('Resource ID of the APIM private DNS A record')
output gatewayRecordId string = length(apimPrivateIpAddresses) > 0 ? gatewayRecord.id : ''
