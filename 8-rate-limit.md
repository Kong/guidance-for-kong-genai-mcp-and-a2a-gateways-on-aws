# Step 8: Rate limit the agent

[← Step 7](7-connect-agent-model-tools.md) · **Step 8** · [README →](README.md)

## Why this step

After Step 7, one call to the agent can turn into several model and tool calls, each one spending Bedrock tokens. A runaway client, or another agent stuck in a loop, can run up that bill fast. A rate limit at the gateway stops the extra calls at Kong, before they reach AgentCore, Bedrock or your tools, and without touching the agent's code.

## What it does, in plain English

1. **Declares a rate-limiting AI Policy** that allows 5 requests a minute.
2. **Attaches it to the agent** at `/a2a`. The model at `/v1` and the tools at `/mcp` aren't limited by this policy.
3. **Sends 6 requests in a row.** The first 5 reach the agent, and the 6th gets `429 Too Many Requests` from Kong.

## Before you start

- Steps 1 to 7 are complete, in this terminal, from the root of this repo. Step 7 is optional: the rate limit works the same on the Step 3 stub.
- The Step 5 variables are still exported (`ISSUER_URL`, `INTROSPECTION_URL`, `CLIENT_ID`, `CLIENT_SECRET`, `CACHE_TOKENS_SALT`), plus `AGENTCORE_URL` (Step 3) and `AWS_DOMAIN`.

> **Not yet tested end to end.** The policy follows Kong's [Rate Limiting Policy](https://developer.konghq.com/ai-gateway/policies/rate-limiting/) and [Rate limit A2A traffic](https://developer.konghq.com/ai-gateway/rate-limit-a2a-traffic/) docs. Run each checkpoint before moving on.

---

## Declare the rate limit

[`code/ai-gateway/step8-rate-limit.yaml`](code/ai-gateway/step8-rate-limit.yaml) adds one **AI Policy** and attaches it to the Step 3 agent:

```yaml
ai_gateway_policies:
  - ref: a2a-rate-limit
    ai_gateway: !lookup {name: kong-aws-ai}
    name: a2a-rate-limit
    display_name: A2A rate limit (5 per minute)
    type: rate-limiting
    enabled: true
    config:
      minute: 5
      limit_by: ip
      policy: local
```

- `minute: 5` allows 5 requests per minute. It's deliberately low so you can trigger it by hand.
- `limit_by: ip` counts requests per client address, as Kong sees it.
- `policy: local` keeps the count in the data plane's memory. That's fine with one data plane replica. With several, use `redis` (for example MemoryDB or ElastiCache) so they share one count.

The agent keeps everything from Step 5 and gains one line, `policies: [!ref a2a-rate-limit#name]`. The file re-declares the Step 5 auth strategy so the agent can still reference it.

```bash
kongctl diff --mode apply -f code/ai-gateway/step8-rate-limit.yaml --pat "$PAT"
```

```bash
kongctl apply -f code/ai-gateway/step8-rate-limit.yaml --auto-approve --pat "$PAT"
```

The preview shows one `ai_gateway_policy` to create and one change on `agentcore-hello`: the policy attachment. In Konnect, the policy appears under **AI Gateway → Policies**.

> **kongctl refuses `--pat`?** If a wrapper such as konnect-guard blocks token flags, leave `--pat "$PAT"` off. See [troubleshooting](docs/troubleshooting.md#kongctl-reaches-the-wrong-konnect-organization-or-refuses---pat).

## Hit the limit

Wait about 10 seconds for Konnect to push the configuration. Then get a token and send 6 requests in a row, printing only each response's status code:

```bash
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" -d grant_type=client_credentials \
  -d client_id=$CLIENT_ID -d client_secret=$CLIENT_SECRET -d scope=scope1 | jq -r .access_token)
for i in 1 2 3 4 5 6; do
  curl -s -o /dev/null -w "request $i: %{http_code}\n" -X POST https://ai-dp.$AWS_DOMAIN/a2a \
    -H "Authorization: Bearer $TOKEN" \
    --json '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"msg-rl","role":"user","parts":[{"kind":"text","text":"Is KONG-123 in stock?"}]}}}'
done
```

You should see:

```
request 1: 200
request 2: 200
request 3: 200
request 4: 200
request 5: 200
request 6: 429
```

With the Step 7 agent, each of the first 5 takes a few seconds, because the agent calls the model and the tools. The 6th comes back immediately: Kong refused it without calling AgentCore.

Look at the refused response in full:

```bash
curl -i -X POST https://ai-dp.$AWS_DOMAIN/a2a -H "Authorization: Bearer $TOKEN" \
  --json '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"msg-rl","role":"user","parts":[{"kind":"text","text":"Is KONG-123 in stock?"}]}}}'
```

Expect `HTTP/1.1 429 Too Many Requests`, headers such as `RateLimit-Limit: 5` and `RateLimit-Remaining: 0`, and the body `{"message":"API rate limit exceeded"}`.

> **Checkpoint: Kong enforces the limit.** The 6th request in a minute returns `429` straight from Kong. Wait a minute and run the loop again: the count resets, and the first requests return `200` again.

## What isn't limited

The policy is attached to the agent only. Calls to `/v1` and `/mcp`, including the ones the Step 7 agent makes, aren't counted against it. To limit those too, attach a policy to the `nova-micro` model or the `inventory-tools` MCP server the same way, or set `global: true` on the policy to cover all AI traffic on the gateway.

---

## Verify

Six calls to `/a2a` within a minute return five `200`s and one `429 Too Many Requests` with `RateLimit-Remaining: 0`. A minute later, calls succeed again.

## Common problems

- **All 6 requests return `200`.** The policy didn't attach, or Konnect hadn't pushed it yet. Check the `kongctl diff` output again: it should show nothing left to change. Wait 10 seconds and rerun the loop.
- **The `429` comes earlier than the 6th request.** You already sent requests in the last minute, and they count too. Wait a minute and run the loop again.
- **Every request returns `401`.** The token expired or wasn't set. Run the `TOKEN=` line again.
- **kongctl says the agent references an unknown policy.** Run the apply with the whole `step8-rate-limit.yaml` file, which declares the policy and the agent together.

## Tearing this step down

To remove the limit, remove the `policies` lines from the agent in `step8-rate-limit.yaml`, apply it, then delete the policy in Konnect under **AI Gateway → Policies**. Deleting the AI Gateway ([docs/teardown.md](docs/teardown.md), section 1) also removes it.

[← Step 7](7-connect-agent-model-tools.md) · **Step 8** · [README →](README.md)
