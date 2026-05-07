// ============================================================================
// Managed Identities — AFD → APIM → AKS Private Architecture
// Author: Kima (SecOps Engineer)
// Date: 2026-05-07
//
// User-Assigned Managed Identities for:
// - APIM: Access Key Vault (certs, named values), authenticate to backend
// - AKS: Workload identity for pod-level access to Azure resources
//
// Why User-Assigned (not System-Assigned):
// - Survives resource recreation (APIM redeployment doesn't lose permissions)
// - Can be pre-created and pre-authorized before the resource exists
// - Easier to manage in IaC (identity lifecycle separate from resource lifecycle)
// ============================================================================

@description('Azure region for managed identity resources')
param location string

@description('Name prefix for managed identity resources')
param namePrefix string

@description('Resource ID of the Key Vault that stores certificates and secrets')
param keyVaultId string

@description('Tags to apply to all resources')
param tags object = {}

// ============================================================================
// APIM Managed Identity
// Purpose: APIM uses this identity to:
//   1. Retrieve TLS certificates from Key Vault
//   2. Retrieve named values (secrets) from Key Vault
//   3. Authenticate to backend services (future: token-based auth to AKS)
// ============================================================================

@description('User-assigned managed identity for APIM — Key Vault access and backend auth')
resource apimIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-apim-identity'
  location: location
  tags: tags
}

// ============================================================================
// AKS Managed Identity
// Purpose: AKS workload identity for pods that need Azure resource access:
//   1. Pull images from ACR (if not using kubelet identity)
//   2. Access Key Vault for application secrets
//   3. Write to Azure Monitor / App Insights
//   4. Service-to-service auth with other Azure resources
// ============================================================================

@description('User-assigned managed identity for AKS workload identity — pod-level Azure access')
resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-aks-workload-identity'
  location: location
  tags: tags
}

// ============================================================================
// RBAC Role Assignments
// Grant least-privilege access to Key Vault for APIM identity
// ============================================================================

// Key Vault Secrets User — read secrets (named values, connection strings)
@description('APIM identity can read Key Vault secrets (for named values, connection strings)')
resource apimKeyVaultSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVaultId, apimIdentity.id, 'KeyVaultSecretsUser')
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: apimIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Certificate User — read certificates (TLS certs for custom domains)
@description('APIM identity can read Key Vault certificates (for TLS/mTLS certs)')
resource apimKeyVaultCertsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVaultId, apimIdentity.id, 'KeyVaultCertificateUser')
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba') // Key Vault Certificate User
    principalId: apimIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// AKS workload identity — Key Vault Secrets User for application secrets
@description('AKS workload identity can read Key Vault secrets (for application config)')
resource aksKeyVaultSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVaultId, aksIdentity.id, 'KeyVaultSecretsUser')
  scope: keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: aksIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reference existing Key Vault for scoped role assignments
resource keyVaultResource 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: last(split(keyVaultId, '/'))
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the APIM managed identity')
output apimIdentityId string = apimIdentity.id

@description('Principal ID of the APIM managed identity (for additional role assignments)')
output apimIdentityPrincipalId string = apimIdentity.properties.principalId

@description('Client ID of the APIM managed identity (for APIM configuration)')
output apimIdentityClientId string = apimIdentity.properties.clientId

@description('Resource ID of the AKS workload identity')
output aksIdentityId string = aksIdentity.id

@description('Principal ID of the AKS workload identity (for additional role assignments)')
output aksIdentityPrincipalId string = aksIdentity.properties.principalId

@description('Client ID of the AKS workload identity (for federated credential setup)')
output aksIdentityClientId string = aksIdentity.properties.clientId

@description('Name of the APIM managed identity')
output apimIdentityName string = apimIdentity.name

@description('Name of the AKS workload identity')
output aksIdentityName string = aksIdentity.name
