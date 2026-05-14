# APIM Network Access Decision

- **Status:** Accepted
- **Date:** 2026-05-14T08:10:57.271-05:00
- **Owner:** EECOM (Infrastructure Developer)
- **Scope:** `infra/modules/apim/apim.bicep`

## Preferred Decision

Deploy APIM with:

- `virtualNetworkType: 'None'`
- `publicNetworkAccess: 'Disabled'`

This keeps APIM reachable only through the approved Azure Front Door shared Private Link / Private Endpoint path and removes direct public ingress to the gateway.

## Why This Is Preferred

1. **Maximum lockdown:** disabling public network access removes the APIM internet-facing attack surface instead of trying to protect it.
2. **Defense in depth:** Azure Front Door, WAF, Private Link, and the APIM private endpoint all stay in the request path.
3. **Lower bypass risk:** a header-based control helps only when AFD stays correctly configured, while `publicNetworkAccess: 'Disabled'` eliminates the listener entirely.

## Fallback Decision

If Azure Front Door shared Private Link connectivity breaks when APIM public access is disabled, fall back to:

- `virtualNetworkType: 'None'`
- `publicNetworkAccess: 'Enabled'`
- APIM inbound policy that validates the `X-Azure-FDID` header against the expected AFD profile ID

If fallback mode is required, keep the WAF-side `X-Azure-FDID` checks aligned with the APIM inbound policy.

## When To Fall Back

Use the fallback only if one or more of these conditions occurs:

- deployment errors indicate the private endpoint approval or shared Private Link data-plane handshake still requires public reachability
- Azure Front Door health probes fail after `publicNetworkAccess` is disabled
- the region or APIM SKU shows the known Azure limitation for this connectivity pattern

## Consequences

- **Preferred mode:** strongest zero-trust posture and simplest network boundary to explain and audit.
- **Fallback mode:** preserves Azure Front Door origin validation, but reintroduces a public listener that must be protected by policy and configuration hygiene.
