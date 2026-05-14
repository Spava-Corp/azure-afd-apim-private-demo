# Security Controls — AFD → APIM → AKS Private Architecture

> **Author:** Kima (SecOps Engineer)  
> **Date:** 2026-05-07  
> **Architecture:** Azure Front Door Premium → APIM (PE-only, public disabled) → AKS (Private)  
> **Region:** West US 2

---

## Control Matrix

| # | Control | Protects Against | Enforcement Point | MITRE ATT&CK |
|---|---------|-----------------|-------------------|---------------|
| 1 | [WAF Prevention Mode](#1-waf-prevention-mode) | OWASP Top 10 attacks | AFD Edge (Global PoPs) | T1190 |
| 2 | [Bot Manager](#2-bot-manager) | Credential stuffing, scraping | AFD Edge | T1110, T1589 |
| 3 | [Rate Limiting](#3-rate-limiting) | DDoS, brute force, API abuse | AFD Edge + APIM | T1498, T1110 |
| 4 | [APIM Header Validation (Fallback)](#4-apim-header-validation-fallback) | Origin bypass when public access must stay enabled | WAF + APIM Policy | T1190, T1090 |
| 5 | [APIM Public Network Access Disabled](#5-apim-public-network-access-disabled) | Direct access, reconnaissance | APIM service + network architecture | T1595, T1190 |
| 6 | [No Public IP on AKS](#6-no-public-ip-on-aks) | Lateral movement, direct exploit | Network architecture | T1210, T1595 |
| 7 | [NSG Deny-All Default](#7-nsg-deny-all-default) | Lateral movement, port scanning | Subnet boundaries | T1046, T1021 |
| 8 | [Private Endpoints](#8-private-endpoints) | Data exfil via public internet | Azure backbone | T1048, T1071 |
| 9 | [Managed Identity (no secrets)](#9-managed-identity) | Credential theft, secret sprawl | APIM + AKS identity | T1528, T1552 |
| 10 | [mTLS Backend (demo: self-signed)](#10-mtls-backend) | Man-in-the-middle, impersonation | APIM → AKS connection | T1557, T1199 |
| 11 | [Response Header Sanitization](#11-response-header-sanitization) | Information disclosure | APIM outbound policy | T1592, T1590 |
| 12 | [Key Vault for Secrets](#12-key-vault-for-secrets) | Secret exposure in config | Azure Key Vault | T1552 |

---

## Detailed Controls

### 1. WAF Prevention Mode

**What it protects against:** SQL injection, XSS, LFI/RFI, command injection, protocol attacks, scanner detection, session fixation.

**Where enforced:** Azure Front Door Premium — WAF policy attached to AFD endpoint. Traffic is inspected at Microsoft's global PoPs before reaching your infrastructure.

**Rule set:** Microsoft Default Rule Set (DRS) 2.1 — all rule groups enabled.

**MITRE ATT&CK:**
- **T1190** (Exploit Public-Facing Application) — WAF blocks known exploit payloads
- **T1059** (Command and Scripting Interpreter) — Blocks injection patterns

**How to verify:**
```bash
# Send a SQL injection attempt — should return 403
curl -v "https://<afd-endpoint>.azurefd.net/api/pets?id=1' OR '1'='1"

# Send XSS payload — should return 403
curl -v "https://<afd-endpoint>.azurefd.net/api/pets" \
  -H "Content-Type: application/json" \
  -d '{"name": "<script>alert(1)</script>"}'

# Check WAF logs in Log Analytics
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| project TimeGenerated, ruleName_s, requestUri_s, clientIP_s
| order by TimeGenerated desc
```

---

### 2. Bot Manager

**What it protects against:** Automated credential stuffing, web scraping, vulnerability scanning, DDoS bots.

**Where enforced:** AFD WAF — Microsoft Bot Manager Rule Set 1.1.

**MITRE ATT&CK:**
- **T1110** (Brute Force) — Blocks known credential-stuffing bots
- **T1589** (Gather Victim Identity Info) — Blocks scraping bots

**How to verify:**
```bash
# Use a known bad bot user-agent — should be blocked
curl -v "https://<afd-endpoint>.azurefd.net/api/pets" \
  -H "User-Agent: masscan/1.0"

# Verify in WAF logs
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where ruleSetType_s == "Microsoft_BotManagerRuleSet"
| summarize count() by ruleName_s, action_s
```

---

### 3. Rate Limiting

**What it protects against:** Application-layer DDoS, brute force login attempts, API abuse, resource exhaustion.

**Where enforced:**
- **Layer 1 (AFD):** WAF custom rule — 1000 requests/minute per source IP → Block
- **Layer 2 (APIM):** Per-subscription rate limit — 100 requests/60s per API key

**MITRE ATT&CK:**
- **T1498** (Network Denial of Service) — Rate limits absorb volumetric attacks
- **T1110** (Brute Force) — Limits authentication attempts

**How to verify:**
```bash
# Rapid-fire requests to trigger rate limit (>1000 in 60s)
for i in $(seq 1 1100); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    "https://<afd-endpoint>.azurefd.net/api/pets/1"
done | sort | uniq -c
# Should see 403s after ~1000 requests

# Check rate limit blocks in logs
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where ruleName_s == "RateLimitPerSourceIP"
| where action_s == "Block"
| summarize BlockedRequests=count() by bin(TimeGenerated, 1m), clientIP_s
```

---

### 4. APIM Header Validation (Fallback Control)

**What it protects against:** Origin bypass when Azure limitations force APIM public access to remain enabled for Azure Front Door shared Private Link connectivity.

**When used:** Only if `publicNetworkAccess: 'Disabled'` breaks AFD private link provisioning, private endpoint approval/data-plane handshake, or AFD health probes in a specific region or SKU.

**Where enforced:**
- **Layer 1 (Optional WAF):** Custom rule blocks requests without valid `X-Azure-FDID`
- **Layer 2 (APIM fallback):** `check-header` policy validates exact AFD profile ID match

**MITRE ATT&CK:**
- **T1190** (Exploit Public-Facing Application) — Prevents bypass of edge security
- **T1090** (Proxy) — Prevents use of alternate entry points

**How to verify:**
```bash
# Fallback mode only: request with wrong AFD ID — should get 403
curl -v "https://<afd-endpoint>.azurefd.net/api/pets/1" \
  -H "X-Azure-FDID: fake-id-12345"

# Fallback mode only: legitimate request through AFD — should get 200
curl -v "https://<afd-endpoint>.azurefd.net/api/pets/1"
```

---

### 5. APIM Public Network Access Disabled

**What it protects against:** Direct internet access to the API management layer, reconnaissance scanning, exploit delivery.

**Where enforced:** APIM is deployed with `virtualNetworkType: 'None'` and `publicNetworkAccess: 'Disabled'`. Azure Front Door reaches the gateway only through the approved Private Endpoint path.

**MITRE ATT&CK:**
- **T1595** (Active Scanning) — No public listener means nothing to scan
- **T1190** (Exploit Public-Facing Application) — Can't exploit what you can't reach

**How to verify:**
```bash
# Verify Azure configuration
az apim show --name <apim-name> -g <rg> \
  --query "{publicNetworkAccess:publicNetworkAccess, publicIpAddresses:publicIpAddresses}"
# Should show publicNetworkAccess=Disabled and no public IPs

# Verify Private Endpoint exists
az network private-endpoint list -g <rg> \
  --query "[?contains(name,'apim')].{name:name, subnet:subnet.id}"

# Validate internet clients cannot reach APIM directly
curl -vk "https://<apim-name>.azure-api.net/api/pets/1"
# Should fail, timeout, or otherwise be inaccessible from the internet
```

---

### 6. No Public IP on AKS

**What it protects against:** Direct container exploitation, kubernetes API exposure, pod-level attacks from the internet.

**Where enforced:** AKS cluster with private API server + internal load balancer. Only reachable from APIM subnet.

**MITRE ATT&CK:**
- **T1210** (Exploitation of Remote Services) — No public k8s API
- **T1595** (Active Scanning) — Backend invisible from internet

**How to verify:**
```bash
# Verify AKS API is private
az aks show --name <aks-name> -g <rg> \
  --query "apiServerAccessProfile.enablePrivateCluster"
# Should return true

# Verify no public LB
kubectl get svc -A | grep -i loadbalancer
# All LBs should be internal (annotation: service.beta.kubernetes.io/azure-load-balancer-internal: "true")
```

---

### 7. NSG Deny-All Default

**What it protects against:** Lateral movement between subnets, port scanning within VNet, unauthorized service-to-service communication.

**Where enforced:** NSGs on each subnet with explicit deny-all rules at priority 4000. Only whitelisted traffic patterns allowed.

**MITRE ATT&CK:**
- **T1046** (Network Service Discovery) — Port scans blocked at NSG
- **T1021** (Remote Services) — No SSH/RDP allowed to backend

**How to verify:**
```bash
# Check effective NSG rules
az network nsg show --name <apim-nsg> -g <rg> \
  --query "securityRules[?access=='Deny']"

# Enable NSG flow logs and check for denied flows
AzureNetworkAnalytics_CL
| where FlowStatus_s == "D"  // Denied
| summarize count() by SrcIP_s, DestIP_s, DestPort_d
| order by count_ desc

# Try to reach AKS from a subnet that shouldn't have access
# (e.g., from a test VM not in APIM subnet) — should timeout
curl -v http://<aks-internal-ip>:8080/api/pets
```

---

### 8. Private Endpoints

**What it protects against:** Data exfiltration over public internet, man-in-the-middle on public paths, DNS hijacking.

**Where enforced:** All inter-service communication uses Private Endpoints. Traffic never leaves the Azure backbone.

**MITRE ATT&CK:**
- **T1048** (Exfiltration Over Alternative Protocol) — No public egress path
- **T1071** (Application Layer Protocol) — Traffic contained to private network

**How to verify:**
```bash
# Verify private endpoint DNS resolution (should return private IP)
nslookup <apim-name>.azure-api.net
# Should resolve to 10.x.x.x (private IP), not public

# Check private endpoint connections
az network private-endpoint-connection list \
  --id <resource-id> --query "[].{status:privateLinkServiceConnectionState.status}"
# All should show "Approved"
```

---

### 9. Managed Identity

**What it protects against:** Credential theft from config files, secret rotation failures, secret sprawl across environments.

**Where enforced:** User-assigned managed identities for APIM and AKS. Key Vault access via RBAC (no access policies with keys/secrets in config).

**MITRE ATT&CK:**
- **T1528** (Steal Application Access Token) — No tokens stored in config
- **T1552** (Unsecured Credentials) — No passwords/keys in source code or environment variables

**How to verify:**
```bash
# Verify APIM uses managed identity for Key Vault
az apim show --name <apim-name> -g <rg> \
  --query "identity.userAssignedIdentities"

# Verify no secrets in APIM named values (should use Key Vault references)
az apim nv list --service-name <apim-name> -g <rg> \
  --query "[?secret==true].{name:displayName, keyVault:keyVault}"

# Test identity can access Key Vault
az keyvault secret show --vault-name <vault> --name <secret> \
  --query "value" 2>&1 | head -1
```

---

### 10. mTLS Backend

**What it protects against:** Man-in-the-middle attacks between APIM and AKS, unauthorized services impersonating the backend, rogue APIM instances.

**Where enforced:** TLS between APIM and AKS backend. In demo mode: self-signed server cert on AKS, APIM skips validation. In production: mutual TLS with client cert from APIM.

**MITRE ATT&CK:**
- **T1557** (Adversary-in-the-Middle) — mTLS prevents interception
- **T1199** (Trusted Relationship) — Only cert-authenticated clients accepted

**How to verify:**
```bash
# Check server cert on AKS backend
openssl s_client -connect <aks-internal-ip>:443 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# Verify APIM backend config includes cert validation (production)
az apim backend show --service-name <apim-name> -g <rg> --backend-id <id> \
  --query "tls.validateCertificateChain"
```

---

### 11. Response Header Sanitization

**What it protects against:** Information disclosure — attackers learning backend technology stack, versions, and framework details.

**Where enforced:** APIM outbound policy removes `X-Powered-By`, `X-AspNet-Version`, overrides `Server` header.

**MITRE ATT&CK:**
- **T1592** (Gather Victim Host Information) — No tech stack leakage
- **T1590** (Gather Victim Network Information) — No internal architecture hints

**How to verify:**
```bash
# Check response headers — should NOT see technology-specific headers
curl -sI "https://<afd-endpoint>.azurefd.net/api/pets/1" | grep -iE "x-powered-by|x-aspnet|server"
# Server should show "API Gateway" only, no ASP.NET or IIS indicators
```

---

### 12. Key Vault for Secrets

**What it protects against:** Secrets in plain text (config files, env vars, source code), unauthorized secret access, lack of rotation.

**Where enforced:** Azure Key Vault with RBAC. APIM references certs/secrets via Key Vault URI (not inline). AKS uses CSI driver for secret injection.

**MITRE ATT&CK:**
- **T1552** (Unsecured Credentials) — All secrets centralized with audit trail

**How to verify:**
```bash
# Verify Key Vault access logging
az monitor diagnostic-settings list --resource <keyvault-id> \
  --query "[].logs[?category=='AuditEvent'].enabled"
# Should be true

# Check for secret access in audit logs
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, identity_claim_upn_s, id_s
```

---

## Architecture Security Posture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    INTERNET (Untrusted)                          │
└─────────────────────┬───────────────────────────────────────────┘
                      │
              ┌───────▼────────┐
              │ Azure Front Door│  ← Controls: WAF, Bot Mgr, Rate Limit,
              │    (Premium)    │    DDoS, TLS termination, fallback AFD ID injection
              └───────┬────────┘
                      │ Private Link (Azure backbone only)
              ┌───────▼────────┐
              │ Private Endpoint│  ← Control: NSG (VNet-only access)
              │    Subnet       │
              └───────┬────────┘
                      │
              ┌───────▼────────┐
              │      APIM       │  ← Controls: publicNetworkAccess disabled,
              │   (PE-only)     │    rate limit, managed identity,
              │                 │    header sanitization, no public ingress
              └───────┬────────┘
                      │ NSG-restricted (only ports 443/8080 to AKS subnet)
              ┌───────▼────────┐
              │      AKS        │  ← Controls: Private API server, NSG,
              │  (Private)      │    workload identity, mTLS server cert,
              │                 │    no public IP, internal LB only
              └─────────────────┘
```

---

## Testing Checklist

| Test | Expected Result | Validates Control |
|------|----------------|-------------------|
| SQLi payload via AFD | 403 Blocked | WAF DRS 2.1 |
| Known bad bot UA | 403 Blocked | Bot Manager |
| 1100 requests in 60s | 403 after ~1000 | Rate limiting |
| Direct APIM access from internet | Timeout / inaccessible | APIM public network access disabled |
| Fallback mode wrong `X-Azure-FDID` | 403 | APIM header validation fallback |
| Nmap APIM private IP from internet | No response | No public IP |
| curl AKS from non-APIM subnet | Timeout | NSG deny-all |
| DNS resolve APIM name | Private IP (10.x.x.x) | Private Endpoint |
| Check response headers | No tech stack info | Header sanitization |
| Key Vault audit log | Access events logged | KV + Managed ID |

---

## Incident Response Integration

These controls produce signals that should feed into Microsoft Sentinel:

| Signal Source | Sentinel Table | Alert Rule |
|---------------|---------------|------------|
| WAF blocks | `AzureDiagnostics` (FrontDoorWebApplicationFirewallLog) | High block rate from single IP |
| Rate limit triggers | `AzureDiagnostics` (FrontDoorWebApplicationFirewallLog) | Sustained rate limiting |
| NSG denies | `AzureNetworkAnalytics_CL` | Unexpected denied flows |
| Key Vault access | `AzureDiagnostics` (AuditEvent) | Access from unexpected identity |
| APIM 403s | `ApiManagementGatewayLogs` | Spike in auth failures |

---

*Security is not a feature — it's the architecture. Every layer assumes the one above it has failed.*
