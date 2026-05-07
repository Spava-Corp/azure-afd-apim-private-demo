# Architecture Plan: Azure Front Door → APIM → Backend (Fully Private)

> **Status:** DRAFT — Decision points pending  
> **Author:** McNulty (Architecture Lead)  
> **Date:** 2026-05-07  
> **Scope:** End-to-end private connectivity from internet edge to backend APIs

---

## 1. Architecture Overview

### Traffic Flow

```
Internet Client
    │
    ▼
┌─────────────────────────────┐
│  Azure Front Door (Premium)  │  ← TLS termination, global load balancing
│  + WAF Policy (Prevention)   │  ← OWASP 3.2, bot protection, rate limiting
└─────────────┬───────────────┘
              │ Private Link (Microsoft-managed VNet)
              ▼
┌─────────────────────────────┐
│  Private Endpoint (APIM)     │  ← No public IP exposed
│  in Hub/Spoke VNet           │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Azure API Management        │  ← Internal mode (stv2 platform)
│  (Premium SKU, internal)     │  ← Policy enforcement, throttling, auth
└─────────────┬───────────────┘
              │ Private Endpoint
              ▼
┌─────────────────────────────┐
│  Backend API (Docker on VM)  │  ← No public IP
│  or AKS with internal LB     │  ← Private endpoint / Private Link Service
└─────────────────────────────┘
```

### Key Architectural Properties

| Property | Value |
|----------|-------|
| Public internet exposure | AFD only (Microsoft PoPs) |
| APIM public IP | None (internal mode) |
| Backend public IP | None |
| Inter-service traversal | Azure backbone only |
| WAF enforcement point | AFD edge |
| Auth model | Managed Identity + OAuth2 |

---

## 2. Decision Points

### 2.1 Azure Front Door Tier

| Factor | Standard | Premium |
|--------|----------|---------|
| Private Link origin support | ❌ No | ✅ Yes |
| WAF with managed rules | ✅ | ✅ |
| Bot protection | ❌ | ✅ |
| DDoS protection | Basic | Enhanced |
| Custom rules limit | 100 | 200 |
| Price | Lower | ~3× higher |

