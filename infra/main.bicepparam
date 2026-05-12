using './main.bicep'

// ─── ESLZ Online Landing Zone — Dev Environment Defaults ──────────────────────
// AFD Premium → APIM (Developer, Internal) → AKS (Private Link) Architecture
// Subscription: Spaidoso-LZ-Online | Region: West US 2
// VNet: 10.1.0.0/16 (shifted to avoid ESLZ hub 10.0.0.0/16 collision)

// Global
param location = 'westus2'
param prefix = 'demo'
param environment = 'dev'

// Networking — 10.1.x.x spoke range (ESLZ hub uses 10.0.0.0/16)
param vnetAddressPrefix = '10.1.0.0/16'
param apimSubnetPrefix = '10.1.1.0/24'
param aksSubnetPrefix = '10.1.4.0/22'
param privateEndpointSubnetPrefix = '10.1.8.0/24'
param bastionSubnetPrefix = '10.1.9.0/26'

// APIM
param apimPublisherEmail = 'demo-admin@spaidoso.onmicrosoft.com'
param apimPublisherName = 'SecOps Demo'
param apimSkuName = 'Developer'

// AKS
param kubernetesVersion = '1.34'
param aksNodeVmSize = 'Standard_D2s_v5'
param aksNodeCount = 2

// Monitoring
param logRetentionDays = 90

// WAF
param wafMode = 'Prevention'
param rateLimitThreshold = 1000

// AKS Private Link Service (set after deploying K8s services with internal LB)
// Phase 2: After `kubectl apply` of services with azure-load-balancer-internal annotation,
// get the LB frontend IP config ID and re-deploy with this parameter set.
param aksLoadBalancerFrontendIpConfigId = ''
