# Test and demo the finished gateway

Back to the [README](../README.md).

This page is for after Steps 1 to 6. It shows how to check that everything works, how to fill the Konnect dashboards, and a short sequence you can walk someone through.

## 1. Check everything in one command

Export the values from your earlier steps, then run the script from the root of this repo:

```bash
export AWS_DOMAIN=<your domain>
export ISSUER_URL=<your Kong Identity issuer URL>
export CLIENT_ID=<your client ID>
export CLIENT_SECRET=<your client secret>
./scripts/verify.sh
```

You want `10 passed, 0 failed`:

| Check | What it proves |
|---|---|
| gateway answers (404 on `/`) | DNS, the load balancer, TLS and the AI Gateway data plane are up. Nothing is declared on `/`, so 404 is correct. |
| `/a2a` without a token, and with a bad token, is rejected by Kong | The auth strategy is active on the agent. Kong's own rejection has no `x-kong-upstream-latency` header, so the request never reached AWS. |
| `/a2a` with a valid token reaches the agent | Kong accepted the token, signed the call with its IAM role, and the agent on AgentCore answered. |
| `/mcp` without a token is rejected | The auth strategy is active on the MCP server. |
| `/mcp` initialize, list and call | The MCP server turns REST endpoints into tools and calls them. |
| `/v1` model without a token is rejected, and with one answers | The model is behind the same token, and Bedrock answers with token usage. |

Put the exports in a file **outside the repo** and `source` it (it holds a client secret). If your laptop can't resolve `ai-dp.<domain>` yet, the script falls back to the address public DNS returns. You can also set `KONG_IP` yourself.

## 2. Traffic for the dashboards

`verify.sh` sends only one request per check. To fill Konnect's analytics before a demo, run [`scripts/traffic.sh`](../scripts/traffic.sh) for a few minutes beforehand:

```bash
ROUNDS=30 ./scripts/traffic.sh
```

Each round sends accepted (valid token) and rejected (no token, bad token) calls to the agent, the MCP server and the model, and prints the status codes, for example `a2a: 200 401 401  mcp: 200 401  model: 200 401`. Each model call costs a fraction of a cent. Set `MODEL=` to leave the model out.

Give Konnect a few minutes. The AI Gateway's **Overview** then shows the model usage: total requests, average LLM latency and token usage. **Observability → Overview** adds the exact cost, error rate and top consumers, including MCP server calls. See the screenshots in [Step 6](../6-llm-gateway-bedrock.md#see-model-usage-in-konnect).

## 3. A five-minute walk-through

Have two things open: **AI Gateway → Gateways → Kong AWS AI Gateway** in Konnect, and the reference architecture diagram in the README.

**a. One front door (1 min).** Show the data plane node under **Data plane nodes**, then the **Agents**, **MCP Servers** and **Models** pages. Say: *one AI gateway in our AWS account, managed from Konnect. Our traffic never goes through Konnect.*

**b. Callers need a token (1 min).**
```bash
curl -si -X POST https://ai-dp.$AWS_DOMAIN/a2a --json '{}' | head -1
```
Expect `HTTP/1.1 401 Unauthorized`. Say: *anyone without a token is stopped at the gateway, before anything reaches AWS.*

**c. Get a token and call the agent (1 min).**
```bash
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" -d grant_type=client_credentials \
  -d client_id=$CLIENT_ID -d client_secret=$CLIENT_SECRET -d scope=scope1 | jq -r .access_token)
echo $TOKEN | jwt decode -
curl -s https://ai-dp.$AWS_DOMAIN/a2a -H "Authorization: Bearer $TOKEN" \
  --json '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"m1","role":"user","parts":[{"kind":"text","text":"hi"}]}}}' | jq
```
Point out `iss`, `aud`, `client_id`, `scope` and `exp` in the decoded token. Say: *short-lived, scoped tokens from Kong Identity. The agent runs on Bedrock AgentCore, and Kong signs the call with its own IAM role, so the caller never holds AWS credentials.* The token lasts 15 minutes, so fetch a fresh one if it has expired.

**d. Tools through MCP (1 min).** Initialize, list the tools, then call one, using the commands in [Step 5](../5-kong-identity-oauth2.md#test-the-mcp-server). Say: *an existing REST API became two agent tools, with no MCP server to write.*

**e. A model through the same gateway (1 min).**
```bash
curl -s https://ai-dp.$AWS_DOMAIN/v1/chat/completions -H "Authorization: Bearer $TOKEN" \
  --json '{"model":"nova-micro","messages":[{"role":"user","content":"In one sentence, what does an API gateway do?"}]}' \
  | jq '{model, reply: .choices[0].message.content, usage}'
```
Then switch to the gateway's **Overview** and show requests, latency and token usage. Say: *the same token and the same gateway for models, with usage per call. Swapping Bedrock for another provider doesn't change the client.*

**f. Optional: see the agent side.**
```bash
aws logs tail /aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT --since 5m --region us-west-2
```
Run it while you repeat step c, to show the request arriving at the runtime.

## 4. If something fails

| Symptom | Likely cause |
|---|---|
| `verify.sh` says it can't get a token | `CLIENT_ID`/`CLIENT_SECRET` wrong or not exported |
| A call returns 401 even with a fresh token | Token expired, or `ISSUER_URL` differs from the one the auth strategy uses |
| `/a2a` returns 403 from AWS | The data plane isn't signing with the Pod Identity role. See [Step 3](../3-a2a-agent-gateway-agentcore.md#common-problems). |
| `/mcp` or `/a2a` answers without a token | Step 5's `kongctl apply` didn't run, or an earlier step's file was re-applied after it |
| A tool call returns 502 | Kong can't reach the echo backend, or can't verify a backend's TLS certificate |
| The model call returns `AccessDenied` | No access to Nova Micro in `us-west-2` |

See also [troubleshooting](troubleshooting.md) and [known issues](known-issues.md).
