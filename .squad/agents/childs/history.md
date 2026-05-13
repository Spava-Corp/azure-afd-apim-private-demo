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

### 2026-05-13 — Least-Privilege RBAC Remediation for GitHub Actions OIDC
- **Root cause:** Three SPs had Contributor at subscription scope (SC-OnlineLZ-00). Only one SP (`github-actions-afd-apim-private-demo`, objectId `b6098f74-6873-4bb9-a02c-42a22e88225c`) is in use.
- **Unused SPs cleaned:** Removed all role assignments from `afd-apim-private-demo-gha` (objectId `66a37932-304d-4ed7-b15f-10b5cfea04ea`) and `github-afd-apim-private-demo-deploy` (objectId `425d3196-e468-4880-82ea-c012949d5bd5`).
- **Least-privilege model applied:** Replaced subscription-scope Contributor with two scoped roles:
  1. **Custom role "Resource Group Contributor - GHA"** (ID: `e22d8292-69a5-4844-b2bc-6016cf675120`) at subscription scope — only allows `Microsoft.Resources/subscriptions/resourceGroups/{read,write,delete}`. Needed for `az group create` in the CI/CD workflow.
  2. **Contributor** at resource group scope (`rg-afd-apim-private-demo-dev-wus2`) — allows full deployment of all resource types (VNet, NSGs, DNS zones, Key Vault, AKS, APIM, Private Endpoints, AFD, WAF) within the RG only.
- **Rationale for Contributor at RG scope:** The Bicep template deploys 8+ distinct resource providers (Network, ContainerService, ApiManagement, Cdn, KeyVault, OperationalInsights, etc.). Enumerating per-provider roles would be brittle and hard to maintain for a demo. Contributor at RG scope is the standard least-privilege boundary for ARM deployments.
- **Key file paths:** `.github/workflows/deploy-infra.yml` (CI/CD), `infra/main.bicep` (orchestrator), `infra/main.bicepparam` (parameters).
- **Decision document:** Written to `.squad/decisions/inbox/childs-least-privilege-rbac.md`.

### 2026-05-13 — Production Environment Federated Credential
- **Root cause:** Deploy Infrastructure workflow failed with `AADSTS700213` because the `deploy` job uses `environment: production`, which sends OIDC subject `repo:x3nc0n/azure-afd-apim-private-demo:environment:production`. No matching federated credential existed on the SP.
- **Existing credentials:** Two branch-based credentials existed (`ref:refs/heads/main` and `ref:refs/heads/feat/eslz-deployment-ready`) but environment-based claims are distinct from branch-based claims — both are needed.
- **Fix applied:** Added federated credential `github-actions-production-env` to app registration `github-actions-afd-apim-private-demo` (appId: `ac563e84-f1dd-4582-bc7b-ce2b79089cb4`) with subject `repo:x3nc0n/azure-afd-apim-private-demo:environment:production`.
- **GitHub environment:** Confirmed `production` environment already exists in the repo (created 2026-05-13T17:12:55Z).
- **No existing credentials modified.** No RBAC changes made.
- **Decision document:** Written to `.squad/decisions/decisions.md` — merged from inbox 2026-05-13T17:22Z.
- **Scribe processed:** Merged decision into decisions.md, deleted inbox file, wrote orchestration and session logs.
