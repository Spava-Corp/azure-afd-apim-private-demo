# Decisions — ESLZ Deployment Analysis

## 2026-05-12: ESLZ Deployment Decisions (MacReady Lead + Childs Networking)

### Context
- **Project:** azure-afd-apim-private-demo
- **Deployment Target:** ESLZ demo tenant, Spaidoso Online Landing Zone
- **Authors:** MacReady (Lead), Childs (Network/Security)
- **Status:** DRAFT — Awaiting John's action items

---

## Tenant & Subscription

| Item | Value | Note |
|------|-------|------|
| **ESLZ Tenant Display Name** | Spaidoso | |
| **ESLZ Tenant ID** | `4d00acda-e258-43e1-bd90-9370a4d118e1` | Verified via CLI |
| **Provided Tenant ID** | `ef4ecf0b-a160-444b-a405-ce3bf1f98752` | **Mismatch — John must clarify** |
| **Target Subscription** | Spaidoso-LZ-Online | `966a8e3c-bd80-41dd-8910-506aab21e18b` |
| **Subscription Type** | Online Landing Zone | For internet-facing workloads, no on-prem dependency |

**HARD DEPENDENCY:** Clarify which tenant ID is correct before proceeding.

---

## Infrastructure Decisions

### 1. VNet Address Space — CRITICAL CONFLICT

**Current:** `10.0.0.0/16` (collides with standard ESLZ hub)  
**Recommendation:** Change to `10.1.0.0/16` (non-overlapping, allows future hub peering)

| Subnet | Current | Recommended | Size | Rationale |
|--------|---------|-------------|------|-----------|
| VNet | `10.0.0.0/16` | `10.1.0.0/16` | 65,536 IPs | Hub uses `10.0.0.0/16`; peering requires non-overlap |
| APIM | `10.0.1.0/24` | `10.1.1.0/24` | 254 IPs | Developer SKU needs ~5, Standard/Premium more but `/24` covers all |
| AKS | `10.0.2.0/22` | `10.1.2.0/22` | 1,022 IPs | ~250 pods + headroom (Azure CNI) |
| Private Endpoints | `10.0.6.0/24` | `10.1.6.0/24` | 254 IPs | 254 PE capacity (APIM PE + KV PE + future) |
| Bastion | `10.0.7.0/26` | `10.1.7.0/26` | 62 IPs | Azure minimum `/26` |

**Status:** Pending update to `main.bicepparam` and `vnet.bicep` defaults.

---

### 2. Private DNS Zones

**Current:** Local zones in spoke only (`privatelink.azure-api.net`, `privatelink.vaultcore.azure.net`)  
**Recommendation:** Local zones for demo; parameterize for centralized (hub) zones in production

**Missing zones identified:**
- `privatelink.westus2.azmk8s.io` — **Required** for AKS private cluster API server DNS
- `privatelink.azurecr.io` — Needed if using ACR for container images

**Future enhancement:** Add optional parameter `existingPrivateDnsZoneId` to modules to support centralized zone strategy.

---

### 3. NSG Adjustments for ESLZ Compliance

**Current state:** Well-structured, good microsegmentation already in place.

**Changes needed:**

| Issue | Recommendation | Priority |
|-------|-----------------|----------|
| No explicit Deny-All rules | Add `Priority 4000: Deny *` to inbound/outbound on all subnets | P1 |
| Private Endpoints NSG empty | Add: allow HTTPS 443 from VNet, deny-all others | P1 |
| APIM HTTPS rule too broad | Tighten to PE subnet only (`10.1.6.0/24`) | P2 |
| AKS missing egress rules | Add explicit outbound to ACR, AAD, Azure Monitor (443) | P2 |

---

### 4. Azure Policy Compliance Risks

| Policy | Impact | Mitigation |
|--------|--------|------------|
| **Deny-PublicIP** | Blocks public IPs | ✅ Compatible (Bastion needs exemption or private-only SKU) |
| **Deny-Subnet-Without-NSG** | All subnets need NSGs | ✅ Compatible (all have NSGs) |
| **Enforce-NSG-FlowLogs** | NSG flow logs required | ⚠️ Add NSG Flow Log resources to Bicep |
| **Deploy-DDoS-Standard** | DDoS Plan required | ⚠️ Add or link to hub DDoS plan |
| **Deny-Inbound-From-Internet** | No internet inbound in NSGs | ⚠️ Bastion NSG allows HTTPS — needs exemption |

