# Azure Front Door → APIM → AKS (Private Link) Demo

[![Build ARM Template](https://github.com/Spava-Corp/azure-afd-apim-private-demo/actions/workflows/build-arm.yml/badge.svg)](https://github.com/Spava-Corp/azure-afd-apim-private-demo/actions/workflows/build-arm.yml)
[![Deploy Infrastructure](https://github.com/Spava-Corp/azure-afd-apim-private-demo/actions/workflows/deploy-infra.yml/badge.svg)](https://github.com/Spava-Corp/azure-afd-apim-private-demo/actions/workflows/deploy-infra.yml)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fx3nc0n%2Fazure-afd-apim-private-demo%2Fmain%2Finfra%2Fmain.json)

> **Zero-trust architecture demo:** All backend traffic flows over Azure Private Link — no public IPs on APIM or AKS.

## Architecture

```
┌──────────────┐     ┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Internet   │────▶│  Azure Front Door   │────▶│   API Management │────▶│   AKS Cluster   │
│   (Users)    │     │  (Premium + WAF)    │     │ (PE-only, No     │     │  (Internal LB)  │
│              │     │                     │     │  Public Access)  │     │                 │
└──────────────┘     └─────────────────────┘     └──────────────────┘     └─────────────────┘
                          │                           │                         │
                          │ DRS 2.1 + Bot Mgr         │ Private Link            │ Private Link Svc
                          │ Rate Limiting             │ publicNetworkAccess     │ No Public IP
                          │ TLS 1.2+                  │ Disabled (stv2)         │ Azure CNI
                          ▼                           ▼                         ▼
                     WAF Policy               Private Endpoint            Internal Load Balancer
                     (Prevention Mode)        (Auto-approved)             (Petstore + Podinfo)
```

## What Gets Deployed

| Resource | SKU/Tier | Purpose |
|----------|----------|---------|
| Azure Front Door | Premium | Global L7 load balancer + WAF + Private Link origin |
| WAF Policy | Prevention | DRS 2.1 + Bot Manager 1.1 managed rules |
| API Management | Developer (stv2) | PE-only API gateway with `publicNetworkAccess: Disabled` |
| AKS Cluster | Standard | Private Kubernetes with Azure CNI |
| Virtual Network | /16 | 4 subnets: APIM, AKS (/22), PE, Bastion |
| Key Vault | Standard | RBAC-enabled secrets management |
| Log Analytics | Per-GB | Centralized diagnostics + Sentinel-ready |
| NSGs | Per-subnet | Zero-trust microsegmentation |

## Prerequisites

- Azure subscription with Owner or Contributor role for interactive/manual deployment
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) v2.50+
- [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.27+
- [Helm](https://helm.sh/docs/intro/install/) v3.12+
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (bundled with Azure CLI)

### GitHub Actions deployment prerequisites

If you deploy with GitHub Actions OIDC, the service principal must have enough RBAC to create Key Vault role assignments during the Bicep deployment.

- **Resource group scope:** **Owner** (or User Access Administrator + Contributor) for Key Vault role assignments (`Microsoft.Authorization/roleAssignments/write`)
- **Subscription scope:** **Contributor** (or equivalent) is needed for `az provider register` to register resource providers like `Microsoft.Cdn` and `Microsoft.Network`
- The workflow automatically registers required providers on first deploy

## Quick Start

```bash
# 1. Clone
git clone https://github.com/x3nc0n/azure-afd-apim-private-demo.git
cd azure-afd-apim-private-demo

# 2. Deploy infrastructure (~45 min for APIM)
az deployment group create \
  --resource-group rg-afd-apim-demo \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam

# 3. Deploy K8s backends (after AKS is ready)
cd infra/k8s && chmod +x deploy.sh && ./deploy.sh

# 4. CD pipeline auto-approves the AFD Private Endpoint on APIM (manual approval only for out-of-band deploys)
```

## Folder Structure

```
├── infra/
│   ├── main.bicep              # Orchestrator — deploys all modules
│   ├── main.bicepparam         # Default parameters
│   ├── modules/
│   │   ├── networking/         # VNet, subnets, NSGs, Bastion
│   │   ├── apim/               # APIM PE-only gateway + Private Endpoint
│   │   ├── aks/                # AKS + Private Link Service
│   │   ├── front-door/         # AFD Premium + WAF + origins
│   │   ├── monitoring/         # Log Analytics + Diagnostic Settings
│   │   └── security/           # Key Vault (RBAC mode)
│   └── k8s/
│       ├── petstore/           # Helm chart — Swagger Petstore v3
│       ├── podinfo/            # Helm chart — Podinfo health check
│       ├── internal-lb/        # Helm chart — Azure internal LB services
│       └── deploy.sh           # One-shot K8s deployment script
├── docs/
│   ├── architecture-plan-afd-apim-private.md
│   ├── security-controls.md
│   └── decisions/
│       └── apim-network-access.md
├── .github/workflows/
│   └── build-arm.yml           # Auto-builds ARM JSON from Bicep
└── README.md
```

## Cost Estimate

| Resource | Monthly Cost (approx) |
|----------|----------------------|
| Azure Front Door Premium | ~$50 |
| WAF Policy | ~$20 |
| APIM Developer | ~$50 |
| AKS (2-node Standard_D4s_v3) | ~$280 |
| Log Analytics (5 GB/day) | ~$100 |
| Key Vault + VNet + NSGs | ~$30 |
| **Total** | **~$530–650/mo** |

> 💡 For production, upgrade APIM to Standard/Premium (~$700+/mo) and AKS to 3+ nodes.

## Security Highlights

- ✅ **APIM `publicNetworkAccess: Disabled`** and **no public IPs on AKS** — all traffic stays on Private Link
- ✅ **WAF in Prevention mode** — DRS 2.1 + Bot Manager blocks known threats
- ✅ **TLS 1.2+ enforced** at AFD edge
- ✅ **NSG microsegmentation** — each subnet has deny-all default + explicit allows
- ✅ **Key Vault RBAC** — no legacy access policies
- ✅ **Managed Identity** — no service principal secrets
- ✅ **Diagnostic Settings** — all resources log to Log Analytics (Sentinel-ready)
- ✅ **Azure Bastion** — secure jump-box access without public SSH

## Documentation

- [Architecture Deep-Dive](docs/architecture-plan-afd-apim-private.md) — full design rationale
- [Security Controls](docs/security-controls.md) — compliance mapping
- [APIM Network Access Decision](docs/decisions/apim-network-access.md) — preferred lockdown and documented fallback

## Deploy to Azure Button

The "Deploy to Azure" button at the top uses a compiled ARM template (`infra/main.json`).  
A GitHub Actions workflow automatically rebuilds it from Bicep on every push to `main`.

If deploying for the first time after a fork, trigger the workflow manually or run:
```bash
az bicep build --file infra/main.bicep --outfile infra/main.json
```

## License

[MIT](LICENSE) — use freely for demos, POCs, and learning.
