# Troubleshooting

This page lists common problems by step.

Back to the [README](../README.md).

## Before you start: two things that catch everyone

- **Run everything in one shell session.** Later steps rely on variables exported earlier (`AWS_DOMAIN`, `CERTIFICATE_ARN`, `HOSTED_ZONE_ID`, `PAT`, `AGENTCORE_URL`, `ISSUER_URL`, `CLIENT_ID`, `CLIENT_SECRET`, `INTROSPECTION_URL`, `CACHE_TOKENS_SALT`). If you open a new terminal, re-run the `export` commands. The client secret can't be shown again, so if you lose it, create a new Kong Identity client and re-run Step 5's `kongctl apply`.
- **kongctl `apply` only creates and updates.** Each step's file adds to the gateway without removing what earlier steps declared, so you can re-run any step's `apply` safely.

## Step 1: EKS and networking

### Helm cannot find the eks chart repository

Run `helm repo add eks https://aws.github.io/eks-charts` and `helm repo update eks`, then re-run the `helm install` command.

### `create-policy` fails with EntityAlreadyExists

IAM policy names are global to the AWS account, and a shared account may already have one with the guide's name, possibly an outdated version. That's why the guide uses the suffixed name `AWSLoadBalancerControllerIAMPolicy-kong314`. If that name is taken too, use a different suffix, and use that name in the Pod Identity command and in clean-up.

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

## Step 2: Kong AI Gateway on EKS

### `kubectl wait aigatewaydataplane ...` times out, with no pod and no status

The operator's AI Gateway data plane controller is off by default. Check the operator's environment:

```
kubectl -n kong-system get deploy kong-operator-kong-operator-controller-manager \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -i controller
```

It must include `KONG_OPERATOR_ENABLE_CONTROLLER_AIGATEWAYDATAPLANE=true`. If it doesn't, re-run Step 2's `helm upgrade` with `--set env.enable_controller_aigatewaydataplane=true`. The data plane resource you already applied is picked up automatically.

### The operator logs `containers[1].image: Required value`

The data plane's pod template names its container something other than `aigw`, so the operator treats it as a second container with no image. Use `name: aigw`, as in `code/ai-gateway/ai-gateway-dataplane.yaml`. Search the operator's log for the cause of any other data plane failure:

```
kubectl logs -n kong-system deploy/kong-operator-kong-operator-controller-manager | grep -i aigatewaydataplane | tail
```

### The AI Gateway or the data plane doesn't come up in Konnect

Check the operator's log (above). Common causes:
- `PAT` is wrong, expired or not exported when the `KonnectAPIAuthConfiguration` was applied.
- Your Konnect organization isn't in the US region. The guide hard-codes `serverURL: us.api.konghq.com`.
- Your organization doesn't have AI Gateway available.

### `AI_LB` is empty

The NLB is still being provisioned. Wait a few minutes after the data plane is created, then re-run the `export AI_LB=...` command.

### HTTP works but HTTPS doesn't

The data plane manifest reads `CERTIFICATE_ARN` when you apply it. If the variable was empty, the NLB has no certificate on 443. Check with `kubectl get svc kong-aws-ai-dp-ingress -n kong -o yaml | grep ssl-cert`, then re-apply with the variable set.

### curl returns 404

That's the expected result at the end of Step 2. Kong is up, but nothing is declared on the gateway yet.

### curl says "Could not resolve host"

Your machine's resolver hasn't picked up the new `ai-dp` record yet, even if public DNS has (`dig +short ai-dp.$AWS_DOMAIN @8.8.8.8`). Pin the address until it catches up:

```
export KONG_IP=$(dig +short ai-dp.$AWS_DOMAIN @8.8.8.8 | head -1)
curl --resolve ai-dp.$AWS_DOMAIN:443:$KONG_IP https://ai-dp.$AWS_DOMAIN/
```

`scripts/verify.sh` and `scripts/traffic.sh` do this for you.

### curl says "Empty reply from server"

