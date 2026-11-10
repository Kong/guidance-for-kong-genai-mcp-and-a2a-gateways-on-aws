# Troubleshooting

This page lists common problems by step.

Back to the [README](../README.md).

## Before you start: two things that catch everyone

- **Run everything in one shell session.** Later steps rely on variables exported earlier (`AWS_DOMAIN`, `CERTIFICATE_ARN`, `HOSTED_ZONE_ID`, `PAT`, `AGENTCORE_URL`). If you open a new terminal, re-run the `export` commands.
- **Each decK sync replaces the whole configuration.** Steps 3, 4 and 5 each run `deck gateway reset ... -f` before `deck gateway sync`, which deletes everything that was on the `kong-aws` control plane. Running a later step removes an earlier step's routes.

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

### `deck gateway sync` can't find kong_aws_mock.yaml

`kong_aws_mock.yaml` and the `openapi.yml` it's built from aren't in this repo yet, so this step can't be completed from this repo alone.

## Step 5: Kong Identity

### `deck gateway sync` can't find kong_docusign_openid_mock.yaml

This file isn't in this repo yet. The Kong Identity API calls and the token and introspection exercises still work without it.

### The wrong auth server or scope is picked up

The `export AUTHZ_SERVER_ID=...` and `export SCOPE_ID=...` commands take the first item in the list (`.data[0]`). If your organization already has other auth servers or scopes, check the IDs against the responses of the create calls.

### Introspection says "active": false

The token has expired. The client is created with a 60-second access token lifetime. Get a new token and introspect it straight away.
