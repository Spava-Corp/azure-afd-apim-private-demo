# Blair — History

## Project Context
- **Project:** azure-afd-apim-private-demo
- **User:** John
- **Stack:** Azure Bicep, AKS, APIM, Azure Front Door, Private Link, Kubernetes
- **Description:** Zero-trust architecture demo — AFD Premium → APIM (internal) → AKS (internal LB). Target: ESLZ demo tenant.

## Learnings
- **2026-05-12:** VNet address space shifted from 10.0.0.0/16 → 10.1.0.0/16 across all three Bicep files (main.bicepparam, main.bicep, vnet.bicep) to avoid ESLZ hub collision. All subnet defaults updated consistently.
- **2026-05-12:** Kubernetes version bumped 1.29 → 1.34 (1.29 EOL in target region).
- **2026-05-12:** APIM publisher email changed from contoso placeholder to demo-admin@spaidoso.onmicrosoft.com. Azure CLI context returned a managed-env email, so used the descriptive placeholder per team guidance.
- **2026-05-12:** ARM template (main.json) rebuilt via `az bicep build`. Pre-existing warnings in afd.bicep and apim.bicep are not from these changes.
- **2026-05-12:** Three files carry subnet/VNet defaults: main.bicepparam, main.bicep, and modules/networking/vnet.bicep. All three must stay in sync when changing address spaces.
- **2026-05-12 (Childs cross-team):** Childs added `aksDnsZoneId` output to `private-dns-zones.bicep` for AKS private cluster DNS resolution. May need to wire this into AKS module consumption in main.bicep.
