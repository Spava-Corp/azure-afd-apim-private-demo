# Squad Decisions

## Active Decisions

### GitHub Actions OIDC Authentication Setup

**Date:** 2026-05-12  
**Author:** Blair (Infra Dev)  
**Status:** Implemented

Created Entra ID app registration `github-actions-afd-apim-private-demo` with federated credentials for GitHub OIDC (workload identity federation). No client secret used — authentication via GitHub's OIDC provider.

**Details:**
- **App Registration:** github-actions-afd-apim-private-demo (appId: ac563e84-f1dd-4582-bc7b-ce2b79089cb4)
- **Service Principal:** b6098f74-6873-4bb9-a02c-42a22e88225c
- **Federated Credentials:** main branch, feat/eslz-deployment-ready branch
- **Role:** Contributor on subscription 45da0317-4f5c-4be6-ae96-e8945b6f4c57
- **GitHub Secrets:** AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
- **Verified:** Workflow #25801346869 passed

**Notes:** Legacy app reg afd-apim-private-demo-gha exists — cleanup recommended. Consider resource group scoping for production. No PR credential yet.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
