# Step 6: Run the same agents and tools on Konnect AI Gateway

[← Step 5](5-kong-identity-oauth2.md) · **Step 6** · [README →](README.md)

## Why this step

Steps 3 to 5 build the A2A and MCP gateways the classic way: services, routes and plugins on an API Gateway control plane (`kong-aws`). Konnect also has a dedicated **AI Gateway** (AI Gateway 2.x). Instead of plugins, you declare AI entities, and Konnect builds the gateway configuration for you:

| AI Gateway entity | Replaces | Used here for |
|---|---|---|
| **Agent** | the `ai-a2a-proxy` plugin | the AgentCore agent at `/a2a` |
| **MCP Server** | the `ai-mcp-proxy` plugin | the two inventory tools at `/mcp` |
| **Auth Strategy** | the `openid-connect` plugin | Kong Identity token checks |
| **Model** and **Model Provider** | the `ai-proxy-advanced` plugin | Amazon Nova Micro on Bedrock, at `/v1` |

The Agent entity also restores the design Step 3 couldn't build: it can **sign calls to AgentCore with AWS SigV4**, using the data plane's Pod Identity role. Callers present a Kong Identity token, Kong checks it, then Kong signs the AWS call. AgentCore never sees the caller's token, and no runtime needs JWT inbound auth.

This step runs **alongside** Steps 1 to 5. It adds a second control plane, data plane and load balancer at `ai-dp.<your domain>`, and leaves `kong-dp.<your domain>` as it is.

## What it does, in plain English

1. Upgrades the **Kong Operator** to 2.4.0 and turns on its AI Gateway data plane controller.
2. Creates an **AI Gateway** control plane in Konnect (`kong-aws-ai`).
3. Deploys an **AI Gateway data plane** on EKS behind its own NLB with your ACM certificate, running as the Pod Identity service account from Step 2.
4. Points `ai-dp.<your domain>` at the new NLB.
5. With **kongctl**, declares an Auth Strategy (Kong Identity), an Agent (the SigV4 `agent` runtime from Step 3), an MCP Server (the in-cluster echo API from Step 4) and a Model (Amazon Nova Micro on Bedrock).
6. Tests them: `/a2a` without a token, with a bad token and with a valid one, the MCP tools, then an OpenAI-style chat call that Kong sends to Bedrock.

## Before you start

- Steps 1 to 4 are complete, plus Step 3's Kong Identity section. This step reuses:
  - the `kaigateway-podid-sa` service account and IAM role (Step 2);
  - the Konnect login object `konnect-api-auth-conf` (Step 2);
  - the SigV4 AgentCore runtime `agent` (Step 3), whose role allows `bedrock-agentcore:InvokeAgentRuntime`;
  - the Kong Identity issuer and client (Step 3);
  - the in-cluster `httpbin` service (Step 4).
