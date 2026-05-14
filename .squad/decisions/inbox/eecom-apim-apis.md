# EECOM APIM APIs Decision

- **Date:** 2026-05-14T17:31:25.663-05:00
- **Requested by:** John Spaid

## Decision
Deploy APIM registrations for the AKS-hosted Petstore and Podinfo backends as a dedicated module at `infra/modules/apim/apim-apis.bicep`, and invoke it from `infra/main.bicep` only during the second deployment phase when both `aksLoadBalancerFrontendIpConfigId` and `aksInternalLbIp` are provided.

## Rationale
The AKS internal load balancer IP is not available during the initial foundation deployment, so unconditional APIM backend configuration would either fail or point at an empty backend. Keeping the API registrations in a separate module lets APIM itself deploy in phase 1 while the backend API surfaces light up only after the internal LB and Private Link Service path are ready.

## Implementation Notes
- Petstore API path: `/petstore` → backend `http://<aksInternalLbIp>:8080`
- Podinfo API path: `/podinfo` → backend `http://<aksInternalLbIp>:9898`
- Both APIs use catch-all APIM operations for GET, POST, PUT, and DELETE and are associated with the built-in `unlimited` product.
