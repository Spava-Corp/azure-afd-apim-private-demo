// ============================================================================
// WAF Policy — Azure Front Door Premium
// Author: Kima (SecOps Engineer)
// Date: 2026-05-07
//
// Mode: Prevention (blocks malicious requests immediately)
// Managed Rules: Microsoft DRS 2.1 (OWASP Top 10) + Bot Manager 1.1
// Custom Rules: Rate limiting (per-IP) + AFD ID header validation
//
// Tuning: Use ruleGroupOverrides to disable/exclude specific rules that
// cause false positives. Operators should baseline in Detection mode first
// if deploying to production with real traffic.
// ============================================================================

@description('Resource naming prefix')
param prefix string

@description('Environment name (dev, staging, prod)')
param environment string

@description('WAF mode: Prevention blocks, Detection only logs')
@allowed([
  'Prevention'
  'Detection'
])
param policyMode string = 'Prevention'

@description('Rate limit threshold — max requests per source IP in the time window')
param rateLimitThreshold int = 1000

@description('Rate limit duration in minutes')
param rateLimitDurationInMinutes int = 1

@description('Azure Front Door ID for header validation (defense-in-depth). Pass empty string on initial deploy; redeploy with actual ID after AFD is created.')
param afdProfileId string = ''

@description('Custom block response body (base64-encoded HTML)')
param customBlockResponseBody string = base64('<html><head><title>Blocked</title></head><body><h1>Request Blocked</h1><p>Your request has been blocked by our security policy. If you believe this is an error, contact support with your request ID.</p></body></html>')

@description('Custom block response status code')
param customBlockResponseStatusCode int = 403

@description('Tags to apply to resources')
param tags object = {}

var wafPolicyName = '${prefix}waf${environment}' // WAF policy names must be alphanumeric

// ============================================================================
// WAF Policy Resource
// ============================================================================

@description('AFD Premium WAF Policy — Prevention mode with DRS 2.1 + Bot Manager + custom rules')
resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: wafPolicyName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: policyMode
      // Custom block page — generic message, no info leakage
      customBlockResponseStatusCode: customBlockResponseStatusCode
      customBlockResponseBody: customBlockResponseBody
      requestBodyCheck: 'Enabled'
      // Log all requests for observability, even in Prevention mode
      javascriptChallengeExpirationInMinutes: 30
    }

    // ==========================
    // MANAGED RULE SETS
    // ==========================
    managedRules: {
      managedRuleSets: [
        {
          // Microsoft Default Rule Set 2.1 — covers OWASP Top 10:
          // SQL injection, XSS, LFI/RFI, command injection, protocol attacks,
          // scanner detection, session fixation, Java attacks, etc.
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
          // To exclude specific rules that cause false positives, add:
          // ruleGroupOverrides: [
          //   {
          //     ruleGroupName: 'SQLI'
          //     rules: [
          //       {
          //         ruleId: '942100'
          //         enabledState: 'Disabled'
          //         action: 'Log'
          //       }
          //     ]
          //   }
          // ]
          ruleGroupOverrides: []
        }
        {
          // Bot Manager 1.1 — blocks known bad bots, challenges unknown bots,
          // allows known good bots (Googlebot, Bingbot, etc.)
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
          ruleSetAction: 'Block'
          ruleGroupOverrides: []
        }
      ]
    }

    // ==========================
    // CUSTOM RULES
    // ==========================
    customRules: {
      rules: concat([
        {
          // RATE LIMITING: Prevents brute force, credential stuffing, and API abuse.
          // 1000 req/min per source IP is generous for legitimate use but blocks automated attacks.
          name: 'RateLimitPerSourceIP'
          priority: 100
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitDurationInMinutes: rateLimitDurationInMinutes
          rateLimitThreshold: rateLimitThreshold
          action: 'Block'
          matchConditions: [
            {
              // Match all requests (rate limit applies globally)
              matchVariable: 'RemoteAddr'
              operator: 'IPMatch'
              negateCondition: false
              matchValue: [
                '0.0.0.0/0'
              ]
            }
          ]
        }
      ], empty(afdProfileId) ? [] : [
        {
          // AFD ID HEADER VALIDATION: Defense-in-depth to prevent origin bypass.
          // Only active when afdProfileId is provided (requires redeploy after AFD creation).
          name: 'BlockMissingAzureFDID'
          priority: 200
          enabledState: 'Enabled'
          ruleType: 'MatchRule'
          action: 'Block'
          matchConditions: [
            {
              matchVariable: 'RequestHeader'
              selector: 'X-Azure-FDID'
              operator: 'Equal'
              negateCondition: true
              matchValue: [
                afdProfileId
              ]
              transforms: [
                'Lowercase'
              ]
            }
          ]
        }
      ])
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the WAF policy — reference this from AFD security policy')
output wafPolicyId string = wafPolicy.id

@description('Name of the WAF policy')
output wafPolicyName string = wafPolicy.name