- `AWS_DOMAIN`, `CERTIFICATE_ARN`, `HOSTED_ZONE_ID`, `ISSUER_URL`, `CLIENT_ID` and `CLIENT_SECRET` are exported.
- [kongctl](https://developer.konghq.com/kongctl/) **1.28.4 or newer**, logged in to the Konnect organization that holds `kong-aws` (US region).
- For the model: access to **Amazon Nova Micro** in `us-west-2`. Check it with your own credentials:
  ```bash
  aws bedrock-runtime converse --region us-west-2 --model-id us.amazon.nova-micro-v1:0 \
    --messages '[{"role":"user","content":[{"text":"Say hi"}]}]' --query 'output.message.content[0].text' --output text
  ```
  A short reply means your account can use the model. Step 2's policy already allows Kong's role `bedrock:InvokeModel`.

> **Tested versions.** This step was run end to end with Kong Operator `2.4.0` (Helm chart `1.5.0`), the `kong/kong-ai-gateway:2.3.1` data plane image (Kong 3.15 underneath), kongctl `1.28.4` and EKS `1.35`.

---

## 6a. Upgrade the Kong Operator

The AI Gateway resources need Kong Operator 2.3 or newer. Step 2 pins the operator image to `2.1.5`, so move it to `2.4.0` and enable the AI Gateway data plane controller, which is **off by default**:

```bash
helm repo update kong
helm upgrade kong-operator kong/kong-operator -n kong-system --version 1.5.0 --reuse-values \
  --set image.tag=2.4.0 \
  --set env.enable_controller_aigatewaydataplane=true
kubectl -n kong-system rollout status deployment kong-operator-kong-operator-controller-manager --timeout=180s
kubectl get crd | grep -i aigateway
```

The last command lists the AI Gateway resource types, such as `konnectaigateways.konnect.konghq.com` and `aigatewaydataplanes.aigateway.konghq.com`.

> **Your existing data plane restarts once.** Operator 2.4 changes a default for existing `DataPlane` resources, so `kong-aws-dp` rolls out a new pod. While the NLB registers it, `https://kong-dp.<your domain>` can fail for a minute or two. Check that it answers `404` again before you continue.

## 6b. Create the AI Gateway control plane

```bash
kubectl apply -f code/ai-gateway/konnect-ai-gateway.yaml
kubectl wait konnectaigateway/kong-aws-ai -n kong --for=condition=Programmed=True --timeout=5m
kongctl get ai-gateways
```

`kong-aws-ai` now appears in Konnect under **AI Gateway → Gateways** as **Kong AWS AI Gateway**.

## 6c. Deploy the AI Gateway data plane

[`code/ai-gateway/ai-gateway-dataplane.yaml`](code/ai-gateway/ai-gateway-dataplane.yaml) runs the data plane with the `kaigateway-podid-sa` service account, so Pod Identity gives it the Step 2 IAM role, behind an internet-facing NLB with your ACM certificate. It fills in `CERTIFICATE_ARN` as it applies:

```bash
sed "s|\${CERTIFICATE_ARN}|$CERTIFICATE_ARN|" code/ai-gateway/ai-gateway-dataplane.yaml | kubectl apply -f -
kubectl wait aigatewaydataplane/kong-aws-ai-dp -n kong --for=condition=Ready=True --timeout=10m
kubectl get pods,svc -n kong
```

You should see a `kong-aws-ai-dp-...` pod `Running` and a `kong-aws-ai-dp-ingress` service of type `LoadBalancer`. The data plane also appears under **Data plane nodes** in Konnect.

Two things to know about this manifest:
- **The container must be named `aigw`.** The pod template's `containers` list is required, and the operator's container is called `aigw`. Any other name adds a second container with no image, and the operator logs `containers[1].image: Required value`.
- **The NLB also gets port 8443.** The operator adds Kong's own TLS proxy port to the service. It serves the same routes with Kong's self-signed certificate. It is not the admin API, which stays inside the pod. Clients use 443, where the NLB presents your ACM certificate.

## 6d. Point `ai-dp.<your domain>` at the new NLB

```bash
export AI_LB=$(kubectl get svc kong-aws-ai-dp-ingress -n kong -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export AI_LB_ZONE=$(aws elbv2 describe-load-balancers --region us-west-2 \
  --query "LoadBalancers[?DNSName=='$AI_LB'].CanonicalHostedZoneId" --output text)
aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch '{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "'"ai-dp.$AWS_DOMAIN"'",
      "Type": "A",
      "AliasTarget": {"HostedZoneId": "'"$AI_LB_ZONE"'", "DNSName": "'"$AI_LB"'", "EvaluateTargetHealth": true}
    }
  }]
}'
```

After 2 or 3 minutes, `curl -i https://ai-dp.$AWS_DOMAIN/` returns Kong's `404` (no routes yet). If your machine can't resolve the new name yet, or you get `Empty reply from server`, see the notes in [Step 2](2-kong-konnect-data-plane.md#test-the-load-balancers). The same `--resolve` workaround applies.

## 6e. Declare the auth strategy, agent, MCP server and model

[`code/ai-gateway/ai-gateway.yaml`](code/ai-gateway/ai-gateway.yaml) declares these entities on `kong-aws-ai`:

- **`kong-identity-oidc`**, an OpenID Connect Auth Strategy that introspects Kong Identity tokens. It sets `ssl_verify: true` and an explicit `cache_tokens_salt`, which kongctl requires, as decK does in Step 5.
- **`agentcore-hello`**, an A2A Agent at `/a2a` that points at the **SigV4 `agent` runtime** from Step 3. `upstream.auth.type: aws` with no keys makes the gateway sign each call with its Pod Identity credentials. `access.auth_strategies` makes callers present a Kong Identity token first.
- **`inventory-tools`**, a `conversion-listener` MCP Server at `/mcp` with the same two tools as Step 4, backed by the in-cluster `httpbin`. It uses the same Kong Identity auth strategy, so unlike Step 4's `/mcp`, it isn't open to anyone. An MCP server's `access` block differs from an agent's: it needs `acl_attribute_type: consumer`, and it lists strategies by **name** (`!ref kong-identity-oidc#name`).
- **`aws-bedrock`**, a Bedrock Model Provider with `auth.type: aws` and no keys, so the gateway signs with its Pod Identity role.
- **`nova-micro`**, a Model at `/v1` in OpenAI format, routed to `us.amazon.nova-micro-v1:0` in `us-west-2`. It uses the same Kong Identity auth strategy, so only token holders can spend your Bedrock budget.

The file reads its values from the environment, so no secret is written to disk. The `AGENTCORE_URL` lines rebuild the SigV4 runtime's URL, as in Step 3. Run them from the AgentCore project folder.

```bash
export AGENTCORE_ARN=$(agentcore status --json | jq -r '.resources[] | select(.name=="agent") | .arn')
export AGENTCORE_URL="https://bedrock-agentcore.us-west-2.amazonaws.com/runtimes/$(jq -rn --arg a "$AGENTCORE_ARN" '$a|@uri')/invocations"
export INTROSPECTION_URL=$ISSUER_URL/introspect
export CACHE_TOKENS_SALT=$(openssl rand -hex 16)
```

Preview, then apply (from the root of this repo):

```bash
kongctl diff --mode apply -f code/ai-gateway/ai-gateway.yaml
kongctl apply -f code/ai-gateway/ai-gateway.yaml --auto-approve
```

The preview shows five resources to create, with the client secret and the `!env` values redacted. `apply` creates them, and Konnect pushes them to the data plane within seconds. In Konnect they appear under **Agents**, **MCP Servers**, **Models**, **Providers** and the gateway's **Auth strategies** tab.

Keep the same `CACHE_TOKENS_SALT` value for later applies of this file.

## 6f. Test

```bash
A2A='{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"msg-001","role":"user","parts":[{"kind":"text","text":"hi"}]}}}'

echo "--- no token:"
curl -si -X POST https://ai-dp.$AWS_DOMAIN/a2a --json "$A2A" | grep -i -E "^HTTP|x-kong-upstream-latency"
echo "--- bad token:"
curl -si -X POST https://ai-dp.$AWS_DOMAIN/a2a -H "Authorization: Bearer not-a-real-token" --json "$A2A" | grep -i -E "^HTTP|x-kong-upstream-latency"
echo "--- valid token:"
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" -d grant_type=client_credentials \
  -d client_id=$CLIENT_ID -d client_secret=$CLIENT_SECRET -d scope=scope1 | jq -r .access_token)
curl -s -X POST https://ai-dp.$AWS_DOMAIN/a2a -H "Authorization: Bearer $TOKEN" --json "$A2A" \
  | jq '.result.artifacts[0].parts[0].text'
```

- No token and bad token: `HTTP/1.1 401 Unauthorized` with no `X-Kong-Upstream-Latency` header, so Kong rejected them.
- Valid token: `"that's the response"`. The data plane log shows `[ai-a2a-proxy] Creating aws_iam auth handler`, which is the SigV4 signing:
  ```bash
  kubectl logs -n kong deploy/kong-aws-ai-dp --since=5m | grep -i aws_iam
  ```

Then the MCP server, the same way as Step 4 but with the token on every call:

```bash
MCP_HDRS=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
MCP_INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}'
echo "--- no token:"
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://ai-dp.$AWS_DOMAIN/mcp "${MCP_HDRS[@]}" --data "$MCP_INIT"
echo "--- valid token:"
curl -s -D mcp-headers.txt -X POST https://ai-dp.$AWS_DOMAIN/mcp "${MCP_HDRS[@]}" -H "Authorization: Bearer $TOKEN" --data "$MCP_INIT"
SID=$(grep -i '^mcp-session-id:' mcp-headers.txt | awk '{print $2}' | tr -d '\r')
curl -s -X POST https://ai-dp.$AWS_DOMAIN/mcp "${MCP_HDRS[@]}" -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $SID" \
  --data '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
curl -s -X POST https://ai-dp.$AWS_DOMAIN/mcp "${MCP_HDRS[@]}" -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $SID" \
  --data '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"check-inventory","arguments":{"query_sku":"KONG-123"}}}'
```

Without a token: `401`. With one: `initialize` reports `"name":"Kong AI Gateway"`, `tools/list` shows `check-inventory` and `list-orders` (with `query_sku` and `query_status` arguments), and the tool call returns the echo with `"isError":false`.

Finally the model. Clients call it the way they'd call OpenAI, and Kong translates the request for Bedrock:

```bash
echo "--- no token:"
curl -s -o /dev/null -w "%{http_code}\n" https://ai-dp.$AWS_DOMAIN/v1/chat/completions \
  --json '{"model":"nova-micro","messages":[{"role":"user","content":"hi"}]}'
echo "--- valid token:"
curl -s https://ai-dp.$AWS_DOMAIN/v1/chat/completions -H "Authorization: Bearer $TOKEN" \
  --json '{"model":"nova-micro","messages":[{"role":"user","content":"In one sentence, what does an API gateway do?"}]}' \
  | jq '{model, reply: .choices[0].message.content, usage}'
```

Without a token: `401`. With one: a one-sentence answer, `"model": "us.amazon.nova-micro-v1:0"`, and a `usage` block with prompt, completion and total tokens.

To run all of these in one go: `KONG_HOST=ai-dp.$AWS_DOMAIN MODEL=nova-micro MCP_AUTH=1 ./scripts/verify.sh`.

## See it in Konnect

Open **AI Gateway → Gateways → Kong AWS AI Gateway**:
- **Agents**, **MCP Servers** and **Auth strategies** show the entities from 6e.
- **Data plane nodes** shows the EKS pod and its version.
- **Observability** shows request analytics a few minutes after traffic.

The **Usage** tiles on the gateway's Overview (requests, LLM latency, tokens and estimated cost) fill in from model traffic, a few minutes after the first calls to `/v1`.

---

## Verify

1. `https://ai-dp.<your domain>/a2a` returns `401` from Kong without a token or with a bad one, and the agent's `that's the response` with a valid Kong Identity token.
2. The data plane log shows `Creating aws_iam auth handler`, so Kong signed the AgentCore call itself.
3. `/mcp` returns `401` without a token. With one, it lists both tools and `check-inventory` returns the echo.
4. `/v1/chat/completions` with `"model":"nova-micro"` returns `401` without a token and a Bedrock answer with token usage with one.
5. `https://kong-dp.<your domain>` still works as before.

## Common problems

- **`kubectl wait aigatewaydataplane ...` times out, with no pod and no status on the resource.** The operator's AI Gateway data plane controller is off. Run the `helm upgrade` in 6a with `env.enable_controller_aigatewaydataplane=true`, and check that the operator's environment shows `KONG_OPERATOR_ENABLE_CONTROLLER_AIGATEWAYDATAPLANE=true`.
- **The operator logs `containers[1].image: Required value`.** The pod template's container isn't named `aigw`.
- **`apply` says `spec.deployment.podTemplateSpec.spec.containers: Required value`.** The pod template needs a `containers` list, even when you only set the service account.
- **kongctl says `could not unmarshal ... into any supported union types for AIGatewayMCPServerListenerAccess`.** The MCP server's `access` block has the agent's shape. Add `acl_attribute_type: consumer` and reference the strategy by name: `!ref kong-identity-oidc#name`.
- **`/mcp` still answers without a token.** The MCP server's `access` was never applied (kongctl stops on the first invalid entity, so nothing in the file is applied). Re-run `kongctl diff` and fix any error first.
- **kongctl says `config.cache_tokens_salt is required`.** Export `CACHE_TOKENS_SALT` before `diff` or `apply`.
- **The valid-token call returns `403` or `Missing Authentication Token` from AWS.** The data plane isn't signing with IAM credentials. Check that the deployment uses `kaigateway-podid-sa` (`kubectl get deploy kong-aws-ai-dp -n kong -o jsonpath='{.spec.template.spec.serviceAccountName}'`) and that `AGENTCORE_URL` points at the SigV4 `agent` runtime, not `agentjwt`.
- **The chat call returns an `AccessDenied` from Bedrock.** Either your account doesn't have access to the model in `us-west-2` (run the `converse` check above), or the data plane isn't using `kaigateway-podid-sa`.
- **`brew upgrade kongctl` refuses an untrusted tap, or says kongctl isn't installed.** Run `brew trust kong/kongctl`. If kongctl was installed as a cask, use `brew upgrade --cask kong/kongctl/kongctl`.
- **kongctl reaches the wrong Konnect organization.** If a company wrapper pins kongctl to a profile, run this step from a folder pinned to the profile for the organization that holds `kong-aws`.

## Tearing this step down

```bash
kongctl delete -f code/ai-gateway/ai-gateway.yaml
kubectl delete aigatewaydataplane kong-aws-ai-dp -n kong
kubectl delete konnectaigateway kong-aws-ai -n kong
```

Then delete the `ai-dp.<your domain>` alias record in Route 53. Deleting the data plane also removes its NLB. These teardown commands haven't been tested yet.

[← Step 5](5-kong-identity-oauth2.md) · **Step 6** · [README →](README.md)
