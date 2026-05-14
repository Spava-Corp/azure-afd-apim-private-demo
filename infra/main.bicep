// Main Bicep Orchestrator — AFD → APIM → AKS (Private Link) Architecture
// Deploys all modules in correct dependency order
//
// Architecture: Internet → AFD (Premium + WAF) → Private Link → APIM (PE-only, public access disabled) → Private Link Service → AKS (Internal LB)
// All inter-service traffic stays on Azure backbone. APIM public network access is disabled and the backend has no public IP.
//
// Deployment note: APIM still takes 30-45 minutes to deploy.
// The CD pipeline auto-approves the AFD Private Endpoint connection; manual approval is for out-of-band deploys.

targetScope = 'resourceGroup'

// ─── Global Parameters ────────────────────────────────────────────────────────

@description('Azure region for all resources')
param location string = 'westus2'

@description('Resource naming prefix (e.g., demo, prod)')
param prefix string = 'demo'

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Tags applied to all resources')
param tags object = {
  project: 'afd-apim-private'
  environment: environment
  managedBy: 'bicep'
}

// ─── Networking Parameters ────────────────────────────────────────────────────

@description('VNet address space')
param vnetAddressPrefix string = '10.1.0.0/16'

@description('APIM subnet address prefix')
param apimSubnetPrefix string = '10.1.1.0/24'

@description('AKS subnet address prefix')
param aksSubnetPrefix string = '10.1.4.0/22'

@description('Private Endpoints subnet address prefix')
param privateEndpointSubnetPrefix string = '10.1.8.0/24'

@description('Bastion subnet address prefix')
param bastionSubnetPrefix string = '10.1.9.0/26'

// ─── APIM Parameters ──────────────────────────────────────────────────────────

@description('APIM publisher email')
param apimPublisherEmail string

@description('APIM publisher name')
param apimPublisherName string = 'SecOps Demo'

@description('APIM SKU')
@allowed(['Developer', 'Standard', 'Premium'])
param apimSkuName string = 'Developer'

// ─── AKS Parameters ──────────────────────────────────────────────────────────

@description('Kubernetes version')
param kubernetesVersion string = '1.34'

@description('AKS system node pool VM size')
param aksNodeVmSize string = 'Standard_D2s_v5'

@description('AKS system node count')
param aksNodeCount int = 2

// ─── Monitoring Parameters ────────────────────────────────────────────────────

@description('Log Analytics retention in days')
param logRetentionDays int = 90

// ─── WAF Parameters ──────────────────────────────────────────────────────────

@description('WAF policy mode')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Prevention'

@description('Rate limit threshold (requests per minute per IP)')
param rateLimitThreshold int = 1000

// ─── AKS Private Link Service Parameter ──────────────────────────────────────

@description('Resource ID of the AKS internal load balancer frontend IP config. Set after deploying K8s services with internal LB annotation. Leave empty for initial deployment.')
param aksLoadBalancerFrontendIpConfigId string = ''

// ═══════════════════════════════════════════════════════════════════════════════
// MODULE DEPLOYMENTS
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Phase 1: Foundation ──────────────────────────────────────────────────────

// 1.1 Log Analytics Workspace
module logAnalytics 'modules/monitoring/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    location: location
    prefix: prefix
    environment: environment
    retentionInDays: logRetentionDays
    tags: tags
  }
}

// 1.2 Virtual Network + Subnets + NSGs
module networking 'modules/networking/vnet.bicep' = {
  name: 'deploy-networking'
  params: {
    location: location
    prefix: prefix
    environment: environment
    vnetAddressPrefix: vnetAddressPrefix
    apimSubnetPrefix: apimSubnetPrefix
    aksSubnetPrefix: aksSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    tags: tags
  }
}

// 1.3 Private DNS Zones
module privateDnsZones 'modules/networking/private-dns-zones.bicep' = {
  name: 'deploy-private-dns-zones'
  params: {
    vnetId: networking.outputs.vnetId
    tags: tags
  }
}

// 1.4 Key Vault
module keyVault 'modules/security/key-vault.bicep' = {
  name: 'deploy-key-vault'
  params: {
    location: location
    prefix: prefix
    environment: environment
    tags: tags
  }
}

// ─── Phase 2: Backend (AKS) ──────────────────────────────────────────────────

