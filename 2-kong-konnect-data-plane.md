# Step 2: Run Kong AI Gateway on EKS, managed from Konnect

[← Step 1](1-eks-cluster.md) · **Step 2** · [Step 3 →](3-a2a-agent-gateway-agentcore.md)

## Why this step

Kong works in two halves:

- The **control plane** is where you define what the gateway does. Here it's a **Konnect AI Gateway**, part of Kong Konnect, a SaaS service that Kong runs.
- The **data plane** is the proxy that actually handles traffic. Here it runs **in your EKS cluster**.

The data plane pulls configuration from Konnect over an outbound, mutually authenticated connection. Your prompts, model responses, tool calls and agent messages go through the data plane in your VPC and **do not pass through Konnect**. Konnect receives configuration requests from you and telemetry from the data plane.

Konnect's **AI Gateway** is built for AI traffic. Instead of services, routes and plugins, you declare AI entities, and Konnect turns them into gateway configuration:

| AI Gateway entity | Step | Used here for |
|---|---|---|
| **Agent** | 3 | the AgentCore agent at `/a2a` |
| **MCP Server** | 4 | two tools at `/mcp`, built from a REST API |
| **Auth Strategy** | 5 | Kong Identity token checks on every route |
| **Model** and **Model Provider** | 6 | Amazon Nova Micro on Bedrock, at `/v1` |

This step is also where AWS IAM enters the picture. Kong doesn't get AWS access keys. Instead, an **EKS Pod Identity** association gives the data plane an IAM role whose policy lists exactly which Bedrock, AgentCore and Secrets Manager actions it may call. Kong uses that role to sign its calls to AgentCore (Step 3) and Bedrock (Step 6). You can audit and revoke that access with the same IAM tools you use for everything else.

## What it does, in plain English

1. Creates an IAM policy (`bedrock-policy`) and binds it to a Kubernetes service account (`kaigateway-podid-sa`) through Pod Identity.
2. Installs the **Kong Operator**, a Kubernetes controller that creates Konnect objects and Kong deployments from YAML, with its AI Gateway data plane controller turned on.
3. Uses the operator to create an **AI Gateway** named `kong-aws-ai` in Konnect, and its **data plane** `kong-aws-ai-dp` in EKS, running as that service account.
4. Puts an internet-facing **NLB** in front of the data plane, with your ACM certificate from Step 1 on port 443.
5. Points `ai-dp.<your domain>` at the NLB using a Route 53 alias record, then tests it.
6. Sets up **kongctl**, the CLI that declares the AI entities in Steps 3 to 6.

## Before you start

