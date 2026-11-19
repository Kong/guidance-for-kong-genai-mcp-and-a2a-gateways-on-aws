# Troubleshooting

This page lists common problems by step.

Back to the [README](../README.md).

## Before you start: two things that catch everyone

- **Run everything in one shell session.** Later steps rely on variables exported earlier (`AWS_DOMAIN`, `CERTIFICATE_ARN`, `HOSTED_ZONE_ID`, `PAT`, `ISSUER_URL`, `CLIENT_ID`, `CLIENT_SECRET`, `JWT_URL`). If you open a new terminal, re-run the `export` commands. The client secret can't be shown again, so if you lose it, create a new Kong Identity client and update the AgentCore runtime's `allowedClients`.
- **Step 3 resets Kong's configuration; Steps 4 and 5 add to it.** Step 3 runs `deck gateway reset ... -f` before `deck gateway sync`, which deletes everything on the `kong-aws` control plane. Steps 4 and 5 use `deck gateway apply`, which only creates or updates. If you re-run Step 3, re-run the `apply` commands in Steps 4 and 5 afterwards.

## Step 1: EKS and networking

### Helm cannot find the eks chart repository

Run `helm repo add eks https://aws.github.io/eks-charts` and `helm repo update eks`, then re-run the `helm install` command.

### `create-policy` fails with EntityAlreadyExists

IAM policy names are global to the AWS account, and a shared account may already have one with the guide's name, possibly an outdated version. Create the policy with a suffixed name (for example `AWSLoadBalancerControllerIAMPolicy-kong314`) and use that name in the Pod Identity command and in clean-up.

### The domain registration command fails or is rejected

- The Route 53 Domains API is only available in `us-east-1`, which is why those commands pass `--region us-east-1`.
- Fill in every `<...>` contact placeholder.
- If you already own a domain with a Route 53 hosted zone, you can skip registration and set `AWS_DOMAIN` to that domain.

### OPERATION_ID is empty or the status isn't SUCCESSFUL yet

Registration takes time. Re-run the `get-operation-detail` command until it reports success before moving on.

### The certificate stays PENDING_VALIDATION

- ACM validates by looking up the CNAME record through public DNS. That only works once the domain is registered and delegated to the hosted zone you wrote the record into.
- Check the delegation: `dig NS $AWS_DOMAIN @8.8.8.8 +short` must list the same name servers as the hosted zone's delegation set. `NXDOMAIN` or different name servers mean the zone isn't the one the internet uses (an expired registration, or a leftover zone).
- Check that public DNS sees the record: `dig +short CNAME $RESOURCE_RECORD_NAME @8.8.8.8` must return the validation value.
- Check that `HOSTED_ZONE_ID`, `RESOURCE_RECORD_NAME` and `RESOURCE_RECORD_VALUE` are all non-empty before running `change-resource-record-sets`.
- Once DNS is right, validation usually completes within a few minutes.

## Step 2: Kong Konnect data plane

### The operator or data plane doesn't come up

Follow the logs with the two `kubectl logs -f ...` commands in [Step 2](../2-kong-konnect-data-plane.md). Common causes:
- `PAT` is wrong, expired or not exported when the `KonnectAPIAuthConfiguration` was applied.
- Your Konnect organization isn't in the US region. The guide hard-codes `serverURL: us.api.konghq.com`.

### DATA_PLANE_LB is empty

The NLB is still being provisioned. Wait a few minutes after applying the `DataPlane` resource, then re-run the `export DATA_PLANE_LB=...` command.

### HTTP works but HTTPS doesn't

The `DataPlane` manifest reads `$CERTIFICATE_ARN` when you apply it. If the variable was empty, the NLB has no certificate on 443. Check the listeners with the `describe-listeners` command in Step 2.

### curl returns 404 "no Route matched with those values"

That's the expected result at the end of Step 2. Kong is up but has no routes yet.

### curl says "Could not resolve host"

Your machine's resolver hasn't picked up the new `kong-dp` record yet, even if public DNS has (`dig +short kong-dp.$AWS_DOMAIN @8.8.8.8`). Pin the address until it catches up:

