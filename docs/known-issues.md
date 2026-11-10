# Known issues

These are open issues to resolve before this guide is used in production. Back to the [README](../README.md).

## Security and privacy

1. **Possible AWS account ID in the docs.** The sample `agentcore status` output in [Step 3](../3-a2a-agent-gateway-agentcore.md#check-the-status) contains a 12-digit account number inside the URL-encoded runtime ARN, while the line above it uses `<YOUR_AWS_ACCOUNT>`. Redact it.
2. **`/a2a` is open between Step 3 and Step 5.** Until Step 5 adds the OpenID Connect plugin, anyone who knows the URL can invoke the agent, and Kong pays for it with its own IAM role. In production, apply the Step 5 protection before exposing the route. The A2A section also describes a Key Auth plugin that the config doesn't include.
3. **The `/mcp` route has no authentication.** Step 4's MCP server is public. Protect it (for example with Kong's MCP OAuth2 plugin) before pointing it at real APIs.
4. **Step 4's tools call a public echo service.** `httpbin.konghq.com` returns whatever it receives. Don't send real data through the sample tools.
5. **`log_payloads: true`** on the A2A route logs full request and response bodies.
6. **The IAM policy is broad.** `bedrock-policy` uses `"Resource": "*"` for every action, including `secretsmanager:ListSecrets` / `GetSecretValue`. Scope it to specific model, guardrail, runtime and secret ARNs. Also confirm `bedrock:CallWithBearerToken` is needed.
7. **TLS policy.** The NLB uses `ELBSecurityPolicy-TLS-1-2-2017-01`. Consider a current TLS 1.3 policy. Port 80 is also open in plain HTTP.

## Missing or incomplete content

8. **Steps 4 and 5 haven't been run end to end yet.** The `ai-mcp-proxy` configuration, the MCP `curl` calls (including session handling) and the OpenID Connect plugin on `a2a-route` follow Kong's documentation but need one test run against this guide's EKS and Konnect setup.
9. **Architecture pieces with no deployment steps:** LLM Gateway → Bedrock (AI Proxy), Bedrock Guardrails (AI AWS Guardrails plugin), MemoryDB (semantic cache, routing and guards), Secrets Manager (vault), and Kong metrics to CloudWatch.
10. **Two different agents.** `code/a2a/server_1.py` (deployed to AgentCore) adds header-logging and A2A-version-normalizing middleware that the inline code in Step 3 doesn't have.
11. **Hard-coded sample domain.** The Step 3 test `curl` and `client_1.py` use `kong-dp.kong-demo.com` instead of `kong-dp.$AWS_DOMAIN`. `client_1.py` also uses `http://`.
12. **`ai-a2a-proxy` config fields to confirm.** The config uses `auth.provider: "aws_iam"` and `auth.aws_iam.aws_region`. Kong's public plugin reference (checked November 2026) lists only `logging.*` and `max_request_body_size` for this plugin. Confirm against the target Kong version.
13. **Step 3 still starts with `deck gateway reset -f`.** Steps 4 and 5 add to the configuration with `deck gateway apply`, but re-running Step 3 deletes their routes and plugins until you re-apply them.

## Commands that may trip readers up

14. `helm install aws-load-balancer-controller eks/...` assumes an `eks` Helm repo, but no `helm repo add eks ...` command is given.
15. The namespace block starts with `kubectl delete namespace kong`, which errors on a fresh cluster.
16. The "Delete CP/DP" block deletes a `konnect-pat` secret that no step creates.
17. There are no clean-up commands for the EKS cluster, IAM policies and roles, ACM certificate, Route 53 records, hosted zone and domain, Load Balancer Controller, Kong Operator, or the Kong Identity auth server.
18. `agentcore remove all -y` is followed by `agentcore deploy`. Confirm this is the intended teardown.
19. The Python setup uses `--python 3.13`, while `agentcore.json` sets `"runtimeVersion": "PYTHON_3_14"`.

## Accuracy and housekeeping

20. **Version drift:** the DataPlane uses `kong/kong-gateway:3.14.0.3`, but the sample response shows `Server: kong/3.14.0.0-enterprise-edition`.
21. **Typos:** "learn mode", "avaiable", "polcies", "existsing", "Speach", "pyptoject.toml", "agentocore.json", "ano no memory", "`$AWS-DOMAIN`" (should be `$AWS_DOMAIN`), "boths", "the the", "At the sames".
22. The scratch notes in the Step 3 appendix should be removed or turned into real content.
23. `.DS_Store` files are tracked in `images/`. Remove them and add a `.gitignore`.
