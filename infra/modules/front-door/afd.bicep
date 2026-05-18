// Azure Front Door Premium — Profile, Endpoint, Origin Group
// AFD reaches APIM through Shared Private Link so the APIM gateway stays private-only in Internal VNet mode.
// APIM still validates the X-Azure-FDID header as defense in depth.

@description('Resource naming prefix')
param prefix string

@description('Environment name (dev, staging, prod)')
param environment string

@description('Resource ID of the WAF policy to associate')
param wafPolicyId string

@description('APIM hostname (e.g., demo-apim-dev.azure-api.net)')
param apimHostname string

@description('Resource ID of the APIM service for Shared Private Link')
param apimId string

@description('Tags to apply to resources')
param tags object = {}

var afdProfileName = '${prefix}-afd-${environment}-${substring(uniqueString(resourceGroup().id), 0, 6)}'
var endpointName = '${prefix}-endpoint-${environment}-${substring(uniqueString(resourceGroup().id), 0, 6)}'

// AFD Premium Profile
resource afdProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: afdProfileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
}

// AFD Endpoint
resource afdEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: afdProfile
  name: endpointName
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin Group
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: afdProfile
  name: 'apim-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/status-0123456789abcdef'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origin pointing to APIM gateway through Shared Private Link
// Name kept as 'apim-private-link-origin' to update existing resource in-place
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'apim-private-link-origin'
  properties: {
    hostName: apimHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: apimHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    sharedPrivateLinkResource: {
      groupId: 'Gateway'
      privateLink: {
        id: apimId
      }
      privateLinkLocation: resourceGroup().location
      requestMessage: 'AFD Private Link to APIM'
    }
  }
}

// Route (default route — all traffic to APIM origin group)
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: afdEndpoint
  name: 'default-route'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [
    origin
  ]
}

// Security Policy (WAF association)
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  parent: afdProfile
  name: 'waf-security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          domains: [
            {
              id: afdEndpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

@description('Resource ID of the AFD profile')
output afdProfileId string = afdProfile.id

@description('Name of the AFD profile')
output afdProfileName string = afdProfile.name

@description('AFD endpoint hostname')
output afdEndpointHostname string = afdEndpoint.properties.hostName

@description('AFD profile ID (for X-Azure-FDID header validation)')
output afdFrontDoorId string = afdProfile.properties.frontDoorId
