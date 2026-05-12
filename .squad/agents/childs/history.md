# Childs — History

## Project Context
- **Project:** azure-afd-apim-private-demo
- **User:** John
- **Stack:** Azure Bicep, AKS, APIM, Azure Front Door, Private Link, Kubernetes
- **Description:** Zero-trust architecture demo — AFD Premium → APIM (internal) → AKS (internal LB). Target: ESLZ demo tenant.

## Learnings

### 2026-05-12 — ESLZ Networking Investigation
- **Address space conflict:** Project defaults to `10.0.0.0/16` which collides with standard ESLZ hub. Must shift to `10.1.0.0/16` for spoke deployment.
- **DNS zones are local-only:** `private-dns-zones.bicep` creates zones in the spoke. Acceptable for demo but needs parameterization for centralized (hub) DNS in production ESLZ.
- **Missing DNS zones:** AKS private cluster needs `privatelink.westus2.azmk8s.io`; ACR likely needs `privatelink.azurecr.io`.
- **NSG gaps:** No explicit deny-all rules (ESLZ policy may require them for auditability). PE subnet NSG is empty. APIM HTTPS inbound is too broad (allows from entire VNet, should restrict to PE subnet).
- **Bastion policy risk:** ESLZ Online LZ typically has Deny-PublicIP and Deny-Inbound-From-Internet policies. Bastion requires both — will need exemption or removal.
- **No hub peering needed for demo:** AFD uses Microsoft-managed Private Link, not VNet peering. Peering only needed if hub firewall egress or on-prem connectivity is required.
- **CLI access:** Could not access ESLZ demo tenant (ef4ecf0b-a160-444b-a405-ce3bf1f98752) from current CLI context. Recommendations based on standard ESLZ patterns.
- **Decision document:** Written to `.squad/decisions/inbox/childs-eslz-networking-decisions.md` with 12 action items.

### 2026-05-12 — NSG Hardening & DNS Zone Addition
- **Deny-all rules added:** All four NSGs (apimNsg, aksNsg, peNsg, bastionNsg) now have explicit priority-4000 Deny-All-Inbound and Deny-All-Outbound rules. This satisfies ESLZ audit requirements for explicit default-deny posture.
- **APIM HTTPS tightened:** `Allow-HTTPS-Inbound` source changed from `VirtualNetwork` to `10.1.6.0/24` (PE subnet only). Only AFD via Private Endpoint can reach APIM on 443.
- **PE NSG populated:** Was empty — now allows HTTPS (443) inbound from VirtualNetwork (priority 100) before deny-all.
- **AKS outbound rules added:** ACR (110), AAD (120), AzureMonitor (130) outbound allows on 443 before deny-all. These are the minimum egress paths for a private AKS cluster.
- **AKS DNS zone added:** `privatelink.westus2.azmk8s.io` zone created in `private-dns-zones.bicep` with VNet link and output, following existing pattern.
- **No address space changes:** Parameter defaults already updated by Blair to 10.1.x.x. NSG rules use new PE subnet prefix `10.1.6.0/24` directly.
- **Decision document:** Written to `.squad/decisions/inbox/childs-nsg-hardening.md`.
- **2026-05-12 (Blair cross-team):** Blair completed VNet address space readdressing (10.0→10.1) and K8s version update (1.29→1.34). ARM template rebuilt. All NSG rules now use correct 10.1.x.x CIDR blocks.
