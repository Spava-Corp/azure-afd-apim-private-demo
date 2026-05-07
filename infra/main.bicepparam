using './main.bicep'

// ─── Dev Environment Defaults ─────────────────────────────────────────────────
// AFD Premium → APIM (Developer, Internal) → AKS (Private Link) Architecture
// Region: West US 2 | Demo APIs: Swagger Petstore + Podinfo

// Global
param location = 'westus2'
param prefix = 'demo'
param environment = 'dev'

// Networking
param vnetAddressPrefix = '10.0.0.0/16'
param apimSubnetPrefix = '10.0.1.0/24'
param aksSubnetPrefix = '10.0.2.0/22'
param privateEndpointSubnetPrefix = '10.0.6.0/24'
param bastionSubnetPrefix = '10.0.7.0/26'

// APIM
param apimPublisherEmail = 'admin@contoso.com'
param apimPublisherName = 'SecOps Demo'
param apimSkuName = 'Developer'

// AKS
param kubernetesVersion = '1.29'
param aksNodeVmSize = 'Standard_DS2_v2'
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
