# Step 7: Connect the agent to the model and tools

[← Step 6](6-llm-gateway-bedrock.md) · **Step 7** · [Step 8 →](8-rate-limit.md)

## Why this step

Steps 3, 4 and 6 each put one kind of AI traffic behind Kong: an agent at `/a2a`, MCP tools at `/mcp` and a model at `/v1`. On their own they're three separate front doors. The Step 3 agent is a stub that returns `that's the response`, and it never calls the model or the tools.

Real agents do all three in one request. A user asks the agent a question, the agent asks a model what to do, the model asks for a tool, the agent calls the tool, and the model writes the answer. This step replaces the stub with an agent that works that way, and sends **every hop through Kong**. Each hop gets the same Kong Identity token check, shows up in the same Konnect analytics, and can be limited by the same policies.

## What it does, in plain English

1. **Runs a small inventory API in the cluster** that returns real-looking stock and order data, so you can tell when the agent actually used a tool.
2. **Points the Step 4 MCP tools at it**, in place of the echo backend.
3. **Replaces the stub agent on AgentCore** with a [Strands](https://strandsagents.com/) agent that calls the `nova-micro` model at `/v1` and the inventory tools at `/mcp`, both through Kong, with its own Kong Identity token.
4. **Asks the agent a question through `/a2a`** and follows the request through all three routes.

The request path:

```
you ──/a2a──► Kong ──► AgentCore: inventory agent
                         ├──/v1──► Kong ──► Amazon Nova Micro      (what should I do?)
                         ├──/mcp─► Kong ──► inventory API           (check_inventory, list_orders)
                         └──/v1──► Kong ──► Amazon Nova Micro      (write the answer)
```

## Before you start

- Steps 1 to 6 are complete, in this terminal, from the root of this repo.
- These are still exported: `AWS_DOMAIN` (Step 1), `PAT` (Step 2), `AGENTCORE_URL` and `AGENTCORE_IDENTIFIER` (Step 3), and `ISSUER_URL`, `INTROSPECTION_URL`, `CLIENT_ID`, `CLIENT_SECRET` and `CACHE_TOKENS_SALT` (Step 5). Check that they're set:

  ```bash
  for v in AWS_DOMAIN PAT AGENTCORE_URL AGENTCORE_IDENTIFIER ISSUER_URL INTROSPECTION_URL CLIENT_ID CLIENT_SECRET CACHE_TOKENS_SALT; do printenv $v > /dev/null && echo "ok      $v" || echo "MISSING $v"; done
  ```

  If any say `MISSING`, re-run the `export` commands from the step that created them. `CACHE_TOKENS_SALT` must be the same value you used in Steps 5 and 6.
- The `agentcorekong` project folder from Step 3 is in the root of this repo.

> **Not yet tested end to end.** The agent code follows the AgentCore CLI's own `a2a-python-strands` template (Strands `1.57`, `bedrock-agentcore` `1.24`). Run each checkpoint before moving on.

---

## Run the inventory API in the cluster

[`code/inventory/inventory-api.yaml`](code/inventory/inventory-api.yaml) runs a tiny Python web server in the `kong` namespace. It has two endpoints, `/inventory?sku=...` and `/orders?status=...`, with three products and four orders. It isn't exposed outside the cluster.

```bash
kubectl apply -f code/inventory/inventory-api.yaml
kubectl -n kong rollout status deployment/inventory-api --timeout=120s
```

You want `successfully rolled out`.

## Point the MCP tools at it

[`code/ai-gateway/step7-tools.yaml`](code/ai-gateway/step7-tools.yaml) re-declares the Step 5 MCP server with one change: `config.url` is now `http://inventory-api.kong.svc.cluster.local:8080` instead of the echo API. The tools, the `/mcp` route and the token requirement stay the same.

```bash
kongctl diff --mode apply -f code/ai-gateway/step7-tools.yaml --pat "$PAT"
```

```bash
kongctl apply -f code/ai-gateway/step7-tools.yaml --auto-approve --pat "$PAT"
```

The preview shows one change on `inventory-tools`: the URL.