**Decision required:** Premium is **mandatory** for this architecture. Private Link origins (connecting AFD to APIM's private endpoint) are a Premium-only feature. No workaround exists at Standard tier.

**Recommendation:** ✅ Premium

---

### 2.2 WAF Policy Configuration

| Decision | Options | Recommendation |
|----------|---------|----------------|
| Mode | Detection / Prevention | **Prevention** for production; Detection for initial rollout to baseline false positives |
| Managed rule set | Microsoft Default Rule Set (DRS) 2.1 | ✅ Use DRS 2.1 — covers OWASP Top 10 |
| Bot manager | Microsoft Bot Manager | ✅ Enable — blocks scrapers, credential stuffers |
| Rate limiting | Custom rules | ✅ Add per-IP rate limit (e.g., 1000 req/min) |
| Geo-filtering | Custom rules | Depends on audience — lock to expected countries |
| Custom rules | IP allowlist, header validation | Add `X-Azure-FDID` header validation at APIM to prevent bypass |

**Decision required:**
1. Start in Detection or Prevention mode?
2. Which geo-regions to allow/block?
3. Rate limit thresholds per use case?

---

### 2.3 Private Link vs Private Endpoint

| Concept | What it is | Used where |
|---------|-----------|-----------|
| **Private Endpoint** | A NIC in *your* VNet with a private IP, connected to a PaaS service | APIM, backend services, storage |
| **Private Link Service** | *Your* service exposed behind an Azure Load Balancer, reachable via Private Endpoint from *other* VNets/subscriptions | Backend APIs behind ILB if using custom services |
| **AFD Private Link origin** | AFD uses Microsoft-managed VNet to reach your Private Endpoint | AFD → APIM connection |

**Decision required:**
- For AFD → APIM: Use **Private Endpoint** (AFD connects via its managed VNet)
- For APIM → Backend: Use **Private Endpoint** if backend is a PaaS (App Service, AKS), or **Private Link Service** if backend is behind a Standard Load Balancer (VMs)

---

### 2.4 APIM SKU Selection

| SKU | VNet Integration | Private Endpoint Support | Multi-region | Price (est.) |
|-----|-----------------|-------------------------|--------------|-------------|
| Consumption | ❌ | ❌ | ❌ | Pay-per-call |
| Developer | ✅ External/Internal | ✅ (stv2) | ❌ | ~$50/mo |
| Basic (v2) | ❌ | ✅ Inbound only | ❌ | ~$160/mo |
| Standard | ✅ External/Internal | ✅ (stv2) | ❌ | ~$700/mo |
| Standard (v2) | ❌ | ✅ Inbound only | ❌ | ~$350/mo |
| Premium | ✅ External/Internal | ✅ (stv2) | ✅ | ~$2,800/mo |

**Decision required:**
- For **demo/dev**: Developer SKU (supports internal VNet mode, cheap)
- For **production**: Premium SKU (multi-region, 99.99% SLA, full VNet injection)
- Must be on **stv2 compute platform** for private endpoint support

**Recommendation:** Developer for POC, Premium for prod.

---

### 2.5 APIM Deployment Mode

| Mode | Behavior | Use case |
|------|----------|----------|
| External | APIM gateway has public IP + VNet connectivity | Public API with VNet backend access |
| Internal | APIM gateway has private IP only, no public endpoint | ✅ Our architecture — all traffic via AFD Private Link |
| None (no VNet) | Standard PaaS, no VNet injection | Not suitable here |

**Decision required:** **Internal mode** is correct for this architecture. APIM is only reachable via Private Endpoint from AFD.

---

### 2.6 Backend Compute Choice

| Option | Pros | Cons | Demo suitability |
|--------|------|------|-----------------|
| Docker on VM | Simple, full control, easy to understand | Manual patching, no orchestration | ✅ Best for demo clarity |
| AKS (internal) | Production-grade, scalable | Complex setup, overkill for demo | Good for prod reference |
| Container Instances | Serverless containers | No VNet integration without caveats | ❌ Not ideal |
| App Service (internal) | Managed, easy | ASE required for full isolation (expensive) | Possible but pricey |

**Recommendation for demo:** Docker on a single VM (Ubuntu, no public IP, accessed via Private Link Service behind ILB). Clear, inspectable, cheap.

**Recommendation for production:** AKS with internal load balancer + Private Link Service.

---

### 2.7 DNS Resolution Strategy

| Zone | Purpose | Records |
|------|---------|---------|
| `privatelink.azure-api.net` | APIM private endpoint resolution | A record → APIM private IP |
| `privatelink.blob.core.windows.net` | Storage (if used) | A record → storage private IP |
| Custom (e.g., `api.contoso.com`) | AFD custom domain | CNAME → AFD endpoint |
| VNet-linked private DNS zones | Ensures VM/AKS can resolve private endpoints | Auto-registration |

**Decision required:**
1. Custom domain name for AFD?
2. Whether to use Azure Private DNS Resolver for hybrid (on-prem) resolution?
3. DNS zone placement (hub VNet vs dedicated subscription)?

---

### 2.8 TLS/Certificate Strategy

| Termination Point | Certificate | Notes |
|-------------------|-------------|-------|
| AFD (edge) | AFD-managed cert or BYOC (Key Vault) | ✅ TLS 1.2+ enforced |
| AFD → APIM (Private Link) | APIM default cert (*.azure-api.net) or custom | Traffic stays on Azure backbone — still encrypted |
| APIM → Backend | Self-signed or internal CA | mTLS recommended for zero-trust |

**Decision required:**
1. Use AFD-managed certs (free, auto-renew) or bring your own from Key Vault?
2. Custom domain on APIM gateway?
3. mTLS between APIM and backend?

---

### 2.9 Network Security Groups (NSGs)

| Subnet | Inbound Allow | Inbound Deny | Outbound Allow |
|--------|--------------|--------------|----------------|
| APIM subnet | AzureFrontDoor.Backend service tag, port 443 | All other | Azure (for management), backend subnet |
| Backend subnet | APIM subnet, port 8080/443 | All other | Azure (for updates), Internet (deny or via NAT) |
| Private Endpoint subnet | N/A (PE doesn't need NSG on its subnet, but supported) | — | — |

**Decision required:**
1. Enable NSG flow logs for audit?
2. Use Azure Firewall for east-west traffic inspection?
3. Application Security Groups for micro-segmentation?

---

### 2.10 Monitoring & Diagnostics

| Layer | Tool | What to capture |
|-------|------|----------------|
| AFD | Diagnostic Settings → Log Analytics | Access logs, WAF logs, health probe logs |
| WAF | WAF logs (per-rule matches) | Blocked requests, anomaly scores |
| APIM | Built-in analytics + Diagnostic Settings | Request latency, 4xx/5xx rates, policy failures |
| APIM | Application Insights | End-to-end distributed tracing |
| Backend VM | Azure Monitor Agent | Syslog, Docker logs, metrics |
| Network | NSG Flow Logs → Traffic Analytics | Connection patterns, anomalies |
| Platform | Azure Activity Log | Control plane changes |

**Decision required:**
1. Log Analytics workspace — shared or dedicated?
2. Retention period (30d? 90d? 365d?)?
3. Alert rules — what SLOs to target?

---

## 3. Security Considerations (Zero-Trust Alignment)

### Why this architecture is zero-trust:

| Principle | Implementation |
|-----------|---------------|
| **Verify explicitly** | WAF validates every request; APIM enforces OAuth2/subscription keys; mTLS to backend |
| **Least privilege** | NSGs restrict east-west; managed identity scoped to specific resources |
| **Assume breach** | No lateral movement path — backend only reachable from APIM; APIM only reachable from AFD |

### Specific controls:

1. **No public IP on APIM** — Internal mode, only Private Endpoint inbound
2. **No public IP on backend** — VM/AKS has no public IP; only reachable via Private Link Service
3. **WAF at the edge** — DRS 2.1 + bot manager + rate limiting before traffic hits your infra
4. **Private endpoints eliminate public internet traversal** — All inter-service traffic on Azure backbone
5. **NSG rules** — Explicit allow-list; deny all by default
6. **Managed Identity** — APIM authenticates to backend via system-assigned MI; no secrets in config
7. **DDoS Protection** — AFD provides built-in L3/L4 DDoS; optionally add Azure DDoS Protection Plan for VNet resources
8. **AFD ID validation** — APIM policy checks `X-Azure-FDID` header to prevent origin bypass
9. **Key Vault for secrets** — Certificates, named values stored in Key Vault with RBAC access

---

## 4. Demo Backend Suggestions

### Option A: **httpbin** (kennethreitz/httpbin)

| Attribute | Detail |
|-----------|--------|
| What | HTTP request/response testing service |
| Endpoints | `/get`, `/post`, `/status/{code}`, `/headers`, `/ip`, `/delay/{n}`, `/json`, `/xml` |
| Docker | `docker run -p 80:80 kennethreitz/httpbin` |
| Demo value | Shows APIM routing, transformation, caching clearly |
| Pros | Dead simple, well-known, many endpoints, zero config |
| Cons | Not a "real" API — purely echo/test |

### Option B: **JSON Placeholder** (typicode/json-server)

| Attribute | Detail |
|-----------|--------|
| What | Fake REST API with CRUD operations |
| Endpoints | `/posts`, `/comments`, `/users`, `/todos` (full CRUD) |
| Docker | Custom Dockerfile with `json-server --watch db.json` |
| Demo value | Shows real CRUD routing, filtering, pagination through APIM |
| Pros | Realistic REST patterns, customizable data, very lightweight |
| Cons | Needs a small db.json file; not as many built-in endpoint types |

### Option C: **Swagger Petstore** (swagger-api/swagger-petstore)

| Attribute | Detail |
|-----------|--------|
| What | OpenAPI-spec demo API (pets, orders, users) |
| Endpoints | `/pet`, `/store/order`, `/user` with full CRUD + file upload |
| Docker | `docker run -p 8080:8080 swaggerapi/petstore3` |
| Demo value | Has OpenAPI spec → can import directly into APIM |
| Pros | ✅ **Best for APIM demo** — OpenAPI import, Swagger UI built-in, realistic schema |
| Cons | Slightly heavier (Java); no persistent data |

### 🏆 Recommendation: **Swagger Petstore**

- APIM can **import the OpenAPI spec directly** → auto-generates API definitions, policies, and documentation
- Swagger UI gives visual confirmation the backend is working
- Multiple resources (pets, store, users) demonstrate APIM routing and policy per-operation
- Well-maintained, official Swagger project

**Runner-up:** httpbin for pure connectivity/WAF testing (use both — httpbin for smoke tests, Petstore for the full demo).

---

## 5. Bicep Module Structure

```
infra/
├── main.bicep                    # Orchestrator — deploys modules in order
├── main.bicepparam               # Environment-specific parameters
├── modules/
│   ├── networking/
│   │   ├── vnet.bicep            # Hub VNet, subnets, NSGs
│   │   ├── private-dns-zones.bicep  # All private DNS zones
│   │   └── bastion.bicep         # Optional — for VM access during dev
│   ├── front-door/
│   │   ├── afd.bicep             # AFD profile, endpoint, routes
│   │   ├── waf-policy.bicep      # WAF policy (rules, custom rules)
│   │   └── origin-group.bicep    # Origin group + Private Link origin
│   ├── apim/
│   │   ├── apim.bicep            # APIM instance (internal mode)
│   │   ├── apim-private-endpoint.bicep  # PE for AFD connectivity
│   │   └── apim-apis.bicep       # API definitions (post-deploy)
│   ├── backend/
│   │   ├── vm.bicep              # Ubuntu VM, cloud-init for Docker
│   │   ├── load-balancer.bicep   # Internal LB (Standard)
│   │   └── private-link-service.bicep  # PLS for APIM to reach backend
│   ├── security/
│   │   ├── key-vault.bicep       # Key Vault for certs/secrets
│   │   ├── managed-identity.bicep  # User-assigned MI
│   │   └── nsg-rules.bicep       # NSG rule definitions
│   └── monitoring/
│       ├── log-analytics.bicep   # Workspace
│       ├── diagnostic-settings.bicep  # All resource diagnostics
│       └── app-insights.bicep    # For APIM tracing
└── scripts/
    ├── deploy.ps1                # Deployment orchestration script
    └── configure-apim-apis.ps1   # Post-deploy API import
```

### Parameter Structure

```
infra/
├── parameters/
│   ├── dev.bicepparam            # Dev environment (Developer SKU, small VM)
│   ├── staging.bicepparam        # Staging (Standard SKU, mirrors prod networking)
│   └── prod.bicepparam           # Production (Premium SKU, multi-region)
```

### Module Dependencies (Deployment Graph)

```
networking/vnet ──┬──→ security/key-vault
                  ├──→ apim/apim (needs subnet)
                  ├──→ backend/vm (needs subnet)
                  └──→ networking/private-dns-zones

security/key-vault ──→ front-door/afd (cert reference)

backend/vm ──→ backend/load-balancer ──→ backend/private-link-service

apim/apim ──→ apim/apim-private-endpoint ──→ front-door/origin-group

front-door/waf-policy ──→ front-door/afd

monitoring/log-analytics ──→ monitoring/diagnostic-settings (all resources)
```

---

## 6. Implementation Order

### Phase 1: Foundation (Day 1)

| Step | Resource | Why first |
|------|----------|-----------|
| 1.1 | Resource Group(s) | Container for everything |
| 1.2 | Log Analytics Workspace | Needed by diagnostic settings on all subsequent resources |
| 1.3 | Key Vault | Store certs/secrets before other resources reference them |
| 1.4 | VNet + Subnets + NSGs | Network foundation — everything else deploys into this |
| 1.5 | Private DNS Zones | Link to VNet before creating private endpoints |

### Phase 2: Backend (Day 1-2)

| Step | Resource | Why this order |
|------|----------|---------------|
| 2.1 | VM (Ubuntu + Docker + Petstore) | Backend must exist before APIM can route to it |
| 2.2 | Internal Load Balancer | Frontend for the VM(s) |
| 2.3 | Private Link Service | Exposes ILB for APIM private endpoint consumption |

### Phase 3: API Management (Day 2-3)

| Step | Resource | Why this order |
|------|----------|---------------|
| 3.1 | APIM (internal mode, stv2) | ⚠️ Takes 30-45 minutes to deploy |
| 3.2 | APIM Private Endpoint | Creates the PE that AFD will target |
| 3.3 | DNS A record in private zone | So AFD can resolve APIM's private IP |
| 3.4 | Import Petstore OpenAPI into APIM | Configure APIs, policies |

### Phase 4: Edge (Day 3)

| Step | Resource | Why this order |
|------|----------|---------------|
| 4.1 | WAF Policy | Must exist before AFD references it |
| 4.2 | AFD Profile (Premium) | Creates the global endpoint |
| 4.3 | AFD Origin Group + Private Link Origin | Points to APIM private endpoint — **requires approval** |
| 4.4 | AFD Route | Maps paths to origin group |
| 4.5 | Custom domain + cert (optional) | Final DNS cutover |

### Phase 5: Validation & Hardening (Day 3-4)

| Step | Action |
|------|--------|
| 5.1 | Approve Private Endpoint connection on APIM (AFD PE connection shows "Pending") |
| 5.2 | Test end-to-end: `curl https://<afd-endpoint>.azurefd.net/pet/1` |
| 5.3 | Verify WAF blocks — send malicious payload, confirm 403 |
| 5.4 | Enable diagnostic settings on all resources |
| 5.5 | Configure alerts (5xx spike, WAF block rate, latency P99) |
| 5.6 | Verify no public access path exists (nmap APIM IP from internet → timeout) |

---

## 7. Open Questions for User Decision

Before implementation begins, the following decisions are needed:

| # | Question | Impact |
|---|----------|--------|
| 1 | Custom domain name? (e.g., `api.contoso.com`) | AFD config, certificate provisioning |
| 2 | APIM SKU for initial deployment? (Developer vs Premium) | Cost, deployment time |
| 3 | WAF start mode? (Detection to baseline, or straight to Prevention?) | Risk of blocking legitimate traffic |
| 4 | Geo-filtering requirements? | WAF custom rules |
| 5 | Backend: Docker-on-VM or AKS? | Complexity, cost |
| 6 | mTLS between APIM and backend? | Certificate management overhead |
| 7 | Azure region(s)? | Affects AFD PoP selection, latency |
| 8 | Existing VNet/subscription to integrate with, or greenfield? | Networking approach |
| 9 | Log retention period? | Cost, compliance |
| 10 | Budget constraints? | SKU selection across all services |

---

## 8. Cost Estimate (Ballpark — Demo/Dev)

| Resource | SKU | Est. Monthly Cost |
|----------|-----|-------------------|
| Azure Front Door Premium | Base + per-request | ~$350 + traffic |
| WAF Policy | Premium tier | Included with AFD |
| APIM | Developer | ~$50 |
| VM (backend) | Standard_B2s | ~$35 |
| Load Balancer | Standard (internal) | ~$20 |
| Private Link Service | — | Free (data transfer charges) |
| Private Endpoints (×3) | — | ~$7.50/mo each |
| Key Vault | Standard | ~$5 |
| Log Analytics | 5GB/day | ~$12 |
| **Total (dev/demo)** | | **~$500/mo** |

Production with Premium APIM + AKS: **~$4,000-6,000/mo**

---

*This document is the decision framework. Once decisions are locked, Bicep implementation begins.*
