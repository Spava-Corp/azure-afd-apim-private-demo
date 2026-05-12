// AKS Cluster — Internal load balancer, no public IP, system-assigned managed identity
// Uses Azure CNI for VNet integration with the AKS subnet

@description('Azure region for AKS')
param location string

@description('Resource naming prefix')
param prefix string

@description('Environment name (dev, staging, prod)')
param environment string

@description('Resource ID of the AKS subnet')
param aksSubnetId string

@description('Kubernetes version')
param kubernetesVersion string = '1.29'

@description('VM size for the system node pool')
param systemNodeVmSize string = 'Standard_DS2_v2'

@description('Number of nodes in the system node pool')
@minValue(1)
@maxValue(10)
param systemNodeCount int = 2

@description('Log Analytics workspace resource ID for monitoring')
param workspaceId string

@description('DNS prefix for the AKS cluster')
param dnsPrefix string = '${prefix}-aks-${environment}'

@description('Tags to apply to resources')
param tags object = {}

var aksName = '${prefix}-aks-${environment}'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: aksName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    // No public IP on the API server
    apiServerAccessProfile: {
      enablePrivateCluster: true
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'calico'
      serviceCidr: '10.250.0.0/16'
      dnsServiceIP: '10.250.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: aksSubnetId
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        // AKS internal load balancer annotation applied at service level in K8s manifests:
        // service.beta.kubernetes.io/azure-load-balancer-internal: "true"
      }
    ]
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: workspaceId
        }
      }
    }
  }
}

@description('Resource ID of the AKS cluster')
output aksClusterId string = aksCluster.id

@description('Name of the AKS cluster')
output aksClusterName string = aksCluster.name

@description('AKS node resource group (MC_ group)')
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup

@description('System-assigned managed identity principal ID')
output aksPrincipalId string = aksCluster.identity.principalId

@description('AKS FQDN for the private cluster')
output aksPrivateFqdn string = aksCluster.properties.privateFQDN