> **kongctl refuses `--pat`?** If a wrapper such as konnect-guard blocks token flags, leave `--pat "$PAT"` off. See [troubleshooting](docs/troubleshooting.md#kongctl-reaches-the-wrong-konnect-organization-or-refuses---pat).

Wait about 10 seconds, then call a tool the way the agent will. Get a token and start an MCP session:

```bash
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" -d grant_type=client_credentials \
  -d client_id=$CLIENT_ID -d client_secret=$CLIENT_SECRET -d scope=scope1 | jq -r .access_token)
curl -s -D mcp-headers.txt -o /dev/null -X POST https://ai-dp.$AWS_DOMAIN/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}'
export MCP_SESSION_ID=$(grep -i '^mcp-session-id:' mcp-headers.txt | awk '{print $2}' | tr -d '\r')
echo "Session: $MCP_SESSION_ID"
```

Then check a SKU:

```bash
curl -s -X POST https://ai-dp.$AWS_DOMAIN/mcp \
  -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $MCP_SESSION_ID" \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  --data '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"check_inventory","arguments":{"query_sku":"KONG-456"}}}'
```

> **Checkpoint: the tools return real data.** The result's `content` includes `"in_stock": 0` and `"restock_date": "2026-12-15"` for the Kong sticker pack, not an echo of the request.

## Replace the stub agent

Move into the Step 3 project, copy in the new agent and its dependencies, and refresh the lockfile. The Step 3 lockfile pins the newer A2A SDK that the stub needed, and this agent uses the version the Strands template expects.

```bash
cd agentcorekong
cp ../code/a2a/inventory_agent.py app/agent/
cp ../code/a2a/inventory-agent-pyproject.toml app/agent/pyproject.toml
(cd app/agent && uv lock)
```

Point the runtime at the new file, and give it the Kong URL and its Kong Identity client credentials as environment variables:

```bash
jq --arg kong "https://ai-dp.$AWS_DOMAIN" --arg iss "$ISSUER_URL" --arg id "$CLIENT_ID" --arg secret "$CLIENT_SECRET" \
  '.runtimes[0].entrypoint = "inventory_agent.py"
   | .runtimes[0].envVars = [
       {"name": "KONG_URL", "value": $kong},
       {"name": "ISSUER_URL", "value": $iss},
       {"name": "CLIENT_ID", "value": $id},
       {"name": "CLIENT_SECRET", "value": $secret}]' \
  agentcore/agentcore.json > /tmp/ac.json && mv /tmp/ac.json agentcore/agentcore.json
jq '.runtimes[0] | {entrypoint, envVars: [.envVars[].name]}' agentcore/agentcore.json
```

You should see:

```
{
  "entrypoint": "inventory_agent.py",
  "envVars": [
    "KONG_URL",
    "ISSUER_URL",
    "CLIENT_ID",
    "CLIENT_SECRET"
  ]
}
```

> **About the client secret.** For this guide the agent reuses the Step 5 client, and the secret is stored as a runtime environment variable. `agentcorekong/` is git-ignored, so it isn't committed. In production, give each agent its own Kong Identity client and keep the secret in AWS Secrets Manager or AgentCore Identity.

### What the agent does

[`code/a2a/inventory_agent.py`](code/a2a/inventory_agent.py) is about 60 lines:

- `get_token()` gets a Kong Identity token with the client credentials grant, the same call you've run by hand since Step 5, and reuses it until it nearly expires.
- The **model** is Strands' `OpenAIModel` pointed at `https://ai-dp.<your domain>/v1` with `model_id="nova-micro"`. The OpenAI client sends the token as `Authorization: Bearer`, which is what Kong checks.
- The **tools** come from Strands' `MCPClient`, connected to `https://ai-dp.<your domain>/mcp` with the same token. The agent discovers `check_inventory` and `list_orders` from Kong at runtime. Nothing about them is hard-coded in the agent.
- `serve_a2a` publishes it as an A2A agent on AgentCore, like the Step 3 template.

The agent never talks to Bedrock or the inventory API directly. It only knows Kong's URL.

## Deploy the new agent

The runtime keeps its name, `agent`, so it keeps its ARN. `AGENTCORE_URL` and the Step 3 Agent on Kong don't change.

```bash
agentcore deploy --region us-west-2
```

It takes a few minutes and ends with `Deploy to AWS Complete`. If it can't find credentials from an `aws login` session, see the note under [Deploy the Agent](3-a2a-agent-gateway-agentcore.md#deploy-the-agent) in Step 3.

Check that the runtime is ready again. It should print `READY`:

```bash
aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id $AGENTCORE_IDENTIFIER --region us-west-2 --query status --output text
```

Then go back to the root of the repo:

```bash
cd ..
```

## Ask the agent through Kong

Get a token and ask a question that needs both tools:

```bash
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" -d grant_type=client_credentials \
  -d client_id=$CLIENT_ID -d client_secret=$CLIENT_SECRET -d scope=scope1 | jq -r .access_token)
curl -s -X POST https://ai-dp.$AWS_DOMAIN/a2a -H "Authorization: Bearer $TOKEN" \
  --json '{
    "jsonrpc": "2.0",
    "id": "1",
    "method": "message/send",
    "params": {
      "message": {
        "kind": "message",
        "messageId": "msg-001",
        "role": "user",
        "parts": [{"kind": "text", "text": "Is KONG-456 in stock? And how many orders are pending?"}]
      }
    }
  }' | jq -r '(.result.artifacts[]?.parts[]?, .result.parts[]?) | .text? // empty'
```

The first call can take 10 to 20 seconds while the runtime starts. You should get an answer like:

```
KONG-456 (Kong sticker pack) is out of stock until 2026-12-15, and there are 2 pending orders.
```

The model can't know those facts. `0` units, `2026-12-15` and `2` pending orders only exist in the inventory API, so the answer proves the agent called both tools through Kong.

> **Checkpoint: one request crossed all three routes.** The answer includes the restock date and the pending order count from the inventory API.

## Follow the request

Watch the agent's side in its logs. Look for `got a new Kong Identity token` and the tool calls:

```bash
aws logs tail "/aws/bedrock-agentcore/runtimes/$AGENTCORE_IDENTIFIER-DEFAULT" --since 5m --region us-west-2
```

Watch Kong's side in the data plane log. Look for your `/a2a` request, then the agent's `/v1` and `/mcp` requests, all within the same few seconds:

```bash
kubectl logs -n kong deploy/kong-aws-ai-dp --since=5m | grep -E '/(a2a|v1|mcp)'
```

In Konnect, the AI Gateway's **Overview** shows the new model requests and tokens a few minutes later. Those tokens were spent by the agent, not by you, and they're counted against the same Kong Identity client.

---

## Verify

Asking the agent through `/a2a` returns an answer with the inventory API's numbers (out of stock until `2026-12-15`, `2` pending orders), and the data plane log shows `/a2a`, `/v1` and `/mcp` requests for that one question. The Step 4 to 6 checks still pass: `/mcp` and `/v1` still require a token.

## Common problems

- **The answer says it couldn't check, or gives made-up numbers.** The agent didn't reach the tools. Check the agent's logs for a `401` from `/mcp`, which means a wrong `CLIENT_ID` or `CLIENT_SECRET` in `agentcore.json`. Re-run the `jq` command above with the right values exported, then `agentcore deploy` again.
- **The agent returns an error, and its log shows a `401` from `/v1`.** Same cause: the token request failed or used the wrong client. Check that `ISSUER_URL` in `agentcore.json` matches `echo $ISSUER_URL`.
- **The agent's log, or a direct `/v1` call, shows `Model produced invalid sequence as part of ToolUse`.** That error comes from Nova on Bedrock, not from Kong. Nova fails on tool names with hyphens, so the tools are named `check_inventory` and `list_orders`. If you named your own tools with hyphens, rename them. The agent also sets `temperature` to `0`, which AWS's [Nova tool-use troubleshooting guide](https://docs.aws.amazon.com/nova/latest/userguide/tools-troubleshooting.html) recommends.
- **The data plane log shows `/mcp` `tools/list` and one `/v1` call, but no `tools/call`.** The model answered without using a tool, usually because of the error above. Call `/v1` directly with the agent's tools to see the model's response.
- **`agentcore deploy` fails on dependencies.** The lockfile still has the Step 3 pins. Run `(cd app/agent && uv lock)` again from `agentcorekong`, then deploy.
- **The tool call returns `unknown sku`.** The inventory API only knows `KONG-123`, `KONG-456` and `AWS-789`. Ask about one of those.
- **The `curl` prints nothing.** The response had a different shape than expected. Run the same `curl` without the `jq` filter to see the raw response, which includes any error.
- **`scripts/verify.sh` fails on the agent check after this step.** It expected the stub's reply. The updated script accepts any agent answer. Pull the latest version of this repo.

## Tearing this step down

Remove the inventory API:

```bash
kubectl delete -f code/inventory/inventory-api.yaml --ignore-not-found
```

To go back to the Step 3 stub agent, repeat [Create the project](3-a2a-agent-gateway-agentcore.md#create-the-project) from the `cp` command onward, then deploy. [docs/teardown.md](docs/teardown.md) removes everything else, including the AgentCore runtime.

[← Step 6](6-llm-gateway-bedrock.md) · **Step 7** · [Step 8 →](8-rate-limit.md)
