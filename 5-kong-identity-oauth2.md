# Step 5: Protect the A2A route with Kong Identity (OAuth2)

[← Step 4](4-mcp-gateway.md) · **Step 5** · [Step 6 →](6-konnect-ai-gateway.md)

## Why this step

At the end of Step 3, the AgentCore runtime only answers calls that carry a valid Kong Identity token. But Kong forwards *every* request to AWS, valid or not, and leaves the rejection to AgentCore. That works, but the gateway can't tell callers apart, can't apply per-client limits, and gives the same protection only to agents that check tokens themselves.

This step makes Kong check the token first. In OAuth2 terms, callers use the **client credentials** grant: each agent or app has a client ID and secret, exchanges them for a short-lived token, and the gateway checks that token on every call. Invalid calls stop at Kong and never reach AWS. Valid calls continue to AgentCore, which checks the token again.

You have options for the token issuer on AWS. **Amazon Cognito** is a common choice. This guide uses **Kong Identity**, the OAuth2 authorization server built into Konnect, so tokens, scopes and gateway policy are managed in one place.

## What it does, in plain English

1. Explores the Kong Identity **authorization server**, **scope**, **claim** and **client** you created in Step 3.
2. Plays both sides by hand: gets a token as the client, decodes it with `jwt-cli`, then **introspects** it as the gateway will.
3. Adds Kong's **OpenID Connect** plugin to Step 3's `a2a-route`, so Kong checks every token with Kong Identity before the call reaches AgentCore.
4. Calls `/a2a` without a token and with a bad token (both rejected by Kong with `401`) and with a valid one (the agent answers).

The plugin is added with `deck gateway apply`, which doesn't delete anything, so Step 4's `/mcp` route keeps working.

## Before you start

- Step 3 is complete, including its Kong Identity section, so the `a2a-route` exists on `kong-aws` and AgentCore trusts your client.
- `PAT`, `AWS_DOMAIN`, `AUTHZ_SERVER_ID`, `ISSUER_URL`, `CLIENT_ID` and `CLIENT_SECRET` are exported (Steps 2 and 3). The API calls use the Konnect **US** region (`us.api.konghq.com`).
- `jwt-cli` is installed for `jwt decode`.

> **Tested.** This step was run end to end against Kong Gateway `3.14.0.3` on the guide's EKS and Konnect setup. The data plane there enforces global TLS certificate verification, which is why the plugin below sets `ssl_verify: true`.

---

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

# Protect the A2A route

Kong's [OpenID Connect plugin](https://developer.konghq.com/plugins/openid-connect/) in `introspection` mode asks Kong Identity "is this token active?" on every request, and rejects the request if it isn't. It uses the same client ID and secret you just used for introspection. When the token is valid, Kong forwards the request with its `Authorization` header unchanged, so AgentCore can check the token again.

Set the values the decK file reads. `cache_tokens_salt` must be an explicit value: decK refuses to sync the plugin without one, so that later syncs don't regenerate it.

```bash
export DECK_ISSUER=$ISSUER_URL
export DECK_KONG_IDENTITY_INTROSPECTION_URL=$ISSUER_URL/introspect
export DECK_CLIENT_ID=$CLIENT_ID
export DECK_CLIENT_SECRET=$CLIENT_SECRET
export DECK_CACHE_TOKENS_SALT=$(openssl rand -hex 16)
```

Write a decK file that attaches the plugin to Step 3's `a2a-route`:

```bash
cat > a2a-oidc.yaml << 'EOF'
_format_version: "3.0"
plugins:
- name: openid-connect
  route: a2a-route
  instance_name: openid-connect-a2a-kong-identity
  enabled: true
  config:
    issuer: ${{ env "DECK_ISSUER" }}
    client_id:
    - ${{ env "DECK_CLIENT_ID" }}
    client_secret:
    - ${{ env "DECK_CLIENT_SECRET" }}
    auth_methods:
    - introspection
    introspection_endpoint: ${{ env "DECK_KONG_IDENTITY_INTROSPECTION_URL" }}
    cache_tokens_salt: ${{ env "DECK_CACHE_TOKENS_SALT" }}
    ssl_verify: true
EOF
```

> **Why `ssl_verify: true`.** The plugin's `ssl_verify` defaults to `false`. A data plane with global TLS certificate verification turned on (`tls_certificate_verify`) **rejects the whole configuration** with `ssl_verify cannot be disabled` and keeps running the previous one. Nothing fails in decK or Konnect; the new plugin, and anything applied after it, silently doesn't take effect. Setting it to `true` works on every data plane.