TLS worked, but the NLB had no healthy target behind the address you reached. Right after the data plane is created, health checks are still warming up. Later, with one pod and cross-zone load balancing off, NLB addresses in zones without a pod can keep dropping connections. Wait until the target group reports `healthy`, then re-resolve the name and retry, or run more data plane replicas.

### The load balancer has an extra port 8443

The operator adds Kong's own TLS proxy port to the service. It serves the same routes with Kong's self-signed certificate. It isn't the admin API. Clients use 443.

### kongctl reaches the wrong Konnect organization, or refuses `--pat`

Some company setups wrap kongctl (and decK) to pin each folder to a profile, and refuse token flags (for example `konnect-guard: token flags are not allowed`). Leave out `--pat "$PAT"`, and run kongctl from a folder pinned to a profile for the organization that holds `kong-aws-ai`:

1. If no kongctl profile uses this PAT yet, add one from the root of this repo:
   ```
   cat >> ~/.config/kongctl/config.yaml <<EOF

   kong-aws-ai:
     konnect:
       pat: $PAT
   EOF
   ```
2. Pin this repo to that profile. With konnect-guard, run `konnect-profile set`, choose the profile, and press Enter to save the pin in the repo root. Check that the organization it prints is the one that holds `kong-aws-ai`.
3. Check with `kongctl get ai-gateways`. It should list **Kong AWS AI Gateway**.

## Step 3: A2A and AgentCore

### The local agent fails with `can't open file` or import errors

