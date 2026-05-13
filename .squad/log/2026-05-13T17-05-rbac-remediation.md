# Session Log — RBAC Remediation (2026-05-13T17:05)

**Session:** Least-privilege RBAC remediation for GitHub Actions OIDC  
**Agent:** Childs (Network/Security)  
**Duration:** Brief (RBAC assignment changes only)  
**Result:** ✅ SUCCESS

## Summary

Removed subscription-scope Contributor role from 3 SPs on SC-OnlineLZ-00. Assigned custom RG-scoped role + RG Contributor to active SP. Unused SPs now have zero access.

**Active SP:** `github-actions-afd-apim-private-demo` (App ID: `ac563e84-f1dd-4582-bc7b-ce2b79089cb4`)

**Custom Role:** `Resource Group Contributor - GHA` (ID: `e22d8292-69a5-4844-b2bc-6016cf675120`)

**Deliverables:** Decision documented in `.squad/decisions/decisions.md`.