```
export KONG_IP=$(dig +short kong-dp.$AWS_DOMAIN @8.8.8.8 | head -1)
curl --resolve kong-dp.$AWS_DOMAIN:443:$KONG_IP https://kong-dp.$AWS_DOMAIN
```

`scripts/verify.sh` does this for you.

### curl says "Empty reply from server"

TLS worked, but the NLB had no healthy target behind the address you reached. Right after the `DataPlane` is created, health checks are still warming up. Later, with one Kong pod and cross-zone load balancing off, NLB addresses in zones without a pod can keep dropping connections. Wait until the target group reports `healthy`, then re-resolve the name and retry, or run more data plane replicas.

### Kong silently ignores new configuration

If decK and Konnect both report success but the data plane keeps behaving as before (a new route returns 404, a new plugin has no effect), the data plane probably **rejected** the new configuration and kept the old one. It logs why:

```
kubectl logs -n kong $(kubectl get pod -n kong -o name | grep dataplane-kong-aws) --since=10m | grep -i -E "error|invalid"
```

One plugin entity that fails validation on the data plane blocks the whole configuration, including unrelated routes. A common case is `ssl_verify invalid value: global tls_certificate_verify option is enabled, ssl_verify cannot be disabled` (see [Step 5](#step-5-kong-identity)).

## Step 3: A2A and AgentCore

### `python3 server_1.py` fails with import errors

Set up the virtual environment and install the A2A SDK first, as described in [code/a2a/python-a2a-sdk-install.md](../code/a2a/python-a2a-sdk-install.md). Its last commands check that `a2a` imports. `server_1.py` needs `a2a-sdk` 1.x (`a2a.helpers`).

### `agentcore create` rejects `--defaults`

Current AgentCore CLI versions use `--template`. Step 3 uses `--template a2a-python-strands`. `agentcore create --help` lists the templates.

### The deployed agent crashes with `No module named 'a2a.helpers'`

The CLI template's `pyproject.toml` pins `a2a-sdk ~= 0.3`. Replace it with the one in [Step 3](../3-a2a-agent-gateway-agentcore.md#agent-configuration), which leaves `a2a-sdk[all]` unpinned, and redeploy. For local runs, also refresh the template's lockfile with `uv lock --upgrade-package a2a-sdk`.

### `agentcore deploy` fails, or the agent doesn't start

Check that `pyproject.toml` lists `uvicorn` and `a2a-sdk[all]`, and that `agentcore.json` has `"protocol": "A2A"` and `"entrypoint": "server_1.py"` for each runtime, as in [Step 3](../3-a2a-agent-gateway-agentcore.md#agent-configuration). Then tail the runtime logs in CloudWatch with the `aws logs tail` command in Step 3. If the CLI can't find credentials from an `aws login` session, run `eval "$(aws configure export-credentials --format env)"` first.

### `agentcore add runtime` says customJwtAuthorizer is required

The CLI expects the key `customJwtAuthorizer` (the AWS API spells it `customJWTAuthorizer`). Rebuild `AUTH_CFG` with the CLI's spelling.

### AgentCore says "Ineffectual token, will expire within the next minute"

AgentCore rejects tokens that expire within about a minute, so a 60-second token always fails. Give the Kong Identity client a longer `access_token_duration` (Step 3 uses 900 seconds), for example with a `PATCH` to `/v1/auth-servers/$AUTHZ_SERVER_ID/clients/$CLIENT_ID`, then fetch a new token.

### awscurl returns an authorization error

The `agent` runtime uses SigV4. Make sure `awscurl` has credentials (`aws configure`, or export them from an `aws login` session) with permission to invoke the runtime. `awscurl` doesn't work against the `agentjwt` runtime, which only accepts bearer tokens.

### `deck gateway sync` fails with "validation error: unknown field"

The `ai-a2a-proxy` config contains an `auth:` block. In Kong 3.14 this plugin has only `max_request_body_size` and `logging` settings. Remove the block. To see a plugin's fields for your version, fetch its schema from Konnect: `https://us.api.konghq.com/v2/control-planes/<control plane ID>/core-entities/schemas/plugins/ai-a2a-proxy`.

### Kong returns "Missing Authentication Token" from AgentCore

The call reached AgentCore without a usable token: the `Authorization: Bearer` header is missing, or the token was issued to a client other than the one in the runtime's `allowedClients`. Also check that `DECK_AGENTCORE_PATH` was built from `JWT_URL` (the `agentjwt` runtime), not from the SigV4 runtime's URL.

### `DECK_AGENTCORE_PATH` is empty

`deck gateway sync` reads it with `${{ env "DECK_AGENTCORE_PATH" }}`. Re-run the `export JWT_ARN=...`, `export JWT_URL=...` and `export DECK_AGENTCORE_PATH=...` commands in the same shell.

### decK says the token flag isn't allowed

Some company setups wrap `deck` and refuse `--konnect-token`, taking the token from a pinned profile. Drop the flag and make sure the profile points at the Konnect organization that holds `kong-aws`. `deck gateway ping --konnect-control-plane-name kong-aws` is a safe check.

## Step 4: MCP Gateway

### `deck gateway apply` is not a known command

Your decK version is older than the `apply` command. Upgrade decK, then check that `deck gateway apply --help` prints its usage.

### `/mcp` returns 404 "no Route matched with those values"

The configuration hasn't reached the data plane yet, or the apply failed. Re-run the `deck gateway apply` command and read its output, then check that `mcp-route` appears under the `kong-aws` gateway in Konnect.

### The MCP calls are rejected after initialize

MCP servers can issue a session ID in the `Mcp-Session-Id` response header, and expect later requests to send it back. Re-run the initialize command and the `export MCP_SESSION_ID=...` command, check that `echo $MCP_SESSION_ID` prints a value, then retry `tools/list`.

### The response starts with `event:` and `data:` instead of plain JSON

That's the `text/event-stream` form of an MCP response, and it's normal. The JSON-RPC message is on the `data:` line.

### `tools/call` says "'sku' was unexpected"

Kong prefixes each tool argument with where it goes in the REST call. Use `query_sku` and `query_status`, as `tools/list` shows.

### `tools/call` returns "HTTP call failed with status 502"

Kong couldn't complete the REST call. The data plane log has the reason next to the request ID. `upstream SSL certificate verify error: (20:unable to get local issuer certificate)` means Kong can't verify the backend's certificate. This happens with the public `https://httpbin.konghq.com`, which is why Step 4 runs an echo backend in the cluster. Check that the `httpbin` deployment in the `kong` namespace is running, and that the service URL is `http://httpbin.kong.svc.cluster.local:8080/anything`.

## Step 5: Kong Identity

### decK requires `cache_tokens_salt`

decK refuses to sync the `openid-connect` plugin without an explicit `cache_tokens_salt`, so later syncs don't regenerate it. Export `DECK_CACHE_TOKENS_SALT=$(openssl rand -hex 16)` and re-run the apply. Keep the same value for later applies.

### The plugin was applied but `/a2a` behaves as before

If a call without a token gets a `401` **with** an `X-Kong-Upstream-Latency` header, the rejection came from AgentCore and the plugin isn't active. Check the data plane log (see [Kong silently ignores new configuration](#kong-silently-ignores-new-configuration)). `ssl_verify cannot be disabled` means the plugin needs `ssl_verify: true`, as in Step 5's decK file.

### Introspection says "active": false

The token has expired. The client from Step 3 issues tokens that last 15 minutes. Get a new token and introspect it straight away.

### `/a2a` still returns 401 with a token

Get a fresh token and call straight away. If it still fails, introspect that same token by hand as shown in Step 5. If Kong Identity reports `"active": true` but Kong still rejects it, check that `DECK_ISSUER`, `DECK_CLIENT_ID`, `DECK_CLIENT_SECRET` and `DECK_KONG_IDENTITY_INTROSPECTION_URL` were set when you ran `deck gateway apply`, then re-run it.

### `deck gateway apply` says `a2a-route` doesn't exist

The plugin attaches to the route created in Step 3. Re-run Step 3's `deck gateway sync`, then the `apply` commands in Steps 4 and 5.

### `/a2a` returns 401 without a token

That's the expected result once Step 5 is applied. Every call now needs a valid Kong Identity token.
