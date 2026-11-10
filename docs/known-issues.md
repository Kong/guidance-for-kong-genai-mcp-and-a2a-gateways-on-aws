# Known issues

These are open issues to resolve before this guide is used in production. Back to the [README](../README.md).

## Security and privacy

1. **Possible AWS account ID in the docs.** The sample `agentcore status` output in [Step 3](../3-a2a-agent-gateway-agentcore.md#check-the-status) contains a 12-digit account number inside the URL-encoded runtime ARN, while the line above it uses `<YOUR_AWS_ACCOUNT>`. Redact it.
2. **The A2A route has no authentication.** `ai-a2a-proxy.yaml` publishes `/a2a` publicly, and Kong calls AgentCore with its own IAM role, so anyone who knows the URL can invoke the agent. The A2A section describes a Key Auth plugin that the config doesn't include.
3. **`log_payloads: true`** on the A2A route logs full request and response bodies.
4. **The IAM policy is broad.** `bedrock-policy` uses `"Resource": "*"` for every action, including `secretsmanager:ListSecrets` / `GetSecretValue`. Scope it to specific model, guardrail, runtime and secret ARNs. Also confirm `bedrock:CallWithBearerToken` is needed.
5. **TLS policy.** The NLB uses `ELBSecurityPolicy-TLS-1-2-2017-01`. Consider a current TLS 1.3 policy. Port 80 is also open in plain HTTP.

## Missing or incomplete content

6. **Files referenced but not in the repo:** `kong_aws_mock.yaml`, `openapi.yml`, `kong_docusign_openid_mock.yaml`, `images/step4-mcp/02-development-time.png`, `images/step5-identity/01-architecture2.png`. Steps 4 and 5 can't be fully completed without them.
7. **Step 5 describes a DocuSign scenario.** Its main section is titled "Docusign Extension App - Production Time" and refers to a DocuSign extension app and Data IO services. Step 4's mocked `/api/dataio/...` endpoints come from the same scenario. Rewrite both for this guide, for example by protecting the `/a2a` route with OpenID Connect introspection against Kong Identity.
8. **Architecture pieces with no deployment steps:** LLM Gateway → Bedrock (AI Proxy), Bedrock Guardrails (AI AWS Guardrails plugin), MemoryDB (semantic cache, routing and guards), Secrets Manager (vault), and Kong metrics to CloudWatch. There is also no `ai-mcp-proxy` configuration in Step 4.
9. **Two different agents.** `code/a2a/server_1.py` (deployed to AgentCore) adds header-logging and A2A-version-normalizing middleware that the inline code in Step 3 doesn't have.
10. **Hard-coded sample domain.** The Step 3 test `curl` and `client_1.py` use `kong-dp.kong-demo.com` instead of `kong-dp.$AWS_DOMAIN`. `client_1.py` also uses `http://`.
11. **`ai-a2a-proxy` config fields to confirm.** The config uses `auth.provider: "aws_iam"` and `auth.aws_iam.aws_region`. Kong's public plugin reference (checked November 2026) lists only `logging.*` and `max_request_body_size` for this plugin. Confirm against the target Kong version.
12. **`deck gateway reset -f` in Steps 3, 4 and 5** deletes the previous step's configuration. If the steps are meant to build on each other, use cumulative decK files or `select_tags`.
13. **Screenshots still to capture.** See the checklist in [images/README.md](../images/README.md#screenshots-still-to-capture).

## Commands that may trip readers up

14. `helm install aws-load-balancer-controller eks/...` assumes an `eks` Helm repo, but no `helm repo add eks ...` command is given.
15. The namespace block starts with `kubectl delete namespace kong`, which errors on a fresh cluster.
16. The "Delete CP/DP" block deletes a `konnect-pat` secret that no step creates.
17. There are no clean-up commands for the EKS cluster, IAM policies and roles, ACM certificate, Route 53 records, hosted zone and domain, Load Balancer Controller, Kong Operator, or the Kong Identity auth server.
18. `agentcore remove all -y` is followed by `agentcore deploy`. Confirm this is the intended teardown.
19. The Python setup uses `--python 3.13`, while `agentcore.json` sets `"runtimeVersion": "PYTHON_3_14"`.

## Accuracy and housekeeping

20. **Version drift:** the DataPlane uses `kong/kong-gateway:3.14.0.3`, the sample response shows `Server: kong/3.14.0.0-enterprise-edition`, and the data plane screenshot shows `3.13.0.1`.
21. In Step 2, "You can check your Data Plane in Konnect UI" sits above the control plane screenshot.
22. **Typos:** "learn mode", "avaiable", "polcies", "existsing", "Speach", "pyptoject.toml", "agentocore.json", "ano no memory", "`$AWS-DOMAIN`" (should be `$AWS_DOMAIN`), "boths", "submiting", "the the", "Checking you Kong Identity", "At the sames", "the defined it as 30 seconds" (the client is configured for 60).
23. The scratch notes in the Step 3 appendix should be removed or turned into real content.
24. `.DS_Store` files are tracked in `images/`. Remove them and add a `.gitignore`.
