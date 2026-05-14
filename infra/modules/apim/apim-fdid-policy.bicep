// APIM Global Inbound Policy — X-Azure-FDID header validation
// Rejects any request that does not carry the expected Azure Front Door profile ID.
// This is the fallback control when publicNetworkAccess cannot be disabled on APIM.
// See docs/decisions/apim-network-access.md for rationale.

@description('Name of the existing APIM service')
param apimName string

@description('Azure Front Door profile ID (GUID) for X-Azure-FDID header validation')
param frontDoorId string

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimName
}

var policyXml = replace('''<policies>
  <inbound>
    <check-header name="X-Azure-FDID" failed-check-httpcode="403" failed-check-error-message="Access denied - request must arrive through Azure Front Door." ignore-case="true">
      <value>__FDID__</value>
    </check-header>
    <base />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>''', '__FDID__', frontDoorId)

resource globalPolicy 'Microsoft.ApiManagement/service/policies@2023-05-01-preview' = {
  parent: apimService
  name: 'policy'
  properties: {
    format: 'xml'
    value: policyXml
  }
}
