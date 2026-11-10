# Troubleshooting

This page lists common problems by step.

Back to the [README](../README.md).

## Before you start: two things that catch everyone

- **Run everything in one shell session.** Later steps rely on variables exported earlier (`AWS_DOMAIN`, `CERTIFICATE_ARN`, `HOSTED_ZONE_ID`, `PAT`, `AGENTCORE_URL`). If you open a new terminal, re-run the `export` commands.
- **Step 3 resets Kong's configuration; Steps 4 and 5 add to it.** Step 3 runs `deck gateway reset ... -f` before `deck gateway sync`, which deletes everything on the `kong-aws` control plane. Steps 4 and 5 use `deck gateway apply`, which only creates or updates. If you re-run Step 3, re-run the `apply` commands in Steps 4 and 5 afterwards.

## Step 1: EKS and networking

### Helm cannot find the eks chart repository

The `helm install aws-load-balancer-controller eks/aws-load-balancer-controller ...` command refers to a Helm repository named `eks`, but this guide doesn't include a command that adds it. If Helm reports that the repository or chart can't be found, add the AWS EKS charts repository using the instructions in the [AWS Load Balancer Controller documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/), then re-run the `helm install` command.

### The domain registration command fails or is rejected

- The Route 53 Domains API is only available in `us-east-1`, which is why those commands pass `--region us-east-1`.
- Fill in every `<...>` contact placeholder.
- If you already own a domain with a Route 53 hosted zone, you can skip registration and set `AWS_DOMAIN` to that domain.

### OPERATION_ID is empty or the status isn't SUCCESSFUL yet

Registration takes time. Re-run the `get-operation-detail` command until it reports success before moving on.

### The certificate stays PENDING_VALIDATION

- ACM validates by looking up the CNAME record in Route 53. That only works once the domain is registered and Route 53 is authoritative for it.
- Check that `HOSTED_ZONE_ID`, `RESOURCE_RECORD_NAME` and `RESOURCE_RECORD_VALUE` are all non-empty before running `change-resource-record-sets`.
- DNS validation can take from a few minutes to longer.

## Step 2: Kong Konnect data plane

### "namespaces kong not found" on the first command

The namespace block starts with `kubectl delete namespace kong`. On a fresh cluster that namespace doesn't exist yet, so the first line fails. The next lines create it, so you can ignore that error.

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

## Step 3: A2A and AgentCore

### `python3 server_1.py` fails with import errors

Set up the virtual environment and install the A2A SDK first, as described in [code/a2a/python-a2a-sdk-install.md](../code/a2a/python-a2a-sdk-install.md). Its last commands check that `a2a` imports.

### `agentcore deploy` fails, or the agent doesn't start

Check that `pyproject.toml` lists `uvicorn` and `a2a-sdk[all]`, and that `agentcore.json` has `"protocol": "A2A"` and `"entrypoint": "server_1.py"`, as in the examples in [Step 3](../3-a2a-agent-gateway-agentcore.md#agent-configuration). Then tail the runtime logs in CloudWatch with the `aws logs tail` command in Step 3.

### awscurl returns an authorization error

All requests to AgentCore must be SigV4-signed. Run `aws configure` so `awscurl` has credentials. Those credentials also need permission to invoke the runtime.

### Kong returns an error when calling AgentCore

- The Kong pod's IAM role must allow `bedrock-agentcore:InvokeAgentRuntime` and `bedrock-agentcore:GetAgentCard`. Both are in the Step 2 policy. Check that the Pod Identity association names the `kong` namespace and `kaigateway-podid-sa` service account.
- `DECK_AGENTCORE_PATH` must be set when you run `deck gateway sync`, because the decK file reads it with `${{ env "DECK_AGENTCORE_PATH" }}`.

### The test request through Kong fails to resolve

The sample request uses `kong-dp.kong-demo.com`. Use `kong-dp.<your domain>`.

## Step 4: MCP Gateway

### `deck gateway apply` is not a known command

Your decK version is older than the `apply` command. Upgrade decK, then check that `deck gateway apply --help` prints its usage.

### `/mcp` returns 404 "no Route matched with those values"

The configuration hasn't reached the data plane yet, or the apply failed. Re-run the `deck gateway apply` command and read its output, then check that `mcp-route` appears under the `kong-aws` gateway in Konnect.

### The MCP calls are rejected after initialize

MCP servers can issue a session ID in the `Mcp-Session-Id` response header, and expect later requests to send it back. Re-run the initialize command and the `export MCP_SESSION_ID=...` command, check that `echo $MCP_SESSION_ID` prints a value, then retry `tools/list`.

### The response starts with `event:` and `data:` instead of plain JSON

That's the `text/event-stream` form of an MCP response, and it's normal. The JSON-RPC message is on the `data:` line.

### `tools/call` returns an error from the upstream

The tools call `https://httpbin.konghq.com`, a public service. Check that the data plane can reach the internet (the NLB in Step 2 is internet-facing, and EKS nodes need outbound access through a NAT gateway or public subnet).

## Step 5: Kong Identity

### The wrong auth server or scope is picked up

The `export AUTHZ_SERVER_ID=...` and `export SCOPE_ID=...` commands take the first item in the list (`.data[0]`). If your organization already has other auth servers or scopes, check the IDs against the responses of the create calls.

### Introspection says "active": false

The token has expired. The client is created with a 60-second access token lifetime. Get a new token and introspect it straight away.

### `/a2a` still returns 401 with a token

Get a fresh token (it lasts 60 seconds) and call straight away. If it still fails, introspect that same token by hand as shown in Step 5. If Kong Identity reports `"active": true` but Kong still rejects it, check that `DECK_ISSUER`, `DECK_CLIENT_ID`, `DECK_CLIENT_SECRET` and `DECK_KONG_IDENTITY_INTROSPECTION_URL` were set when you ran `deck gateway apply`, then re-run it.

### `deck gateway apply` says `a2a-route` doesn't exist

The plugin attaches to the route created in Step 3. Re-run Step 3's `deck gateway sync`, then the `apply` commands in Steps 4 and 5.

### `/a2a` returns 401 without a token

That's the expected result once Step 5 is applied. Every call now needs a valid Kong Identity token.
