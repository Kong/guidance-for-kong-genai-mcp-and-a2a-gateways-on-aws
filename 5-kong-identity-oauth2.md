# Step 5: Require Kong Identity tokens on the agent and tools

[← Step 4](4-mcp-gateway.md) · **Step 5** · [Step 6 →](6-llm-gateway-bedrock.md)

## Why this step

At the end of Step 4, anyone who knows the `/a2a` or `/mcp` URL can call your agent and your tools. API keys would help, but once agents call agents and tools across teams, you'll want short-lived, scoped tokens that you can check and revoke. In OAuth2 terms that's the **client credentials** grant: each agent or app has a client ID and secret, exchanges them for a short-lived token, and the gateway checks that token on every call. Invalid calls stop at Kong and never reach AWS or your tools.

You have options for the token issuer on AWS. **Amazon Cognito** is a common choice. This guide uses **Kong Identity**, the OAuth2 authorization server built into Konnect, so tokens, scopes and gateway policy are managed in one place.

## What it does, in plain English

1. Creates an **authorization server** in Kong Identity with the Konnect API (`AuthZ_Server_1`, audience `http://kong.dev`), with a **scope** (`scope1`), a **custom claim** (`claim1`) and a **client** (`client1`) that may use the client credentials grant.
2. Plays both sides by hand: gets a token as the client, decodes it with `jwt-cli`, then **introspects** it as the gateway will.
3. Declares an **Auth Strategy** on the AI Gateway that checks tokens with Kong Identity, and attaches it to the Step 3 agent and the Step 4 MCP server.
4. Calls `/a2a` and `/mcp` without a token and with a bad one (both rejected by Kong with `401`), then with a valid one.

## Before you start

- Steps 2 to 4 are complete. `PAT`, `AWS_DOMAIN` and `AGENTCORE_URL` are exported (Steps 2 and 3). The API calls use the Konnect **US** region (`us.api.konghq.com`).
- `jwt-cli` is installed for `jwt decode`.

> **Tested.** This step was run end to end against the `kong/kong-ai-gateway:2.3.1` data plane with kongctl `1.28.4`.

---

# Create the token issuer in Kong Identity