**Action:** Run `az deployment group what-if` before Phase 1 deployment to surface policy denials.

---

## Deployment Configuration

### Region & Resource Naming

| Decision | Value | Rationale |
|----------|-------|-----------|
| **Region** | `westus2` | All existing ESLZ RGs in region; consistent pattern |
| **Resource Group** | `rg-afd-apim-private-demo-dev-wus2` | ESLZ naming standard: `rg-{workload}-{env}-{region}` |

---

### Kubernetes Version

**Current param:** `1.29` (❌ no longer available in westus2)  
**Recommendation:** `1.34` (GA default, good patch coverage)

| Version | Status | Available in westus2 | Recommendation |
|---------|--------|----------------------|-----------------|
| 1.29 | Dropped | ❌ | Must update |
| 1.30 | GA | ✅ | Older, fewer patches |
| 1.31 | GA | ✅ | Supported |
| 1.32 | GA | ✅ | Supported |
| 1.33 | GA | ✅ | Good stability |
| **1.34** | **GA** | **✅** | **✅ Recommended** |
| 1.35 | Latest | ✅ | Newer, fewer patches |

**Action:** Update `main.bicepparam` kubernetesVersion from `1.29` to `1.34`.

---

### APIM Configuration

| Decision | Value | Notes |
|----------|-------|-------|
| **SKU** | Developer | ~$50/mo; sufficient for demo; clear upgrade path to Premium |
| **VNet Mode** | Internal (private) | ✅ Supported by Developer SKU with stv2 |
| **Publisher Email** | **Must change** | Current `admin@contoso.com` is placeholder; will receive service notifications |
| **Private Endpoint** | Enabled | APIM PE in `snet-private-endpoints`; AFD connects via Private Link |
| **Private Link Service** | 2-phase deployment | Phase 1: skip (no ILB IP config yet); Phase 2: enable after K8s ILB deployed |

**Action:** John must provide real publisher email (e.g., `john@MngEnvMCAP484724.onmicrosoft.com` or corporate domain).

---

### Tags (ESLZ Requirement)

**Current:** Minimal (`project`, `environment`, `managedBy`)  
**Recommendation:** Add ESLZ-standard tags

```yaml
tags:
  project: 'afd-apim-private'
  environment: 'dev'
  managedBy: 'bicep'
  costCenter: '<John to provide>'
  owner: '<John's email>'
  applicationName: 'AFD-APIM-Private-Demo'
```

**Action:** John must provide `costCenter` and confirm `owner` email.

---

### Diagnostics & Monitoring

| Decision | Value | Notes |
|----------|-------|-------|
| **Log Analytics** | Local workspace in subscription | Workload-local logs; sufficient for demo |
| **ESLZ best practice** | Dual-send (local + hub Management sub) | Not required for demo; defer to production |

---

## Deployment Phasing

**Phase 1: Full infrastructure (45-60 min)**
- VNet, NSGs, DNS zones, Key Vault, Log Analytics, AKS, APIM, APIM PE, WAF, AFD
- AFD Private Endpoint will show as "Pending" — requires manual approval on APIM PE
- AKS LoadBalancer will be external (no Private Link Service yet)

**Phase 2: After Kubernetes services deployed (10-15 min)**
1. Deploy K8s services with `azure-load-balancer-internal` annotation
2. Retrieve ILB frontend IP config resource ID
3. Re-deploy Bicep with `aksLoadBalancerFrontendIpConfigId` to enable Private Link Service

---

## Estimated Monthly Cost (Dev/Demo)

| Resource | Cost |
|----------|------|
| AFD Premium | ~$350 |
| APIM Developer | ~$50 |
| AKS (2× Standard_DS2_v2) | ~$200 |
| Log Analytics | ~$12 |
| Key Vault + Private Endpoints + DNS | ~$25 |
| **TOTAL** | **~$640/mo** |

---

## John's Action Items (Blocking)