- Step 1 is complete and `CERTIFICATE_ARN`, `AWS_DOMAIN` and `HOSTED_ZONE_ID` are still exported in your shell.
- You have a Kong Konnect account with **AI Gateway** available (it appears as **AI** in the Konnect sidebar). If you don't have an account, start a [free 30-day trial of Kong Konnect on the AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-77nhc3l2cn5im).
- [kongctl](https://developer.konghq.com/kongctl/) **1.28.4 or newer**. On macOS: `brew install kong/kongctl/kongctl`.
- Replace `<YOUR_AWS_ACCOUNT>` with your AWS account ID.

> **Tested versions.** This step was run with Kong Operator `2.4.0` (Helm chart `1.5.0`), the `kong/kong-ai-gateway:2.3.1` data plane image (Kong 3.15 underneath), kongctl `1.28.4` and EKS `1.35`.

> **Heads-up about the IAM policy below.** It allows `bedrock:ApplyGuardrail`, `bedrock:InvokeModel`, `secretsmanager:GetSecretValue` and related actions on `"Resource": "*"`. That is broader than you'd use in production. Scope it down to specific resource ARNs before using this in production.
>
> **Shared AWS account?** If `bedrock-policy` or `kaigateway-aws-podid-role` already exists, use suffixed names (for example `bedrock-policy-kong314`) and use them consistently, as in Step 1.

---

## Pod Identity

The data plane calls AWS services (AgentCore, Bedrock, and in the reference architecture Secrets Manager) using [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html). Create the policy it will use:

```
aws iam create-policy \
 --policy-name bedrock-policy \
 --policy-document '{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Action": [
				"bedrock:InvokeModel",
				"bedrock:InvokeModelWithResponseStream",
				"bedrock:ApplyGuardrail",
				"bedrock:CallWithBearerToken",
				"bedrock-agentcore:InvokeAgentRuntime",
				"bedrock-agentcore:GetAgentCard",
				"secretsmanager:ListSecrets",
				"secretsmanager:GetSecretValue"
			],
			"Resource": "*"
		}
	]
}'
```

The **Pod Identity association** links a Kubernetes service account to an IAM role with that policy. The data plane will run as the service account `kaigateway-podid-sa`:

```
kubectl create namespace kong
kubectl create sa kaigateway-podid-sa -n kong
```

```
eksctl create podidentityassociation \
  --cluster kong314 \
  --region us-west-2 \
  --namespace kong \
  --service-account-name kaigateway-podid-sa \
  --role-name kaigateway-aws-podid-role \
  --permission-policy-arns arn:aws:iam::<YOUR_AWS_ACCOUNT>:policy/bedrock-policy
```

## Kong Operator

Install the [Kong Operator](https://developer.konghq.com/operator/). The AI Gateway resources need Operator 2.3 or newer, and its **AI Gateway data plane controller is off by default**, so turn it on:

```
helm repo add kong https://charts.konghq.com
helm repo update kong
```

```
helm upgrade --install kong-operator kong/kong-operator \
  -n kong-system \
  --create-namespace \
  --version 1.5.0 \
  --set image.tag=2.4.0 \
  --set kubernetes-configuration-crds.enabled=true \
  --set env.ENABLE_CONTROLLER_KONNECT=true \
  --set env.enable_controller_aigatewaydataplane=true
kubectl -n kong-system rollout status deployment kong-operator-kong-operator-controller-manager --timeout=180s
kubectl get crd | grep -i aigateway
```

The last command lists the AI Gateway resource types, such as `konnectaigateways.konnect.konghq.com` and `aigatewaydataplanes.aigateway.konghq.com`.

## Konnect Personal Access Token (PAT)

The operator and kongctl authenticate to Konnect with a Personal Access Token (PAT) or a System Access Token (SAT). To generate a PAT, go to the Konnect UI, click your initials in the upper right corner, then select **Personal Access Tokens**. Click **+ Generate Token**, name it, set its expiration, and copy it. Konnect won't display it again.

```
export PAT=<YOUR_PAT>
```

## AI Gateway control plane

The first resource tells the operator which Konnect region to use and which token to authenticate with:

```
cat <<EOF | kubectl apply -f -
kind: KonnectAPIAuthConfiguration
apiVersion: konnect.konghq.com/v1alpha1
metadata:
  name: konnect-api-auth-conf
  namespace: kong
spec:
  type: token
  token: $PAT
  serverURL: us.api.konghq.com
EOF
```

The second creates the AI Gateway in Konnect, from [`code/ai-gateway/konnect-ai-gateway.yaml`](code/ai-gateway/konnect-ai-gateway.yaml):

```
kubectl apply -f code/ai-gateway/konnect-ai-gateway.yaml
kubectl wait konnectaigateway/kong-aws-ai -n kong --for=condition=Programmed=True --timeout=5m
```

`kong-aws-ai` now appears in Konnect under **AI Gateway → Gateways** as **Kong AWS AI Gateway**.

## AI Gateway data plane

[`code/ai-gateway/ai-gateway-dataplane.yaml`](code/ai-gateway/ai-gateway-dataplane.yaml) runs the data plane as `kaigateway-podid-sa`, so Pod Identity gives it the IAM role above, behind an internet-facing NLB with your ACM certificate. It fills in `CERTIFICATE_ARN` as it applies:

```
sed "s|\${CERTIFICATE_ARN}|$CERTIFICATE_ARN|" code/ai-gateway/ai-gateway-dataplane.yaml | kubectl apply -f -
kubectl wait aigatewaydataplane/kong-aws-ai-dp -n kong --for=condition=Ready=True --timeout=10m
kubectl get pods,svc -n kong
```

You should see a `kong-aws-ai-dp-...` pod `Running` and a `kong-aws-ai-dp-ingress` service of type `LoadBalancer`. The data plane also appears under **Data plane nodes** in Konnect.

Two things to know about this manifest:
- **The container must be named `aigw`.** The pod template's `containers` list is required, even when you only set the service account, and the operator's container is called `aigw`. Any other name adds a second container with no image, and the operator logs `containers[1].image: Required value`.
- **The NLB also gets port 8443.** The operator adds Kong's own TLS proxy port to the service. It serves the same routes with Kong's self-signed certificate. It is not the admin API, which stays inside the pod. Clients use 443, where the NLB presents your ACM certificate.

Check that the pod runs as the Pod Identity service account:

```
kubectl get deploy kong-aws-ai-dp -n kong -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'
```

It should print `kaigateway-podid-sa`.

## Route 53

Point `ai-dp.<your domain>` at the new NLB:

```
export AI_LB=$(kubectl get svc kong-aws-ai-dp-ingress -n kong -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export AI_LB_ZONE=$(aws elbv2 describe-load-balancers --region us-west-2 \
  --query "LoadBalancers[?DNSName=='$AI_LB'].CanonicalHostedZoneId" --output text)
echo $AI_LB $AI_LB_ZONE
```

If `AI_LB` is empty, the NLB is still being created. Wait a minute and re-run the exports.

```
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

## Test the load balancer

```
curl -i https://ai-dp.$AWS_DOMAIN/
```

```
HTTP/1.1 404 Not Found
Content-Type: application/json; charset=utf-8
Content-Length: 103
...
```

A new DNS name and a new NLB both take a few minutes to settle:
- **`Could not resolve host`.** Your machine's resolver hasn't picked up the new name yet, even if public DNS has. Check with `dig +short ai-dp.$AWS_DOMAIN @8.8.8.8`. Until your resolver catches up, pin the address for curl:
  ```
  export KONG_IP=$(dig +short ai-dp.$AWS_DOMAIN @8.8.8.8 | head -1)
  curl -i --resolve ai-dp.$AWS_DOMAIN:443:$KONG_IP https://ai-dp.$AWS_DOMAIN/
  ```
  Add the same `--resolve` option to the `curl` commands in later steps. The repo's scripts do this for you.
- **`Empty reply from server`.** The NLB accepted the connection but has no healthy target in that zone yet. Wait for the target group to report `healthy` (EC2 console, **Target groups**), then resolve the name again and retry. With one data plane pod and cross-zone load balancing off, NLB addresses in zones without a pod can keep dropping connections, so re-resolve until you get a working address, or run more replicas.

## kongctl

Steps 3 to 6 declare the AI entities with kongctl, from YAML files in [`code/ai-gateway/`](code/ai-gateway/). Check that it reaches your AI Gateway:

```
kongctl version
kongctl get ai-gateways --pat "$PAT"
```

It should list **Kong AWS AI Gateway**. The `kongctl` commands in later steps pass `--pat "$PAT"`. If you've logged kongctl in with a profile instead (`kongctl login`), you can leave that flag out.

---

## Verify

`curl -i https://ai-dp.$AWS_DOMAIN/` returns **`HTTP/1.1 404 Not Found`**, and `kongctl get ai-gateways` lists **Kong AWS AI Gateway**.

That 404 is the success signal. It proves DNS → NLB → TLS with your ACM certificate → the AI Gateway data plane on EKS all work, and that Kong answered. Kong returns 404 only because nothing is declared on the gateway yet. That starts in Step 3.

## Common problems

- **`kubectl wait aigatewaydataplane ...` times out, with no pod and no status on the resource.** The operator's AI Gateway data plane controller is off. Re-run the `helm upgrade` above with `env.enable_controller_aigatewaydataplane=true`, and check that the operator's environment shows `KONG_OPERATOR_ENABLE_CONTROLLER_AIGATEWAYDATAPLANE=true`.
- **The operator logs `containers[1].image: Required value`.** The pod template's container isn't named `aigw`.
- **`apply` says `spec.deployment.podTemplateSpec.spec.containers: Required value`.** The pod template needs a `containers` list.
- **The AI Gateway never becomes `Programmed`, or the data plane never appears in Konnect.** Check the operator's log: `kubectl logs -n kong-system deploy/kong-operator-kong-operator-controller-manager --tail=50`. A wrong or expired `PAT`, a Konnect region other than `us`, or an organization without AI Gateway are common causes.
- **`AI_LB` is empty.** The NLB takes a few minutes to provision. Wait and re-run the export.
- **HTTPS fails but HTTP works.** `CERTIFICATE_ARN` was probably not set when you applied the data plane, so the NLB has no certificate. Check with `kubectl get svc kong-aws-ai-dp-ingress -n kong -o yaml | grep ssl-cert`.
- **`Could not resolve host` or `Empty reply from server`.** DNS or the NLB targets are still settling. See [Test the load balancer](#test-the-load-balancer).
- **More:** see [docs/troubleshooting.md](docs/troubleshooting.md#step-2-kong-ai-gateway-on-eks).

## Tearing this step down

Sections 1 and 2 of [docs/teardown.md](docs/teardown.md) remove the AI Gateway, its data plane and NLB, and the operator. The rest of that page removes everything else the guide creates.

[← Step 1](1-eks-cluster.md) · **Step 2** · [Step 3 →](3-a2a-agent-gateway-agentcore.md)