The commands use the [Kong Identity API](https://developer.konghq.com/api/konnect/kong-identity) in the Konnect **US** region, and take each ID straight from its create response.

Create the authorization server:
```
AUTHZ_JSON=$(curl -s -X POST https://us.api.konghq.com/v1/auth-servers \
  -H "Authorization: Bearer $PAT" \
  --json '{"name":"AuthZ_Server_1","audience":"http://kong.dev","description":"AuthZ Server 1"}')
echo "$AUTHZ_JSON" | jq '{id, name, audience, issuer}'
export AUTHZ_SERVER_ID=$(echo "$AUTHZ_JSON" | jq -r .id)
export ISSUER_URL=$(echo "$AUTHZ_JSON" | jq -r .issuer)
```

You should see an `id` and an issuer like `https://xxxxxx.us.identity.konghq.com/auth`. Authorization server names are unique per organization and region, so if the name is taken, pick another.

Add a scope and a custom claim:
```
SCOPE_JSON=$(curl -s -X POST "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/scopes" \
  -H "Authorization: Bearer $PAT" \
  --json '{"name":"scope1","description":"scope1","default":false,"include_in_metadata":false,"enabled":true}')
echo "$SCOPE_JSON" | jq '{id, name}'
export SCOPE_ID=$(echo "$SCOPE_JSON" | jq -r .id)
```

```
curl -s -X POST "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/claims" \
  -H "Authorization: Bearer $PAT" \
  --json '{"name":"claim1","value":"claim1","include_in_token":true,"include_in_all_scopes":false,"include_in_scopes":["'$SCOPE_ID'"],"enabled":true}' | jq '{id, name}'
```

Create the client, the machine-to-machine credential callers will use. Its tokens last **900 seconds (15 minutes)**, long enough to run this step's tests with one token.
```
CLIENT_JSON=$(curl -s -X POST "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/clients" \
  -H "Authorization: Bearer $PAT" \
  --json '{"name":"client1","grant_types":["client_credentials"],"allow_all_scopes":false,"allow_scopes":["'$SCOPE_ID'"],"access_token_duration":900,"id_token_duration":900,"response_types":["id_token","token"]}')
echo "$CLIENT_JSON" | jq 'del(.client_secret)'
export CLIENT_ID=$(echo "$CLIENT_JSON" | jq -r .id)
export CLIENT_SECRET=$(echo "$CLIENT_JSON" | jq -r .client_secret)
echo "secret length: ${#CLIENT_SECRET}"
```

Konnect shows the client secret only once, and these commands keep it in your shell rather than on screen. If you lose it, create a new client.

Get a token and look at its claims:
```
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" -d "scope=scope1" | jq -r '.access_token')
echo $TOKEN | jwt decode - | sed -n '/Token claims/,$p'
curl -s $ISSUER_URL/.well-known/openid-configuration | jq '{issuer, jwks_uri}'
```

The token's `iss` equals the `issuer` in the discovery document, and `client_id` equals `$CLIENT_ID`. `exp` minus `iat` is `900`.

# Explore Kong Identity

## Check your Authorization Server

Kong Identity provides the standard endpoint `$ISSUER_URL/.well-known/openid-configuration`, where you can see the issuer, token, introspection and key endpoints:

```
curl -s $ISSUER_URL/.well-known/openid-configuration | jq
```

List the authorization servers in your organization:

```
curl -sX GET "https://us.api.konghq.com/v1/auth-servers" \
  -H "Authorization: Bearer $PAT" | jq '.data[] | {id, name, issuer}'
```

### Kong Identity User Interface

You can also check the Konnect UI (**Identity**) for your authorization server and its clients, scopes and claims.

## Explore the Token and Introspection Endpoints

To exercise the introspection endpoint, send some requests to Kong Identity, acting as the consumer and then as the gateway.

### Token Endpoint

First, play the consumer role and use the [**client credentials grant**](https://oauth.net/2/grant-types/client-credentials/) to get an access token:

```
TOKEN=$(curl -s -X POST "$ISSUER_URL/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=scope1" | jq -r '.access_token')
```

Decode the access token:

```
echo $TOKEN | jwt decode -
```

You should get output like this. The `sub` field is the same as the `client_id`, and `exp` is 900 seconds after `iat`.

```
Token header
------------
{
  "typ": "JWT",
  "alg": "RS256",
  "kid": "0c6b4da3-e954-43fb-b435-29df04f40bdf"
}

Token claims
------------
{
  "aud": [
    "http://kong.dev"
  ],
  "claim1": "claim1",
  "client_id": "xxxxxx",
  "exp": 1771351824,
  "iat": 1771350924,
  "iss": "https://xxxxxxxx.us.identity.konghq.com/auth",
  "jti": "019c6cbe-1de8-7bb4-b1a4-85c5864a1eb0",
  "nbf": 1771350924,
  "scope": "scope1",
  "sub": "xxxxxx"
}
```

You can list the tokens issued to a client:
```
curl -sX GET "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID/clients/$CLIENT_ID/tokens" -H "Authorization: Bearer $PAT" | jq
```

### Introspection Endpoint

Now play the gateway role and ask Kong Identity whether the token is valid. The [`-u` curl option](https://curl.se/docs/manpage.html#-u) sends the client ID and secret.

```
curl -s -X POST "$ISSUER_URL/introspect" \
  -d "token=$TOKEN" \
  -u "$CLIENT_ID:$CLIENT_SECRET" | jq
```

Here's a typical response. `"active": true` means the token is still good.

```
{
  "active": true,
  "claim1": "claim1",
  "client_id": "xxxxxxxx",
  "scope": "scope1"
}
```

Once the token expires (15 minutes for this client), the endpoint returns:

```
{
  "active": false
}
```

# Protect the agent and the MCP server

An **Auth Strategy** of type `openid-connect` in `introspection` mode asks Kong Identity "is this token active?" on every request, and rejects the request if it isn't. It uses the same client ID and secret you just used for introspection.

[`code/ai-gateway/step5-auth.yaml`](code/ai-gateway/step5-auth.yaml) declares the strategy, `kong-identity-oidc`, and re-declares the Step 3 agent and the Step 4 MCP server with an `access` block that references it:

- **Auth Strategy:** `issuer`, `client_id`, `client_secret`, `auth_methods: [introspection]` and `introspection_endpoint`, read from the environment. It also sets `ssl_verify: true` and an explicit `cache_tokens_salt`, which kongctl requires so a later apply doesn't regenerate it.
- **Agent:** `access.auth_strategies: [!ref kong-identity-oidc]`.
- **MCP server:** an MCP server's `access` block has a different shape. It needs `acl_attribute_type: consumer`, and it lists strategies by **name** (`!ref kong-identity-oidc#name`).

Set the values the file reads. The client secret is sent to Konnect as a secret and never written to the file:

```bash
export INTROSPECTION_URL=$ISSUER_URL/introspect
export CACHE_TOKENS_SALT=$(openssl rand -hex 16)
```

Keep the same `CACHE_TOKENS_SALT` value for later applies, including Step 6.

```bash
kongctl diff --mode apply -f code/ai-gateway/step5-auth.yaml --pat "$PAT"
kongctl apply -f code/ai-gateway/step5-auth.yaml --auto-approve --pat "$PAT"
```

> **kongctl refuses `--pat`?** If a wrapper such as konnect-guard blocks token flags, leave `--pat "$PAT"` off and pin this folder to a kongctl profile for the organization that holds `kong-aws-ai`. See [troubleshooting](docs/troubleshooting.md#kongctl-reaches-the-wrong-konnect-organization-or-refuses---pat).

The preview shows one `ai_gateway_auth_strategy` to create, with the secret and the `!env` values redacted, and the agent and MCP server to update with their `access` block. In Konnect the strategy appears under the gateway's **Auth strategies** tab.

kongctl validates the whole file before it changes anything. If it reports an error, nothing in the file was applied, so fix the error and run it again.

## Test the agent

Wait about 10 seconds, then:

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

- **No token and bad token:** `HTTP/1.1 401 Unauthorized` with **no** `X-Kong-Upstream-Latency` header. That header only appears when a request went upstream, so its absence shows Kong rejected the call itself.
- **Valid token:** `"that's the response"`. Kong checked the token with Kong Identity, then signed the call to AgentCore with its IAM role as in Step 3.

## Test the MCP server

```bash
MCP_HDRS=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
MCP_INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}'
echo "--- no token:"
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://ai-dp.$AWS_DOMAIN/mcp "${MCP_HDRS[@]}" --data "$MCP_INIT"
echo "--- valid token:"
curl -s -D mcp-headers.txt -X POST https://ai-dp.$AWS_DOMAIN/mcp "${MCP_HDRS[@]}" -H "Authorization: Bearer $TOKEN" --data "$MCP_INIT"
SID=$(grep -i '^mcp-session-id:' mcp-headers.txt | awk '{print $2}' | tr -d '\r')
curl -s -X POST https://ai-dp.$AWS_DOMAIN/mcp "${MCP_HDRS[@]}" -H "Authorization: Bearer $TOKEN" -H "Mcp-Session-Id: $SID" \
  --data '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"check_inventory","arguments":{"query_sku":"KONG-123"}}}'
```

Without a token: `401`. With one: the initialize result, then the tool's echo with `"isError":false`.

---

## Verify

1. `curl -s $ISSUER_URL/.well-known/openid-configuration | jq` returns your authorization server's OpenID configuration.
2. `echo $TOKEN | jwt decode -` shows `"aud": ["http://kong.dev"]`, `"scope": "scope1"` and `"claim1": "claim1"`.
3. Calls to `/a2a` and `/mcp` **without** a token, or with a bad one, return `401` from Kong. The same calls **with** a fresh token reach the agent and the tools.

## Common problems

- **kongctl says `config.cache_tokens_salt is required`.** Export `CACHE_TOKENS_SALT` before `diff` or `apply`.
- **kongctl says `could not unmarshal ... into any supported union types for AIGatewayMCPServerListenerAccess`.** The MCP server's `access` block has the agent's shape. It needs `acl_attribute_type: consumer` and the strategy referenced by name (`!ref kong-identity-oidc#name`), as in `step5-auth.yaml`.
- **`/a2a` or `/mcp` still answers without a token.** The apply didn't happen. kongctl stops on the first invalid entity and applies nothing. Re-run `kongctl diff` and fix any error first.
- **A call with a token still returns `401`.** The token has probably expired (15-minute lifetime). Get a new one. If it still fails, introspect the token by hand as shown above, and check that `ISSUER_URL`, `CLIENT_ID` and `CLIENT_SECRET` were set when you applied the file.
- **More:** see [docs/troubleshooting.md](docs/troubleshooting.md#step-5-kong-identity).

## Tearing this step down

Section 2 of [docs/teardown.md](docs/teardown.md) deletes the `AuthZ_Server_1` authorization server. Deleting the AI Gateway (section 1) removes the auth strategy.

[← Step 4](4-mcp-gateway.md) · **Step 5** · [Step 6 →](6-llm-gateway-bedrock.md)