| # | Item | Must Change | Default/Rec. | Status |
|---|------|-------------|--------------|--------|
| 1 | Confirm tenant ID (provided vs. discovered) | ⚠️ **CRITICAL** | `4d00acda-...` is correct | Pending |
| 2 | APIM publisher email | ⚠️ **YES** | Provide real email | Pending |
| 3 | Kubernetes version | ⚠️ **YES** | Update from `1.29` → `1.34` | Pending |
| 4 | Cost center tag | ⚠️ **YES** | Provide value | Pending |
| 5 | Owner email tag | ✅ Confirm | John's email | Pending |
| 6 | VNet address space | ✅ Confirm or alt | `10.1.0.0/16` rec. | Pending |
| 7 | Region | ✅ Confirm | `westus2` | Pending |
| 8 | Subscription | ✅ Confirm | Spaidoso-LZ-Online | Pending |
| 9 | APIM SKU | ✅ Confirm | Developer | Pending |
| 10 | Diagnostics | ✅ Confirm | Single workspace | Pending |
| 11 | DNS zones | ✅ Confirm | Local to spoke | Pending |
| 12 | Deployment phasing | ✅ Confirm | 2-phase | Pending |

---

## Pre-Deployment Checklist

- [ ] Verify tenant ID (provided vs. actual)
- [ ] Update `main.bicepparam`: `kubernetesVersion` → `1.34`
- [ ] Update `main.bicepparam`: `apimPublisherEmail` → real email
- [ ] Add tags to `main.bicepparam`: `costCenter`, `owner`
- [ ] Update VNet/subnet prefixes: `10.0.x.x` → `10.1.x.x` in param and `vnet.bicep`
- [ ] Add missing DNS zones: `privatelink.westus2.azmk8s.io`, `privatelink.azurecr.io`
- [ ] Add explicit Deny-All NSG rules (P4000)
- [ ] Tighten APIM HTTPS rule to PE subnet only
- [ ] Add AKS egress rules for ACR, AAD, Monitor
- [ ] `az account set --subscription 966a8e3c-bd80-41dd-8910-506aab21e18b`
- [ ] `az group create -n rg-afd-apim-private-demo-dev-wus2 -l westus2`
- [ ] **Run `az deployment group what-if`** to check for policy denials
- [ ] Approve AFD Private Endpoint on APIM (post Phase 1)
- [ ] Deploy K8s workloads, get ILB IP config ID
- [ ] Deploy Phase 2 with `aksLoadBalancerFrontendIpConfigId`
- [ ] Validate: `curl https://<afd-endpoint>.azurefd.net/pet/1`

---

## Implementation Summary (2026-05-12)

### Blair (Infra Dev) — VNet Address Space & K8s Version Shift
**Status:** ✅ Completed

- VNet address space: `10.0.0.0/16` → `10.1.0.0/16`
- APIM subnet: `10.0.1.0/24` → `10.1.1.0/24`
- AKS subnet: `10.0.2.0/22` → `10.1.2.0/22`
- PE subnet: `10.0.6.0/24` → `10.1.6.0/24`
- Bastion subnet: `10.0.7.0/26` → `10.1.7.0/26`
- Kubernetes version: `1.29` → `1.34` (v1.29 no longer available in westus2)
- APIM publisher email: `admin@contoso.com` → `demo-admin@spaidoso.onmicrosoft.com`
- ARM template rebuilt in `infra/main.json`

**Files touched:** `infra/main.bicepparam`, `infra/main.bicep`, `infra/modules/networking/vnet.bicep`

---

### Childs (Network/Security) — NSG Hardening & Private DNS
**Status:** ✅ Completed

1. **Deny-All Rules (P4000):** All four NSGs (APIM, AKS, PE, Bastion) now have explicit inbound and outbound deny rules for audit compliance.
2. **APIM HTTPS Tightening:** Inbound rule source narrowed from `VirtualNetwork` to PE subnet only (`10.1.6.0/24`).
3. **PE Subnet NSG:** Populated with `Allow-HTTPS-From-VNet` (P100, inbound 443) for private endpoint traffic.
4. **AKS Outbound Allowlist:**
   - P110: ACR (container image pulls)
   - P120: AAD (control plane auth, managed identity tokens)
   - P130: AzureMonitor (Container Insights, metrics)
5. **AKS Private DNS Zone:** Added `privatelink.westus2.azmk8s.io` with VNet link and **new output `aksDnsZoneId`**.

