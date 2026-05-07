// ============================================================================
// NSG Rules — AFD → APIM → AKS Private Architecture
// Author: Kima (SecOps Engineer)
// Date: 2026-05-07
//
// Design Philosophy: Deny-all default with explicit allow-list.
// Every rule has a comment explaining WHY it exists (not just what).
// ============================================================================

@description('Azure region for all NSG resources')
param location string

@description('Name prefix for all NSG resources')
param namePrefix string

@description('CIDR of the APIM subnet (e.g., 10.0.1.0/24)')
param apimSubnetCidr string

@description('CIDR of the AKS subnet (e.g., 10.0.2.0/24)')
param aksSubnetCidr string

@description('CIDR of the Private Endpoint subnet (e.g., 10.0.3.0/24)')
param privateEndpointSubnetCidr string

@description('CIDR of the full VNet (e.g., 10.0.0.0/16)')
param vnetCidr string

@description('Tags to apply to all NSG resources')
param tags object = {}

// ============================================================================
// APIM Subnet NSG
// Purpose: Protect the APIM instance. Only AFD and Azure management can reach it.
// ============================================================================

@description('NSG for the APIM subnet — only AFD and management traffic allowed inbound')
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-apim-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // --- INBOUND RULES ---
      {
        name: 'Allow-AFD-Inbound-HTTPS'
        properties: {
          description: 'AFD Premium connects to APIM via Private Link on port 443. This is the ONLY legitimate ingress path for API traffic.'
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetCidr
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-APIM-Management'
        properties: {
          description: 'Azure APIM management plane requires port 3443 for deployments, config pushes, and health monitoring. Without this, APIM becomes unmanageable.'
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetCidr
          destinationPortRange: '3443'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          description: 'Azure Load Balancer health probes must reach APIM to confirm instance health. Required for stv2 platform.'
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetCidr
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          description: 'Explicit deny-all catches anything not in the allow-list above. Defense-in-depth — even if Azure adds new default rules, we block unknown traffic.'
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      // --- OUTBOUND RULES ---
      {
        name: 'Allow-Outbound-To-AKS'
        properties: {
          description: 'APIM must reach AKS backend on ports 443/8080 to proxy API requests. This is the only backend communication path.'
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: apimSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: aksSubnetCidr
          destinationPortRanges: [
            '443'
            '8080'
          ]
        }
      }
      {
        name: 'Allow-Outbound-Azure-Management'
        properties: {
          description: 'APIM needs outbound to Azure services for: Key Vault cert retrieval, Azure Monitor telemetry, AAD token acquisition, and SQL for config storage.'
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: apimSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRanges: [
            '443'
            '1433'
          ]
        }
      }
      {
        name: 'Deny-Outbound-Internet'
        properties: {
          description: 'No direct internet access from APIM. Prevents data exfil if APIM is compromised. All Azure dependencies use service tags above.'
          priority: 4000
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ============================================================================
// AKS Subnet NSG
// Purpose: Protect AKS nodes. Only APIM and Azure control plane can reach them.
// ============================================================================

@description('NSG for the AKS subnet — only APIM and control plane traffic allowed inbound')
resource aksNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-aks-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // --- INBOUND RULES ---
      {
        name: 'Allow-APIM-Inbound'
        properties: {
          description: 'APIM proxies API traffic to AKS workloads on 8080 (HTTP) and 443 (HTTPS/mTLS). This is the only application-level ingress.'
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: apimSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: aksSubnetCidr
          destinationPortRanges: [
            '443'
            '8080'
          ]
        }
      }
      {
        name: 'Allow-AKS-ControlPlane'
        properties: {
          description: 'AKS control plane (managed by Azure) needs to communicate with kubelet on nodes for pod management, log streaming, and exec. Required for cluster operation.'
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureCloud'
          sourcePortRange: '*'
          destinationAddressPrefix: aksSubnetCidr
          destinationPortRanges: [
            '443'
            '10250'
          ]
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          description: 'Internal load balancer health probes for AKS services. Without this, ILB marks all backends as unhealthy.'
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: aksSubnetCidr
          destinationPortRange: '*'
        }
      }
      {
        name: 'Allow-IntraSubnet'
        properties: {
          description: 'AKS nodes need to communicate with each other for pod-to-pod networking (CNI), CoreDNS, and kube-proxy. Blocking this breaks the cluster.'
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: aksSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: aksSubnetCidr
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          description: 'Block everything else. No SSH, no direct internet, no other subnets. If you need debug access, use AKS run-command or Bastion — never open SSH here.'
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      // --- OUTBOUND RULES ---
      {
        name: 'Allow-Outbound-Azure'
        properties: {
          description: 'AKS needs outbound to Azure for: ACR image pulls, Azure Monitor, AAD authentication, Key Vault secrets. Covers all Azure PaaS dependencies.'
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: aksSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRanges: [
            '443'
            '9000'
          ]
        }
      }
      {
        name: 'Allow-Outbound-DNS'
        properties: {
          description: 'DNS resolution for Azure Private DNS zones and external names (NTP, package repos). AKS CoreDNS forwards here.'
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: aksSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRanges: [
            '53'
            '123'
          ]
        }
      }
      {
        name: 'Allow-Outbound-ImagePulls'
        properties: {
          description: 'Limited internet for container image pulls from MCR, Docker Hub, etc. In production, replace with ACR-only via Private Endpoint and remove this rule.'
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: aksSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Deny-Outbound-All-Other'
        properties: {
          description: 'Block non-HTTPS outbound internet. Prevents C2 on non-standard ports if a pod is compromised.'
          priority: 4000
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRanges: [
            '1-442'
            '444-65535'
          ]
        }
      }
    ]
  }
}

// ============================================================================
// Private Endpoint Subnet NSG
// Purpose: Lock down the PE subnet. Only VNet-internal traffic should reach PEs.
// ============================================================================

@description('NSG for the Private Endpoint subnet — VNet-only access, no external')
resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-pe-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // --- INBOUND RULES ---
      {
        name: 'Allow-VNet-Inbound'
        properties: {
          description: 'Private Endpoints serve resources to the VNet. Allow all VNet sources — the PE itself handles access control via Private Link RBAC.'
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: vnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointSubnetCidr
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-All-External-Inbound'
        properties: {
          description: 'No traffic from outside the VNet should ever reach Private Endpoints. This blocks lateral movement from peered VNets or on-prem if not explicitly allowed.'
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      // --- OUTBOUND RULES ---
      {
        name: 'Deny-All-Outbound'
        properties: {
          description: 'Private Endpoints are inbound-only constructs. They should never initiate outbound connections. If traffic is leaving this subnet, something is wrong.'
          priority: 4000
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the APIM subnet NSG')
output apimNsgId string = apimNsg.id

@description('Resource ID of the AKS subnet NSG')
output aksNsgId string = aksNsg.id

@description('Resource ID of the Private Endpoint subnet NSG')
output privateEndpointNsgId string = privateEndpointNsg.id

@description('Name of the APIM subnet NSG')
output apimNsgName string = apimNsg.name

@description('Name of the AKS subnet NSG')
output aksNsgName string = aksNsg.name

@description('Name of the Private Endpoint subnet NSG')
output privateEndpointNsgName string = privateEndpointNsg.name
