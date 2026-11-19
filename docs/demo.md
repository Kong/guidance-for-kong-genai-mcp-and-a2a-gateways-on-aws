# Test and demo the finished gateway

Back to the [README](../README.md).

This page is for after Steps 1 to 5. It shows how to check that everything works, and a short sequence you can walk someone through.

> The `/a2a` checks rely on the design in [Step 3](../3-a2a-agent-gateway-agentcore.md#how-kong-reaches-agentcore): AgentCore accepts Kong Identity tokens, and Kong checks them first (Step 5).

## 1. Check everything in one command

Export the values from your earlier steps, then run the script:

```bash
export AWS_DOMAIN=<your domain>
export ISSUER_URL=<your Kong Identity issuer URL>
export CLIENT_ID=<your client ID>
export CLIENT_SECRET=<your client secret>
./scripts/verify.sh
```

Every line should say `PASS`:

| Check | What it proves |
|---|---|
| gateway answers (404 on `/`) | DNS, the load balancer, TLS and Kong are up. There is no route on `/`, so 404 is correct. |
| `/a2a` without a token is rejected by Kong | The OpenID Connect plugin is active. Kong's own rejection has no `x-kong-upstream-latency` header, so the request never reached AWS. |
| `/a2a` with a bad token is rejected by Kong | The same check for an invalid token. |
| `/a2a` with a valid token reaches the agent | Kong accepted the token, passed it on, and the agent on AgentCore answered. |
| `/mcp` initialize, list and call | The MCP gateway turns REST endpoints into tools and calls them. |

Put the exports in a file **outside the repo** and `source` it (it holds a client secret). If your laptop can't resolve `kong-dp.<domain>` yet, the script falls back to the address public DNS returns. You can also set `KONG_IP` yourself.

## 2. A five-minute walk-through

Have two things open: the `kong-aws` control plane in Konnect (Routes, Plugins, Data Plane Nodes) and the reference architecture diagram in the README.

**a. One front door (1 min).** Show the data plane node connected in Konnect, then the two routes, `/a2a` and `/mcp`. Say: *one gateway in our AWS account, managed from Konnect. Our traffic never goes through Konnect.*

**b. Agents need a token (1 min).**
```bash
curl -si https://kong-dp.$AWS_DOMAIN/a2a -X POST --json '{}' | head -3
```
Expect a `401` with a `WWW-Authenticate: Bearer` header. Say: *anyone without a token is stopped at the gateway.*

**c. Get a token and call the agent (2 min).**
```bash
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" -d grant_type=client_credentials \
  -d client_id=$CLIENT_ID -d client_secret=$CLIENT_SECRET -d scope=scope1 | jq -r .access_token)
echo $TOKEN | jwt decode -        # show iss, aud, client_id, scope, exp
curl -s https://kong-dp.$AWS_DOMAIN/a2a -H "Authorization: Bearer $TOKEN" \
  --json '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"m1","role":"user","parts":[{"kind":"text","text":"hi"}]}}}' | jq
```
Say: *short-lived, scoped tokens from Kong Identity. The agent runs on Bedrock AgentCore, and this is the only way in.* The token lasts 15 minutes in this guide, so fetch a fresh one if it has expired.

**d. Tools through MCP (1 min).** Initialize, list the tools, then call one, using the commands in [Step 4](../4-mcp-gateway.md). Use `query_sku`, not `sku`, as the argument name. Say: *an existing REST API became two agent tools with no MCP server to write.*

**e. Optional: see the agent side.**
```bash
aws logs tail /aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT --since 5m --region us-west-2
```
Run it while you repeat step c, to show the request arriving at the runtime.

## 3. If something fails

| Symptom | Likely cause |
|---|---|
| `verify.sh` says it can't get a token | `CLIENT_ID`/`CLIENT_SECRET` wrong or not exported |
| `/a2a` returns 401 even with a fresh token | Token expired, or `ISSUER_URL` differs from the one the plugin uses |
| `/a2a` returns an error about expiry | Token lifetime under about 2 minutes. AgentCore rejects tokens about to expire. |
| New routes return `no Route matched` | The data plane rejected the last config. Check `kubectl logs -n kong <dataplane pod>` for `[error]` lines. |
| A tool call returns 502 | Kong cannot verify the backend's TLS certificate, or cannot reach it |

See also [troubleshooting](troubleshooting.md) and [known issues](known-issues.md).
