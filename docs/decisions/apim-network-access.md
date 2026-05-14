# APIM Network Access Decision

- **Status:** Fallback Activated
- **Date:** 2026-05-14T08:10:57.271-05:00
- **Updated:** 2026-05-14
- **Owner:** EECOM (Infrastructure Developer)
- **Scope:** `infra/modules/apim/apim.bicep`, `infra/modules/apim/apim-fdid-policy.bicep`

## Preferred Decision (Not Viable)

Deploy APIM with:

- `virtualNetworkType: 'None'`
- `publicNetworkAccess: 'Disabled'`

This was intended to keep APIM reachable only through the approved Azure Front Door shared Private Link / Private Endpoint path and remove direct public ingress to the gateway.

### Why It Failed

After deploying with `publicNetworkAccess: 'Disabled'`, Azure Front Door origin health probes returned **0%** for over two hours. The AFD `deploymentStatus` remained stuck at `NotStarted` across all edge resources (origin, origin group, route, endpoint). The PE connection was approved, but AFD's shared Private Link data-plane handshake could not complete while APIM's public listener was disabled.

This matched the documented risk: *"Azure shared Private Link may require public access during PE provisioning handshake in some regions/SKUs."* Testing confirmed that the Developer SKU in West US 2 exhibits this limitation.

## Active Decision (Fallback)

Deploy APIM with:

- `virtualNetworkType: 'None'`
- `publicNetworkAccess: 'Enabled'`
- APIM global inbound policy (`check-header`) that validates the `X-Azure-FDID` header against the AFD profile ID
- WAF custom rule that also validates `X-Azure-FDID` (defense-in-depth, two-phase deploy)

### How It Works

1. **APIM policy layer:** A global `<check-header>` policy on APIM rejects any request whose `X-Azure-FDID` header does not match the expected Front Door profile ID. This runs before any API logic.
2. **WAF layer:** The WAF policy includes a custom rule that blocks requests missing the correct `X-Azure-FDID` header (activated on redeploy with the AFD profile ID).
3. **Private Link:** The AFD origin still uses a shared Private Link to APIM. Traffic flows over the Azure backbone even though the public listener is enabled.

### Trade-offs

| Aspect | Preferred (disabled) | Fallback (FDID validation) |
|--------|---------------------|---------------------------|
| Public listener | None | Present, but policy-gated |
| Bypass risk | Eliminated | Low — requires knowing the FDID GUID |
| AFD compatibility | Broken on Developer SKU | Works |
| Defense layers | AFD + WAF + PE + no listener | AFD + WAF + PE + FDID policy |

## Why This Is Preferred

1. **Maximum lockdown:** disabling public network access removes the APIM internet-facing attack surface instead of trying to protect it.
2. **Defense in depth:** Azure Front Door, WAF, Private Link, and the APIM private endpoint all stay in the request path.
3. **Lower bypass risk:** a header-based control helps only when AFD stays correctly configured, while `publicNetworkAccess: 'Disabled'` eliminates the listener entirely.

## When To Fall Back

Use the fallback only if one or more of these conditions occurs:

- ✅ deployment errors indicate the private endpoint approval or shared Private Link data-plane handshake still requires public reachability
- ✅ Azure Front Door health probes fail after `publicNetworkAccess` is disabled
- the region or APIM SKU shows the known Azure limitation for this connectivity pattern

## Consequences

- **Preferred mode:** strongest zero-trust posture and simplest network boundary to explain and audit.
- **Fallback mode:** preserves Azure Front Door origin validation, but reintroduces a public listener that must be protected by policy and configuration hygiene.