Run it from the root of this repo with the `uv run` command in [Step 3](../3-a2a-agent-gateway-agentcore.md#the-first-agent): the file is at `code/a2a/server_1.py`, and `uv run --with` installs the A2A SDK for you. A plain `python3 server_1.py` fails with `can't open file` from the repo root, and with import errors when the SDK isn't installed. `server_1.py` needs `a2a-sdk` 1.x (`a2a.helpers`).

### `agentcore create` rejects `--defaults`

Current AgentCore CLI versions use `--template`. Step 3 uses `--template a2a-python-strands`. `agentcore create --help` lists the templates.

### The deployed agent crashes with `No module named 'a2a.helpers'`

The CLI template's `pyproject.toml` pins `a2a-sdk ~= 0.3`. Replace it with the one in [Step 3](../3-a2a-agent-gateway-agentcore.md#agent-configuration), which leaves `a2a-sdk[all]` unpinned, and redeploy. For local runs, also refresh the template's lockfile with `uv lock --upgrade-package a2a-sdk`.

### `agentcore deploy` fails, or the agent doesn't start

Check that `pyproject.toml` lists `uvicorn` and `a2a-sdk[all]`, and that `agentcore.json` has `"protocol": "A2A"` and `"entrypoint": "server_1.py"`, as in [Step 3](../3-a2a-agent-gateway-agentcore.md#agent-configuration). Then tail the runtime logs in CloudWatch with the `aws logs tail` command in Step 3. If the CLI can't find credentials from an `aws login` session, run `eval "$(aws configure export-credentials --format env)"` first.

### awscurl returns an authorization error

The runtime uses SigV4. Make sure `awscurl` has credentials (`aws configure`, or export them from an `aws login` session) with permission to invoke the runtime.

### The gateway call returns `403` or `Missing Authentication Token` from AWS

The call reached AgentCore unsigned, or signed by a role that may not invoke it. Check that:
- the data plane runs as `kaigateway-podid-sa`: `kubectl get deploy kong-aws-ai-dp -n kong -o jsonpath='{.spec.template.spec.serviceAccountName}'`;
- the Pod Identity association for that service account exists, and its role allows `bedrock-agentcore:InvokeAgentRuntime`;
- the agent's `upstream.auth.type` is `aws` with `region: us-west-2`.

The data plane log shows `Creating aws_iam auth handler` when it signs.

### `AGENTCORE_URL` is empty

Re-run the `export AGENTCORE_ARN=...` and `export AGENTCORE_URL=...` commands from the AgentCore project folder, in the same shell you run kongctl from.

## Step 4: MCP tools

### `/mcp` returns 404 "no Route matched with those values"

The MCP server hasn't reached the data plane yet, or `kongctl apply` failed. Check the apply output, then check that **Inventory and Orders Tools** appears under **AI Gateway → MCP Servers** in Konnect.

### The MCP calls are rejected after initialize

MCP servers issue a session ID in the `Mcp-Session-Id` response header, and expect later requests to send it back. Re-run the initialize command and the `export MCP_SESSION_ID=...` command, check that `echo $MCP_SESSION_ID` prints a value, then retry `tools/list`.

### The response starts with `event:` and `data:` instead of plain JSON

That's the `text/event-stream` form of an MCP response, and it's normal. The JSON-RPC message is on the `data:` line.

### `tools/call` says "'sku' was unexpected"

Kong prefixes each tool argument with where it goes in the REST call. Use `query_sku` and `query_status`, as `tools/list` shows.

### `tools/call` returns "HTTP call failed with status 502"

Kong couldn't complete the REST call. The data plane log has the reason next to the request ID (`kubectl logs -n kong deploy/kong-aws-ai-dp --since=5m`). `upstream SSL certificate verify error: (20:unable to get local issuer certificate)` means Kong can't verify the backend's certificate. This happens with the public `https://httpbin.konghq.com`, which is why Step 4 runs an echo backend in the cluster. Check that the `httpbin` deployment in the `kong` namespace is running, and that the MCP server's `config.url` is `http://httpbin.kong.svc.cluster.local:8080/anything`.

## Step 5: Kong Identity

### kongctl says `config.cache_tokens_salt is required`

kongctl requires an explicit `cache_tokens_salt` for the OpenID Connect auth strategy, so later applies don't regenerate it. Export `CACHE_TOKENS_SALT=$(openssl rand -hex 16)` and re-run. Keep the same value for later applies.

### kongctl says `could not unmarshal ... into any supported union types for AIGatewayMCPServerListenerAccess`

The MCP server's `access` block has the agent's shape. An MCP server needs `acl_attribute_type: consumer`, and it references the strategy by name (`!ref kong-identity-oidc#name`), as in `code/ai-gateway/step5-auth.yaml`.

### `/a2a` or `/mcp` still answers without a token

The apply didn't happen. kongctl validates the whole file first, and if any entity is invalid it applies nothing. Re-run `kongctl diff` and fix the error it reports.

### Introspection says "active": false

The token has expired. Step 5's client issues tokens that last 15 minutes. Get a new token and introspect it straight away.

### A call returns 401 even with a token

Get a fresh token and call straight away. If it still fails, introspect that same token by hand as shown in Step 5. If Kong Identity reports `"active": true` but Kong still rejects it, check that `ISSUER_URL`, `INTROSPECTION_URL`, `CLIENT_ID` and `CLIENT_SECRET` were set when you ran `kongctl apply`, then re-run it.

### The wrong auth server is used

The Step 5 commands take each ID from its create response. If you created several authorization servers, list them with `curl -s https://us.api.konghq.com/v1/auth-servers -H "Authorization: Bearer $PAT" | jq '.data[] | {id, name, issuer}'` and export the right `ISSUER_URL`.

## Step 6: LLM Gateway to Bedrock

### The model call returns `AccessDenied` from Bedrock

Either your account doesn't have access to Nova Micro in `us-west-2` (run Step 6's `converse` check with your own credentials), or the data plane's role doesn't allow `bedrock:InvokeModel` (run Step 6's `simulate-principal-policy` check).

### The model call returns an error about the model

The request body's `"model"` must be `nova-micro`, the name declared on the gateway, not the Bedrock model ID (`us.amazon.nova-micro-v1:0`).

### kongctl complains about the auth strategy in `step6-bedrock.yaml`

Step 6's file re-declares the Step 5 auth strategy, so the model can reference it. Export the same Step 5 variables first, including the same `CACHE_TOKENS_SALT`.

### The AI Gateway's Overview tiles stay at 0

Analytics take a few minutes to appear, and the Overview's Usage tiles count model calls only. Send some traffic to `/v1` (for example with `scripts/traffic.sh`), wait a few minutes and refresh. If only **Estimated cost** stays at `$0.00`, that's rounding. **Observability → Overview** shows the exact cost.