Apply it. Like Step 4, `deck gateway apply` adds the plugin and leaves the rest of the configuration alone:

```bash
deck gateway apply --konnect-control-plane-name kong-aws --konnect-token $PAT a2a-oidc.yaml
```

Wait about 10 seconds. To confirm the data plane accepted the new configuration, check its log for errors:

```bash
kubectl logs -n kong $(kubectl get pod -n kong -o name | grep dataplane-kong-aws) --since=2m | grep -i -E "error|invalid"
```

No output is good.

### Call the A2A route without a token

The first line of the response should be `HTTP/1.1 401 Unauthorized`, with a `WWW-Authenticate: Bearer ... error="invalid_token"` header:

```bash
curl -si -X POST https://kong-dp.$AWS_DOMAIN/a2a \
  --json '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"msg-001","role":"user","parts":[{"kind":"text","text":"hi"}]}}}' \
  | grep -i -E "^HTTP|x-kong-upstream-latency|www-authenticate"
```

**Check who rejected it.** If Kong rejected the call, the response has **no** `X-Kong-Upstream-Latency` header, because it never went upstream. If that header is present, the call reached AgentCore, which means the plugin isn't active (see the log check above).

### Call it with a bad token

```bash
curl -si -X POST https://kong-dp.$AWS_DOMAIN/a2a -H "Authorization: Bearer not-a-real-token" \
  --json '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"msg-001","role":"user","parts":[{"kind":"text","text":"hi"}]}}}' \
  | grep -i -E "^HTTP|x-kong-upstream-latency|www-authenticate"
```

Again a `401` from Kong, with no upstream latency header.

### Call it with a token

Get a fresh token by running the command under [Token Endpoint](#token-endpoint) again. Then send the same request with it:

```bash
curl -s -X POST https://kong-dp.$AWS_DOMAIN/a2a \
  -H "Authorization: Bearer $TOKEN" \
  --json '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"kind":"message","messageId":"msg-001","role":"user","parts":[{"kind":"text","text":"How much is 100 USD in EUR?"}]}}}' | jq
```

This time the agent on AgentCore answers with the `that's the response` artifact. Kong checked the token with Kong Identity and passed it on, and AgentCore checked it again. The caller needs an OAuth2 token, never AWS credentials.

> **What about `/mcp`?** MCP clients expect the MCP authorization flow, where the server tells the client where to get a token. Kong's MCP OAuth2 plugin handles that, and is the natural next step for protecting Step 4's route.

---

## Verify

1. `curl -s $ISSUER_URL/.well-known/openid-configuration | jq` returns your authorization server's OpenID configuration.
2. `echo $TOKEN | jwt decode -` shows `"aud": ["http://kong.dev"]`, `"scope": "scope1"` and `"claim1": "claim1"`.
3. A call to `/a2a` **without** a token, or with a bad one, returns `401 Unauthorized` with no `X-Kong-Upstream-Latency` header. The same call **with** a fresh token returns the agent's `that's the response` artifact.

[`scripts/verify.sh`](scripts/verify.sh) runs these checks, plus Step 4's, in one go. See [docs/demo.md](docs/demo.md).

## Common problems

- **decK says `openid-connect plugin requires explicit non-empty config values for cache_tokens_salt`.** `DECK_CACHE_TOKENS_SALT` isn't set in this shell. Export it and re-run the apply.
- **The no-token call returns 401, but with an `X-Kong-Upstream-Latency` header, or `/mcp` suddenly returns 404.** The data plane rejected the new configuration and is still running the old one. Check its log (`kubectl logs ... | grep error`). `ssl_verify cannot be disabled` means the plugin is missing `ssl_verify: true`.
- **A call with a token still returns `401`.** The token has probably expired (15-minute lifetime). Get a new one and call straight away. If it still fails, introspect the token by hand as shown above to see whether Kong Identity considers it active.
- **`deck gateway apply` reports that `a2a-route` doesn't exist.** Step 3's configuration isn't on `kong-aws`. Re-run Step 3's `deck gateway sync`, then Step 4's and this step's `apply` commands.
- **More:** see [docs/troubleshooting.md](docs/troubleshooting.md#step-5-kong-identity).

## Tearing this step down

Delete the `AuthZ_Server_1` authorization server in Konnect (**Identity**). Deleting the `kong-aws` control plane in [Clean up](README.md#clean-up) removes the plugin. Delete `a2a-oidc.yaml` from your working directory when you're done.

[← Step 4](4-mcp-gateway.md) · **Step 5** · [Step 6 →](6-konnect-ai-gateway.md)