**Files touched:** `infra/modules/networking/vnet.bicep` (NSG rules), `infra/modules/networking/private-dns-zones.bicep` (AKS zone + output)

**Cross-team note:** Blair may need to wire `aksDnsZoneId` output into `main.bicep` if AKS module consumes it.

---

---

## 2026-05-13: Least-Privilege RBAC for GitHub Actions OIDC (Childs)

**Date:** 2026-05-13  
**Author:** Childs (Network/Security)  
**Status:** Implemented  
**Scope:** SC-OnlineLZ-00 subscription (`6a170127-f4d5-4706-af95-e957af9cbcff`)

### Problem
Three service principals had **Contributor at subscription scope** on SC-OnlineLZ-00. This was an emergency fix to unblock CI/CD after discovering zero RBAC assignments on the OIDC-configured SPs. Subscription-scope Contributor violates least-privilege.

### Decision
Replace subscription-scope Contributor with two scoped roles on the single active SP.

**Active SP:** `github-actions-afd-apim-private-demo`  
- **App ID:** `ac563e84-f1dd-4582-bc7b-ce2b79089cb4`  
- **Object ID:** `b6098f74-6873-4bb9-a02c-42a22e88225c`

**Role Assignments (AFTER):**
| Role | Scope | Purpose |
|------|-------|---------|
| `Resource Group Contributor - GHA` (custom) | Subscription `6a170127-...` | `az group create` in workflow — RG read/write/delete only |
| `Contributor` (built-in) | RG `rg-afd-apim-private-demo-dev-wus2` | ARM deployments — all resource types within this RG |

**Unused SPs Cleaned (ZERO role assignments):**
- `afd-apim-private-demo-gha` (Contributor removed)
- `github-afd-apim-private-demo-deploy` (Contributor removed)

**Rationale:** 8+ resource providers in Bicep; fine-grained roles per provider would be fragile. Custom role limits subscription-level blast radius to RG management only. `az group create` requires subscription-level action.

**Future:** Delete unused app registrations if confirmed unnecessary. Add PR-scoped federated credential for what-if previews.

---

---

## 2026-05-13: Production Environment Federated Credential (Childs)

**Date:** 2026-05-13  
**Author:** Childs (Network/Security)  
**Status:** Implemented  
**Requested by:** John

### Problem

The Deploy Infrastructure workflow (`deploy-infra.yml`) failed with error `AADSTS700213` when running on `main`. The deploy job specifies `environment: production`, causing GitHub Actions OIDC to send the subject claim `repo:x3nc0n/azure-afd-apim-private-demo:environment:production`. No matching federated identity credential existed on the service principal.

### Context

The app registration `github-actions-afd-apim-private-demo` (appId: `ac563e84-f1dd-4582-bc7b-ce2b79089cb4`) had two existing federated credentials:

| Name | Subject |
|------|---------|
| `github-actions-main-branch` | `repo:x3nc0n/azure-afd-apim-private-demo:ref:refs/heads/main` |
| `github-actions-feat-branch` | `repo:x3nc0n/azure-afd-apim-private-demo:ref:refs/heads/feat/eslz-deployment-ready` |

These are **branch-based** credentials. When a workflow job uses `environment: production`, GitHub Actions sends an **environment-based** subject claim instead of a branch-based one. Both credential types are needed — the branch credential for jobs without an environment, and the environment credential for deployment jobs.

### Decision

Added a third federated credential:

| Name | Subject |
|------|---------|
| `github-actions-production-env` | `repo:x3nc0n/azure-afd-apim-private-demo:environment:production` |

Configuration:
- **Issuer:** `https://token.actions.githubusercontent.com`
- **Audience:** `api://AzureADTokenExchange`
- **Credential ID:** `8ab4f736-57cf-4928-9799-0fb482b5a756`

### Verification

- All three federated credentials confirmed present on the app registration.
- The `production` environment already exists in the GitHub repo (created 2026-05-13T17:12:55Z).
- No existing credentials were modified.
- No RBAC role assignments were changed.

### Risk

Low. This is standard OIDC federation configuration. The credential is scoped to only the `production` environment in this specific repository — it cannot be used by other repos or environments.

---

## Related References

- **ESLZ reference:** [Azure Landing Zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/enterprise-scale/architecture)
