# EECOM — History

## Project Context
- **Project:** Azure Front Door → APIM → AKS (Private Link) Demo
- **Stack:** Bicep, GitHub Actions, Azure (AFD, APIM, AKS, VNet, Private Link)
- **Owner:** John Spaid
- **Created:** 2026-05-13

## Learnings
- 2026-05-14T08:10:57.271-05:00 — Preferred APIM posture is `virtualNetworkType: 'None'` with `publicNetworkAccess: 'Disabled'` in `infra/modules/apim/apim.bicep`; use `X-Azure-FDID` validation only as a fallback for shared Private Link limitations.
- 2026-05-14T08:10:57.271-05:00 — Network access rationale is documented in `docs/decisions/apim-network-access.md`, with supporting updates in `README.md`, `docs/architecture-plan-afd-apim-private.md`, and `docs/security-controls.md`.
- 2026-05-14T09:50:07.763-05:00 — AFD origins targeting APIM must use the deployed APIM gateway hostname derived from `apim.outputs.apimName`; composing `${prefix}-apim-${environment}.azure-api.net` breaks probe resolution when the APIM module appends a unique suffix.
- 2026-05-14T17:31:25.663-05:00 — APIM backend API definitions now live in `infra/modules/apim/apim-apis.bicep`, with `infra/main.bicep` wiring them after the FDID policy and gating deployment on both `aksLoadBalancerFrontendIpConfigId` and `aksInternalLbIp` for the second-phase AKS/PLS rollout.
- 2026-05-14T17:31:25.663-05:00 — Petstore is exposed in APIM at `/petstore` and forwarded to `http://<aksInternalLbIp>:8080`; Podinfo is exposed at `/podinfo` and forwarded to `http://<aksInternalLbIp>:9898`, with both APIs attached to the built-in `unlimited` product.
