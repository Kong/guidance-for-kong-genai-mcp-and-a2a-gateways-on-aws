# Kong AI Gateway on AWS: LLM, MCP and Agent (A2A) Gateways with Amazon EKS and Bedrock AgentCore

You're probably already building GenAI on AWS with Bedrock models, AgentCore-hosted agents and IAM. As more teams and agents come online, every model call, tool call and agent-to-agent call needs the same things: authentication, limits, logging and one place to change policy. This guide deploys **Kong AI Gateway** inside your AWS account, on Amazon EKS behind a Network Load Balancer with an ACM certificate, as that shared front door. Kong's data plane sits in your VPC and uses an IAM role to call AWS services. Kong Konnect manages its configuration. The result adds a consistent policy and visibility layer on top of the AWS services you already use, and doesn't replace any of them.

## Contents

1. [Why Kong, if I already have AWS?](#why-kong-if-i-already-have-aws)
2. [Architecture](#architecture)
3. [What you'll build](#what-youll-build)
4. [Who this is for](#who-this-is-for)
5. [Prerequisites](#prerequisites)
6. [Steps](#steps)
   - [Step 1: Build the AWS foundation](#step-1-build-the-aws-foundation)
   - [Step 2: Run Kong's data plane on EKS, managed from Konnect](#step-2-run-kongs-data-plane-on-eks-managed-from-konnect)
   - [Step 3: Put an AgentCore agent behind Kong's Agent (A2A) Gateway](#step-3-put-an-agentcore-agent-behind-kongs-agent-a2a-gateway)
   - [Step 4: The MCP Gateway pattern, and a mocked API to build it on](#step-4-the-mcp-gateway-pattern-and-a-mocked-api-to-build-it-on)
   - [Step 5: Kong Identity as the OAuth2 provider](#step-5-kong-identity-as-the-oauth2-provider)
7. [Clean up](#clean-up)
8. [Repo layout](#repo-layout)
9. [Next steps and further reading](#next-steps-and-further-reading)

## Why Kong, if I already have AWS?

It's a fair question. AWS already gives you models (Bedrock), safety filters (Guardrails), an agent runtime and tool gateway (AgentCore), identity (IAM, Cognito), API management (API Gateway), edge protection (WAF), logs and metrics (CloudWatch) and secrets (Secrets Manager). Kong doesn't replace any of these.

Kong becomes useful once you have **more than one kind of AI traffic, more than one team, or more than one provider**. Then you want one place to apply the same identity, limits and logging to LLM calls, MCP tool calls and agent-to-agent calls, whether they go to Bedrock or somewhere else. Kong runs inside your VPC as that layer and calls AWS services with an IAM role you control.

| AWS service you already use | What Kong adds on top |
|---|---|
| **Amazon Bedrock** | One OpenAI-compatible or provider-native endpoint across Bedrock and non-AWS providers. Per-team routing, fallback and load balancing between models. |
| **Bedrock Guardrails** | Applies your existing guardrail at the gateway with Kong's AI AWS Guardrails plugin, so the same guardrail covers traffic to non-Bedrock models too. |
| **Bedrock AgentCore** | A single A2A front door for agents on AgentCore *and* outside it. Callers use plain HTTPS while Kong signs requests to AgentCore with IAM (Step 3). |
| **IAM / Pod Identity** | Kong gets AWS access only through an IAM role you scope and audit. Consumer-level identity (API keys, OAuth2, OIDC) applies on top for the humans and agents calling Kong. |
| **API Gateway / WAF** | AI-aware policies on top of request-based throttling: limits counted in **tokens or dollars** per consumer or group, and prompt-level guards. |
| **CloudWatch** | AI-specific metrics (tokens, cost, model, latency per consumer) for LLM, MCP and A2A traffic, plus OpenTelemetry export. |
| **MemoryDB / ElastiCache** | Used as Kong's Redis backend for semantic caching, semantic routing and shared rate-limit counters. |

The full, even-handed comparison, including when you **don't** need Kong, is in [docs/why-kong-on-aws.md](docs/why-kong-on-aws.md).

![Side-by-side diagram: an AWS-only GenAI stack where each app integrates separately with Bedrock, AgentCore and tools, versus the same AWS services with a Kong data plane on EKS in front](images/architecture/10-aws-only-vs-aws-plus-kong.svg)
*Left: each app wires itself to each AWS service. Right: the same AWS services, with Kong in front applying shared policy.*

## Architecture

![Reference architecture: agents reach an AWS NLB with an ACM certificate; Route 53 provides DNS; the NLB forwards to the Kong AI Gateway data plane running in EKS pods inside the cluster VPC; Kong calls Amazon Bedrock, SageMaker AI, external model providers, MemoryDB for Redis, Bedrock AgentCore agents and MCP servers, external services, and an agent in an E2B sandbox; AWS Secrets Manager supplies secrets; the Konnect control plane manages the data plane](images/architecture/01-reference-architecture.png)
*The reference architecture.*

Kong is split into two halves. The **control plane** (Kong Konnect, run by Kong) is where routes and policies are defined. The **data plane** (Kong Gateway pods on your EKS cluster) is where traffic actually flows. The data plane connects out to Konnect to fetch configuration and send telemetry. Your prompts, responses and agent messages stay on the data plane in your VPC.

### Follow one request through the system

This is the path an A2A call takes once you've finished Step 3. LLM and MCP calls follow the same path and differ only in the plugin and the upstream service.

![Life of a request: client, Route 53, NLB with ACM TLS, Kong data plane on EKS running route matching and plugins, Pod Identity IAM role, AgentCore or Bedrock, response back, with Konnect receiving telemetry and CloudWatch receiving AgentCore logs](images/architecture/11-life-of-a-request.svg)
*One request, end to end.*

1. **The client resolves the name.** An app or agent calls `https://kong-dp.<your domain>/a2a`. Route 53 answers with the NLB's address (alias record from Step 2).
2. **The NLB terminates TLS.** The Network Load Balancer presents your ACM wildcard certificate on port 443 (Step 1) and forwards plain HTTP to the Kong pods on port 8000.
3. **Kong matches a route and runs plugins.** The data plane on EKS matches `/a2a` to the `a2a-route` and runs its plugins. Here that's the AI A2A Proxy. Authentication plugins (key auth, OpenID Connect against Kong Identity in Step 5), AI rate limiting and Guardrails plugins would run at this point too.
4. **Kong authenticates to AWS with IAM.** Kong's pod uses the IAM role attached through EKS Pod Identity (Step 2). No static AWS keys are involved. The policy allows `bedrock-agentcore:InvokeAgentRuntime`, `bedrock:InvokeModel`, `bedrock:ApplyGuardrail` and `secretsmanager:GetSecretValue`, among others.
5. **The AWS service does the work.** AgentCore runs the agent (Step 3). For LLM traffic it would be Bedrock, optionally with Bedrock Guardrails checking the prompt and response.
6. **The response comes back the same way,** through Kong and the NLB to the client.
7. **Everyone gets the logs they need.** Kong sends analytics to Konnect, and can also export OpenTelemetry. AgentCore writes its own logs to CloudWatch (you'll tail them in Step 3). The reference architecture also streams Kong metrics to CloudWatch, but this guide doesn't configure that yet.

Deeper dives on each flow:
- [Kong AI Gateway and Amazon Bedrock AgentCore](docs/concepts/kong-ai-gateway-and-agentcore.md): how AgentCore and Kong split responsibilities.
- [The LLM/GenAI flow](docs/concepts/llm-gateway-flow.md): agent → Kong LLM Gateway → Bedrock, OpenAI, Anthropic.
- [All flows together](docs/concepts/all-flows.md): LLM, MCP and A2A traffic through one data plane.
- [Solution overview](docs/solution-overview.md): summary, features, use cases and architecture steps.

## What you'll build

When you finish Steps 1–3 you'll have:

- An **EKS cluster** with the AWS Load Balancer Controller and EKS Pod Identity.
- A **public HTTPS endpoint**, `kong-dp.<your domain>`, served by an NLB with an **ACM** certificate and a **Route 53** alias.
- A **Kong data plane** on EKS, connected to a **Konnect control plane** named `kong-aws`, with AWS access through an **IAM role** rather than keys.
- An **A2A agent running on Bedrock AgentCore**, reachable through Kong at `/a2a` by any A2A client without AWS credentials.

Steps 4 and 5 add a mocked API route and a **Kong Identity** OAuth2 authorization server with the client credentials flow. Both depend on decK files that aren't in this repo yet, so read the notes in those steps first.

> **What this guide does *not* configure yet.** The architecture includes the LLM Gateway to Bedrock, Bedrock Guardrails, MemoryDB for semantic caching, Secrets Manager for credentials and CloudWatch for Kong metrics. The IAM policy in Step 2 already grants the Bedrock, Guardrails and Secrets Manager permissions. This guide has **no deployment steps** for these pieces yet.

- Run [Clean up](#clean-up) when you're done.

## Who this is for

You don't need deep Kubernetes knowledge. Every Kubernetes command is copy-paste, and the step docs explain what each one does. You do need to be comfortable running AWS CLI commands in a terminal.

| You are… | Read this first | Then |
|---|---|---|
| **Cloud architect** | [Why Kong on AWS](docs/why-kong-on-aws.md), [Architecture](#architecture) | [docs/concepts/](docs/concepts/) for the LLM, MCP and A2A flows |
| **Security lead** | Step 2's IAM policy and Pod Identity section, [Step 5](5-kong-identity-oauth2.md) (OAuth2 tokens and introspection) | The "who owns what" diagram in [docs/why-kong-on-aws.md](docs/why-kong-on-aws.md#who-owns-what) |
| **FinOps / IT lead** | [What you'll build](#what-youll-build) (cost estimate), [Why Kong on AWS](docs/why-kong-on-aws.md#where-the-gaps-show-up-in-practice) (token and cost budgets) | [Clean up](#clean-up) |
| **Platform engineer** | [Prerequisites](#prerequisites), then Steps 1–5 in order | [docs/troubleshooting.md](docs/troubleshooting.md) |

Terms like MCP, A2A, data plane and AgentCore are defined in the [glossary](docs/glossary.md).

## Prerequisites

### Accounts

- **AWS account** with permission to create EKS clusters, IAM policies and roles, Route 53 domains and records, ACM certificates and Bedrock AgentCore runtimes, all in `us-west-2` (Route 53 Domains uses `us-east-1`).
- **Kong Konnect account.** If you don't have one, start a [free 30-day trial of Kong Konnect on the AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-77nhc3l2cn5im). You'll create a **Personal Access Token** in Step 2. The guide uses the Konnect **US** region (`us.api.konghq.com`).
- **Bedrock AgentCore** available in `us-west-2` for your account (Step 3).

### Tools

These are the command-line tools the steps use. Install each one from its own install page (linked below). Running each tool's version command is a quick way to confirm it's on your `PATH`.

| Tool | What it's for in this guide | Used in |
|---|---|---|
| [Kong decK](https://developer.konghq.com/deck/) | Pushes declarative Kong configuration (routes, plugins) to Konnect | Steps 3–5 |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) | Creates IAM policies, Route 53 records, ACM certificates; inspects the NLB and AgentCore | Steps 1–3 |
| [eksctl](https://github.com/eksctl-io/eksctl) | Creates the EKS cluster, add-ons and Pod Identity associations | Steps 1–2 |
| [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) | Applies the Kong Operator resources and checks pods | Step 2 |
| [helm](https://helm.sh/docs/intro/install/) | Installs the AWS Load Balancer Controller and the Kong Operator | Steps 1–2 |
| [k9s](https://k9scli.io/) | Optional terminal UI for watching pods | Any |
| [curl](https://curl.se/) | Calls Konnect APIs and tests the gateway | All |
| [jq](https://jqlang.org/) | Extracts values (ARNs, IDs, URLs) from JSON output | All |
| [jwt-cli](https://github.com/mike-engel/jwt-cli) | Decodes access tokens | Step 5 |
| [wget](https://www.gnu.org/software/wget/) | General-purpose downloads | — |
| Python + [uv](https://docs.astral.sh/uv/) + A2A SDK | Runs the sample agents | Step 3 ([setup](code/a2a/python-a2a-sdk-install.md)) |
| npm + [AgentCore CLI](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-get-started-cli.html) | Creates and deploys the AgentCore agent | Step 3 |
| [awscurl](https://pypi.org/project/awscurl/) | Sends SigV4-signed requests straight to AgentCore | Step 3 |

## Steps

Each step below gives the **why**, a plain-English summary and a **Verify** check. To run a step, open its **full doc**: it has every command in order, with expected output, optional checks and background.

Run everything in **one terminal session**. Later steps reuse variables exported earlier (`AWS_DOMAIN`, `CERTIFICATE_ARN`, `HOSTED_ZONE_ID`, `PAT`, `AGENTCORE_URL`).

> **Placeholders.** Replace `<YOUR_AWS_ACCOUNT_ID>`, `<YOUR_AWS_ACCOUNT>`, `<YOUR_PAT>`, `<YOUR_CLIENT_ID>`, `<YOUR_CLIENT_SECRET>` and the Route 53 contact fields with your own values. The commands also hard-code the names `kong314`, `us-west-2` and `kong-aws-ai-guidance.com`. Keep them, or change them consistently everywhere.

### Step 1: Build the AWS foundation

**Full doc:** [1-eks-cluster.md](1-eks-cluster.md)

**Why this step.** Kong will run inside your own AWS account, on EKS, so AI traffic stays on infrastructure you control and IAM governs it. Before any Kong component exists, you need a cluster, a way to get a load balancer and a trusted HTTPS name.

**What it does.** Creates an EKS cluster with the Pod Identity add-on, installs the AWS Load Balancer Controller (so Kubernetes can create an NLB), registers a domain in Route 53 and issues a wildcard ACM certificate validated through DNS.

**Verify.** The certificate status check at the end of the full doc prints `ISSUED`.

**Common problems.** The certificate stays `PENDING_VALIDATION` (domain registration not finished, or CNAME in the wrong zone). `helm install` can't find the `eks` chart repository. See [Step 1 troubleshooting](docs/troubleshooting.md#step-1-eks-and-networking).

### Step 2: Run Kong's data plane on EKS, managed from Konnect

**Full doc:** [2-kong-konnect-data-plane.md](2-kong-konnect-data-plane.md)

**Why this step.** This is where Kong and AWS meet. The Kong data plane runs as pods in your cluster and gets AWS permissions only through an IAM role bound with EKS Pod Identity. Konnect is where you'll define routes and policies. It manages the data plane but never sits in the request path.

**What it does.** Creates the `bedrock-policy` IAM policy and binds it to Kong's service account, installs the Kong Operator, uses it to create the `kong-aws` control plane in Konnect and the `kong-aws-dp` data plane in EKS behind an internet-facing NLB with your ACM certificate, then points `kong-dp.<your domain>` at the NLB.

**Verify.** A request to `https://kong-dp.<your domain>` returns a `404 Not Found` with `"no Route matched with those values"` and a `Server: kong/...` header is **success**. DNS, the NLB, TLS and the Kong pod all work. There are no routes yet.

**Common problems.** The data plane never becomes Ready (check the operator and data plane logs; the full doc has the commands). `DATA_PLANE_LB` is empty because the NLB is still provisioning. HTTPS fails because `CERTIFICATE_ARN` wasn't set. See [Step 2 troubleshooting](docs/troubleshooting.md#step-2-kong-konnect-data-plane).

### Step 3: Put an AgentCore agent behind Kong's Agent (A2A) Gateway

**Full doc:** [3-a2a-agent-gateway-agentcore.md](3-a2a-agent-gateway-agentcore.md)

**Why this step.** AgentCore runs your agents and requires IAM-signed (SigV4) calls. Kong gives other agents (inside AWS or not) one plain HTTPS A2A endpoint with consistent policy and logging. Kong signs the call to AgentCore with its own IAM role, so callers never hold AWS credentials.

**What it does.** Runs a hello-world A2A agent locally, deploys it to AgentCore, then publishes it through Kong at `/a2a` using the AI A2A Proxy plugin.

> **Before you run it:** the Kong test request uses the sample host `kong-dp.kong-demo.com`. Use your own `kong-dp.<your domain>`. Also, `deck gateway reset ... -f` deletes any existing Kong configuration on `kong-aws` before syncing.

**Verify.** A plain, unsigned request to `https://kong-dp.<your domain>/a2a` returns an artifact whose text is `that's the response`.

**Common problems.** `awscurl` returns 403 (run `aws configure`). Kong returns 401/403 from AgentCore (check the Pod Identity role). Kong returns 404 because a later step's `deck gateway reset` removed the route. See [Step 3 troubleshooting](docs/troubleshooting.md#step-3-a2a-and-agentcore).

### Step 4: The MCP Gateway pattern, and a mocked API to build it on

**Full doc:** [4-mcp-gateway.md](4-mcp-gateway.md)

**Why this step.** Agents call tools over MCP. Routing those calls through Kong gives tool access the same authentication, limits and telemetry as model and agent traffic, instead of every agent holding credentials for every tool.

**What it does.** The full doc walks through the MCP flow, including Kong's AI MCP Proxy plugin. The hands-on part publishes a **mocked REST API** with Kong's Mocking plugin. It doesn't configure MCP proxying itself.

> **Can't complete from this repo alone:** the decK file `kong_aws_mock.yaml` (and the `openapi.yml` it's built from) isn't in this repo yet. This also resets Step 3's configuration.

**Verify.** A request to `/api/dataio/getTypeNames` returns a `typeNames` list containing `CRM Contact` and `Sales Opportunity`.

**Common problems.** See [Step 4 troubleshooting](docs/troubleshooting.md#step-4-mcp-gateway).

### Step 5: Kong Identity as the OAuth2 provider

**Full doc:** [5-kong-identity-oauth2.md](5-kong-identity-oauth2.md)

**Why this step.** Machine-to-machine traffic (agents calling agents and tools) needs short-lived, scoped tokens that the gateway can check, not shared static keys. Kong Identity is an OAuth2 authorization server built into Konnect. Amazon Cognito is the AWS-native alternative.

**What it does.** Creates an authorization server, scope, custom claim and client-credentials client in Kong Identity. Then it adds the OpenID Connect plugin (introspection mode) to a route and walks through getting, decoding and introspecting a token by hand.

> **Note:** this step's text still describes a DocuSign extension-app scenario, and its decK file `kong_docusign_openid_mock.yaml` isn't in this repo yet. The Kong Identity API calls and the token exercises below work without it. This step's `deck gateway reset` also removes earlier steps' configuration.

**Verify.** Introspecting the token, as the gateway would, shows that a fresh token returns `"active": true`. After the 60-second lifetime it returns `"active": false`.

**Common problems.** `.data[0]` picks the wrong auth server or scope if your org has others. The token expires before you introspect it. See [Step 5 troubleshooting](docs/troubleshooting.md#step-5-kong-identity).

## Clean up

Stop billing by removing what you created, **roughly in reverse order**.

- **AgentCore agent** (Step 3): use the teardown in [Step 3](3-a2a-agent-gateway-agentcore.md#tearing-this-step-down).
- **Kong control plane and data plane** (Step 2): use the teardown in [Step 2](2-kong-konnect-data-plane.md#tearing-this-step-down). This also deletes the NLB that Kubernetes created for the data plane.

**Remove these yourself, from the console or the CLI:**
- **Kong Identity** (Step 5): the `AuthZ_Server_1` authorization server, in Konnect.
- **Route 53 records** (Steps 1–2): the `kong-dp.<your domain>` alias and the ACM validation CNAME.
- **ACM certificate** (Step 1): the `*.<your domain>` certificate in `us-west-2`, once nothing uses it.
- **AWS Load Balancer Controller** (Step 1): the Helm release in `kube-system`.
- **Kong Operator** (Step 2): the Helm release in `kong-system`.
- **EKS cluster** `kong314` (Step 1): this stops the largest ongoing charges (control plane and the `c5.xlarge` node). Deleting the cluster with eksctl also removes its node group.
- **IAM policies and roles**: `AWSLoadBalancerControllerIAMPolicy`, `bedrock-policy`, `AWSLoadBalancerControllerIAMRole-kong314` and `kaigateway-aws-podid-role`.
- **Route 53 hosted zone and domain** (Step 1): a hosted zone costs a monthly fee while it exists. The domain registration was set to `--auto-renew`. Turn auto-renew off if you don't want to keep the domain.

Check the Billing console a day later to confirm nothing is still running.

## Repo layout

```
├── README.md                              # this walkthrough
├── 1-eks-cluster.md                       # Step 1: EKS, Load Balancer Controller, Route 53, ACM
├── 2-kong-konnect-data-plane.md           # Step 2: IAM + Pod Identity, Kong Operator, Konnect CP and EKS DP, NLB, DNS
├── 3-a2a-agent-gateway-agentcore.md       # Step 3: A2A agent locally → AgentCore → behind Kong's AI A2A Proxy
├── 4-mcp-gateway.md                       # Step 4: MCP flow explained; mocked API route
├── 5-kong-identity-oauth2.md              # Step 5: Kong Identity OAuth2 server, client credentials, introspection
├── code/a2a/                              # Step 3 sample agents and Python setup (server_1.py, client_1.py)
├── docs/
│   ├── why-kong-on-aws.md                 # the AWS-first case for (and against) adding Kong
│   ├── glossary.md                        # every acronym and product term used here
│   ├── troubleshooting.md                 # per-step problems and fixes
│   ├── known-issues.md                    # open issues to resolve before production use
│   ├── solution-overview.md               # solution summary, features, use cases
│   └── concepts/                          # architecture write-ups: AgentCore, LLM flow, all flows
└── images/
    ├── architecture/                      # reference architecture and overview diagrams
    ├── step2-kong/ … step5-identity/      # per-step screenshots (numbered)
    └── README.md                          # image conventions and screenshots still to capture
```

## Next steps and further reading

- **Add the LLM Gateway to Bedrock, with Guardrails.** The IAM permissions are already in place. Kong's docs cover the [Bedrock provider](https://developer.konghq.com/ai-gateway/ai-providers/bedrock/) and the [AI AWS Guardrails plugin](https://developer.konghq.com/plugins/ai-aws-guardrails/).
- **Expose tools over MCP.** See the [AI MCP Proxy plugin](https://developer.konghq.com/plugins/ai-mcp-proxy/), which can proxy existing MCP servers or turn REST APIs into MCP tools.
- **Secure the A2A route.** Kong's guides show [key authentication](https://developer.konghq.com/how-to/secure-a2a-endpoints/) and [OpenID Connect](https://developer.konghq.com/how-to/secure-a2a-endpoints-with-oidc/) on A2A endpoints. Combine them with Step 5's Kong Identity tokens.
- **Token and cost budgets.** See the [AI Rate Limiting Advanced plugin](https://developer.konghq.com/plugins/ai-rate-limiting-advanced/).
- **AWS references:** [Amazon Bedrock AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/), [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html), [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/).
- **Protocols:** the [A2A protocol](https://a2a-protocol.org/) and the [Model Context Protocol](https://modelcontextprotocol.io/).