// 2.1 AKS Cluster
module aks 'modules/aks/aks.bicep' = {
  name: 'deploy-aks'
  params: {
    location: location
    prefix: prefix
    environment: environment
    aksSubnetId: networking.outputs.aksSubnetId
    kubernetesVersion: kubernetesVersion
    systemNodeVmSize: aksNodeVmSize
    systemNodeCount: aksNodeCount
    workspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// 2.2 Private Link Service (deploy after K8s internal LB is provisioned)
// NOTE: aksLoadBalancerFrontendIpConfigId must be set after deploying K8s services
// with the azure-load-balancer-internal annotation. This is a two-phase deploy.
module aksPrivateLinkService 'modules/aks/private-link-service.bicep' = if (!empty(aksLoadBalancerFrontendIpConfigId)) {
  name: 'deploy-aks-private-link-service'
  params: {
    location: location
    prefix: prefix
    environment: environment
    aksSubnetId: networking.outputs.aksSubnetId
    loadBalancerFrontendIpConfigId: aksLoadBalancerFrontendIpConfigId
    tags: tags
  }
}

// ─── Phase 3: API Management ─────────────────────────────────────────────────

// 3.1 APIM Instance (PE-only, public access disabled)
module apim 'modules/apim/apim.bicep' = {
  name: 'deploy-apim'
  params: {
    location: location
    prefix: prefix
    environment: environment
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    skuName: apimSkuName
    workspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// 3.2 APIM Private Endpoint (for AFD to connect via Private Link)
module apimPrivateEndpoint 'modules/apim/apim-private-endpoint.bicep' = {
  name: 'deploy-apim-private-endpoint'
  params: {
    location: location
    prefix: prefix
    environment: environment
    apimId: apim.outputs.apimId
    privateEndpointSubnetId: networking.outputs.privateEndpointSubnetId
    apimDnsZoneId: privateDnsZones.outputs.apimDnsZoneId
    tags: tags
  }
}

// 3.3 Key Vault access for APIM managed identity
module keyVaultWithApimAccess 'modules/security/key-vault.bicep' = {
  name: 'deploy-key-vault-apim-access'
  params: {
    location: location
    prefix: prefix
    environment: environment
    apimPrincipalId: apim.outputs.apimPrincipalId
    tags: tags
  }
}

// ─── Phase 4: Edge (Azure Front Door) ────────────────────────────────────────

// 4.1 WAF Policy (afdProfileId output is available if fallback header validation is ever needed)
module wafPolicy 'modules/front-door/waf-policy.bicep' = {
  name: 'deploy-waf-policy'
  params: {
    prefix: prefix
    environment: environment
    policyMode: wafMode
    rateLimitThreshold: rateLimitThreshold
    afdProfileId: '' // Populated post-deployment via parameter override or redeployment
    tags: tags
  }
}

// 4.2 AFD Profile + Endpoint + Origin Group + Private Link Origin
module frontDoor 'modules/front-door/afd.bicep' = {
  name: 'deploy-front-door'
  params: {
    prefix: prefix
    environment: environment
    wafPolicyId: wafPolicy.outputs.wafPolicyId
    apimHostname:'${prefix}-apim-${environment}.azure-api.net'
    apimPrivateLinkServiceId: apim.outputs.apimId
    tags: tags
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OUTPUTS
// ═══════════════════════════════════════════════════════════════════════════════

@description('AFD endpoint URL — use this to test the full path')
output afdEndpointUrl string = 'https://${frontDoor.outputs.afdEndpointHostname}'

@description('AFD Front Door ID — use only if fallback X-Azure-FDID validation is needed')
output afdFrontDoorId string = frontDoor.outputs.afdFrontDoorId

@description('APIM gateway URL (PE-only ingress)')
output apimGatewayUrl string = apim.outputs.apimGatewayUrl

@description('AKS cluster name')
output aksClusterName string = aks.outputs.aksClusterName

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('Post-deployment reminder')
output postDeployNote string = 'IMPORTANT: The CD pipeline auto-approves the AFD Private Endpoint connection on APIM. If you deploy outside the pipeline, approve it manually. Deploy K8s services with internal LB annotation, then re-deploy with aksLoadBalancerFrontendIpConfigId set.'
