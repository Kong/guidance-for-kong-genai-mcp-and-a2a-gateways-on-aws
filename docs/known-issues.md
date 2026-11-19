# Known issues

These are open issues to resolve before this guide is used in production. Back to the [README](../README.md).

Each step was run in November 2026 with Kong Operator `2.4.0`, the `kong/kong-ai-gateway:2.3.1` data plane, kongctl `1.28.4`, AgentCore CLI `1.1.0`, `a2a-sdk` `1.3.1` and EKS `1.35`. The fixes from that run are in the step docs. What's left is below.

## Not yet run from scratch

1. **The guide hasn't been run start to finish on a fresh account.** The AI Gateway setup was built on top of an earlier, plugin-based setup in the same cluster, then written up as this linear path. In particular, these weren't run exactly as written:
   - installing Kong Operator `2.4.0` directly in Step 2 (it was upgraded from `2.1.5`);
   - applying Steps 3 to 6 one file at a time (the same entities were applied together, in fewer passes);
   - the teardown in [docs/teardown.md](teardown.md).

   Have someone follow the README in a clean account before relying on it.

## Security and privacy

2. **`/a2a` and `/mcp` are open between Steps 3 and 5.** Until Step 5 adds the auth strategy, anyone who knows the URL can call the agent and the tools, and Kong signs the agent calls with its own IAM role. In production, attach the auth strategy before exposing anything.
3. **The client secret is stored in the auth strategy's config** in Konnect. Use a Konnect vault reference for production.
4. **`logging.payloads: true`** on the agent logs full request and response bodies.
5. **The IAM policy is broad.** `bedrock-policy` uses `"Resource": "*"` for every action, including `secretsmanager:ListSecrets` / `GetSecretValue`. Scope it to the specific AgentCore runtime, Bedrock model, guardrail and secret ARNs. Also confirm `bedrock:CallWithBearerToken` is needed.
6. **TLS.** The data plane's NLB uses the AWS default TLS policy, and port 80 is open in plain HTTP. The operator also adds port 8443 (Kong's own TLS proxy, with a self-signed certificate). Consider a TLS 1.3 policy and removing ports 80 and 8443.
7. **Possible AWS account IDs in sample output.** Check sample outputs for 12-digit account numbers (for example inside runtime ARNs) and replace them with `<YOUR_AWS_ACCOUNT>`.

## Missing or incomplete content

8. **`client_1.py` isn't updated for the AI Gateway.** It uses the sample domain `kong-dp.kong-demo.com` over `http://`, and doesn't send a Kong Identity token, which `/a2a` needs after Step 5. Update it to read the domain and a token from the environment, then test it.
9. **Cost on the gateway's Overview rounds to the cent.** With small test volumes it shows `$0.00`. **Observability → Overview** shows the exact figure (for example `$0.0002835` for about 2,100 Nova Micro tokens).
10. **Architecture pieces with no deployment steps:** Bedrock Guardrails, MemoryDB (semantic cache, routing and guards), Secrets Manager (vault), and Kong metrics to CloudWatch.
11. **Two different agents.** `code/a2a/server_1.py` (deployed to AgentCore) adds header-logging and A2A-version-normalizing middleware that the inline code in Step 3 doesn't have. Its first line also prints the SDK version, which is debugging output.
12. **Kong doesn't trust `httpbin.konghq.com`'s certificate chain.** From a data plane that verifies upstream TLS, calls to it fail with `unable to get local issuer certificate`, while `curl` in the same cluster succeeds. Step 4 uses an in-cluster backend instead. The likely cause is Kong's CA bundle lacking the newer Let's Encrypt roots (`Root YE`, `ISRG Root X2`). Worth confirming with the Kong Gateway team, since real upstreams can use the same chain.

## Commands that may trip readers up

13. **The operator's AI data plane controller is off by default**, and the data plane's container must be named `aigw`. Both are handled in Step 2, but if either is missed, the failure is silent or the error message is unclear.
14. **Steps 5 and 6 re-declare entities.** Step 5's file re-declares the Step 3 agent and Step 4 MCP server to add their `access` block, and Step 6's re-declares the Step 5 auth strategy so the model can reference it. Re-running an earlier step's file after Step 5 (for example Step 3's) removes the `access` block again and reopens that route.
15. **kongctl wrappers.** Some company setups wrap kongctl and refuse `--pat`, taking the token from a pinned profile instead. If so, drop the flag and point the profile at the Konnect organization that holds `kong-aws-ai`.
16. The Python setup uses `--python 3.13`, while `agentcore.json` sets `"runtimeVersion": "PYTHON_3_14"`.

## Accuracy and housekeeping

17. **Typos:** "learn mode", "avaiable", "polcies", "existsing", "Speach", "the the".
18. `.DS_Store` files are tracked in `images/`. Remove them and add a `.gitignore`.
19. **Diagrams.** The flow diagrams in `images/` show plugins (A2A Proxy, MCP Proxy, Key Auth) from the plugin-based design, not the AI Gateway's Agent, MCP Server and Auth Strategy entities.
