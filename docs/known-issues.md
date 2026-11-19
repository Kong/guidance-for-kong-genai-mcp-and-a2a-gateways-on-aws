# Known issues

These are open issues to resolve before this guide is used in production. Back to the [README](../README.md).

Steps 1 to 5 were run end to end in November 2026 with Kong Gateway `3.14.0.3`, Kong Operator `2.1.5`, AgentCore CLI `1.1.0`, `a2a-sdk` `1.3.1`, decK `1.70` and EKS `1.35`. The fixes from that run are in the step docs. What's left is below.

## Design

1. **Kong can't sign requests to AgentCore with IAM.** The `ai-a2a-proxy` plugin in Kong 3.14 has only `max_request_body_size` and `logging.*` settings, with no upstream authentication. Step 3 therefore gives the AgentCore runtime JWT inbound auth that trusts Kong Identity, and Kong passes the caller's token through. If a later Kong version adds upstream AWS IAM auth to this plugin, Step 3 could go back to a single SigV4 runtime, with Kong signing through its Pod Identity role.
2. **Step 3 deploys two runtimes.** The `agent` runtime (SigV4) exists only for the direct `awscurl` test. It isn't used afterwards, but it stays deployed until you remove it.
3. **AgentCore checks only the token's `client_id`.** The runtime's authorizer sets `allowedClients`. Consider adding `allowedAudience` (`http://kong.dev`) or `allowedScopes` too.

## Security and privacy

4. **Possible AWS account ID in the docs.** Check sample outputs for 12-digit account numbers (for example inside URL-encoded runtime ARNs) and replace them with `<YOUR_AWS_ACCOUNT>`.
5. **Kong checks tokens only from Step 5 on.** Between Steps 3 and 5, Kong forwards every `/a2a` call to AgentCore, which rejects calls without a valid token. In production, apply the Step 5 plugin before exposing the route. The A2A section also describes a Key Auth plugin that the config doesn't include.
6. **The `/mcp` route has no authentication.** Step 4's MCP server is public. Protect it (for example with Kong's MCP OAuth2 plugin) before pointing it at real APIs.
7. **The client secret is stored in the OpenID Connect plugin's config** in Konnect. Use a Konnect vault reference for production.
8. **`log_payloads: true`** on the A2A route logs full request and response bodies.
9. **The IAM policy is broad, and no step uses it yet.** `bedrock-policy` uses `"Resource": "*"` for every action, including `secretsmanager:ListSecrets` / `GetSecretValue`. Scope it to specific model, guardrail, runtime and secret ARNs. Also confirm `bedrock:CallWithBearerToken` is needed.
10. **TLS policy.** The NLB uses `ELBSecurityPolicy-TLS-1-2-2017-01`. Consider a current TLS 1.3 policy. Port 80 is also open in plain HTTP.

## Missing or incomplete content

11. **`client_1.py` doesn't send a token.** Since `/a2a` needs a Kong Identity token, the second agent in Step 3 is rejected as written. It also uses the sample domain `kong-dp.kong-demo.com` over `http://`. Update it to read the domain and a token from the environment, then test it.
12. **Architecture pieces with no deployment steps:** LLM Gateway → Bedrock (AI Proxy), Bedrock Guardrails (AI AWS Guardrails plugin), MemoryDB (semantic cache, routing and guards), Secrets Manager (vault), and Kong metrics to CloudWatch.
13. **Two different agents.** `code/a2a/server_1.py` (deployed to AgentCore) adds header-logging and A2A-version-normalizing middleware that the inline code in Step 3 doesn't have. Its first line also prints the SDK version, which is debugging output.
14. **Step 3 still starts with `deck gateway reset -f`.** Steps 4 and 5 add to the configuration with `deck gateway apply`, but re-running Step 3 deletes their routes and plugins until you re-apply them.
15. **Kong doesn't trust `httpbin.konghq.com`'s certificate chain.** From a data plane that verifies upstream TLS, calls to it fail with `unable to get local issuer certificate`, while `curl` in the same cluster succeeds. Step 4 uses an in-cluster backend instead. The likely cause is Kong's CA bundle lacking the newer Let's Encrypt roots (`Root YE`, `ISRG Root X2`). Worth confirming with the Kong Gateway team, since real upstreams can use the same chain.

## Commands that may trip readers up

16. There are no clean-up commands for the EKS cluster, IAM policies and roles, ACM certificate, Route 53 records, hosted zone and domain, Load Balancer Controller, Kong Operator, or the Kong Identity auth server. The README lists what to remove.
17. `agentcore remove all -y` is followed by `agentcore deploy`. Confirm this is the intended teardown, now that the project has two runtimes.
18. The Python setup uses `--python 3.13`, while `agentcore.json` sets `"runtimeVersion": "PYTHON_3_14"`.
19. **decK wrappers.** Some company setups wrap `deck` and refuse `--konnect-token`, taking the token from a pinned profile instead. If so, drop the flag and point the profile at the Konnect organization that holds `kong-aws`.

## Accuracy and housekeeping

20. **Version drift:** the DataPlane uses `kong/kong-gateway:3.14.0.3`, but the sample response in Step 2 shows `Server: kong/3.14.0.0-enterprise-edition`.
21. **Typos:** "learn mode", "avaiable", "polcies", "existsing", "Speach", "the the", "At the sames".
22. The scratch notes in the Step 3 appendix should be removed or turned into real content.
23. `.DS_Store` files are tracked in `images/`. Remove them and add a `.gitignore`.
