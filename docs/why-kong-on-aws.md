# Why Kong, if I already have AWS?

This page is for readers who already run GenAI on AWS and would rather not add a third-party product without a good reason. That's a reasonable default. The goal here is to show where Kong actually helps, where it doesn't, and how it fits with the AWS services you already use, so you can decide for yourself.

Back to the [README](../README.md).

## What AWS gives you for GenAI

AWS covers a lot of the GenAI stack natively, and covers it well.

| AWS service | What it does well for GenAI |
|---|---|
| **Amazon Bedrock** | Managed access to many foundation models (from Amazon, Anthropic, Meta, Mistral and others) through one AWS API, with IAM, VPC endpoints and CloudTrail built in. **Application inference profiles** with cost allocation tags let you attribute model spend to teams or apps in Cost Explorer. |
| **Bedrock Guardrails** | Content filters, denied topics, word filters, PII detection and contextual grounding checks. The standalone **ApplyGuardrail** API can check text for models that aren't on Bedrock too, as long as your code calls it. |
| **Bedrock AgentCore** | A managed runtime for agents and MCP servers (Runtime), plus **AgentCore Gateway**, which turns APIs and Lambda functions into MCP tools and offers semantic tool search, and **AgentCore Identity** for inbound and outbound credentials. Step 3 of this guide deploys an A2A agent to AgentCore Runtime. |
| **IAM** (and EKS Pod Identity) | Fine-grained, auditable permissions for every AWS call, with no long-lived keys when you use roles. |
| **Amazon API Gateway** | Managed API front door with request throttling, usage plans and API keys, authorizers and WAF integration. |
| **ALB / NLB** | Load balancing and TLS termination. This guide uses an NLB. |
| **AWS WAF** | Protection against common web exploits and bots at the edge. |
| **Amazon CloudWatch** | Logs, metrics, alarms and dashboards. AgentCore writes its runtime logs here (Step 3 tails them). |
| **AWS Secrets Manager** | Stores and rotates credentials. |
| **Amazon MemoryDB / ElastiCache** | Managed Redis-compatible data stores, usable as fast caches and vector stores. |

If all your traffic is one team calling Bedrock models from code you control, this list is very likely enough.

## Where the gaps show up in practice

The gaps aren't in any single AWS service. They show up once the *number* of things grows: more teams, more agents, more tools, more than one model provider, more than one environment. These are the patterns where a gateway layer like Kong earns its place.

**1. One policy layer across model providers, including ones outside Bedrock.**
Bedrock already gives you one API across the models it hosts. If teams also call providers that aren't on Bedrock (OpenAI directly, a self-hosted model, another cloud's model service), each integration brings its own SDK, keys and logging. Kong's AI Proxy and AI Proxy Advanced plugins put Bedrock and those other providers behind the same gateway routes, so authentication, limits and logging are applied the same way regardless of where the model lives.

**2. The same governance for LLM, MCP and agent-to-agent traffic.**
AWS has strong pieces for each kind of traffic (Bedrock for models, AgentCore Gateway for MCP tools, AgentCore Runtime for agents), each with its own configuration. Kong handles all three on one data plane, with its AI Proxy, AI MCP Proxy and AI A2A Proxy plugins, so one consumer identity and one rate-limit policy can apply across a model call, the tool call it triggers and the agent it delegates to. The [all-flows concept doc](concepts/all-flows.md) shows this.

**3. Budgets counted in tokens or dollars, enforced per consumer or group.**
API Gateway throttles by *requests* per second. Bedrock's cost allocation tags tell you *afterwards* who spent what, and AWS Budgets can alert you. Kong's **AI Rate Limiting Advanced** plugin enforces limits *inline*, counted in tokens or in cost (using per-model input and output prices you configure), scoped per consumer, consumer group, model or provider. Counters can be shared across data plane nodes through Redis, which on AWS can be MemoryDB or ElastiCache.

**4. Guardrails applied once, at the gateway.**
Bedrock Guardrails can protect non-Bedrock models through the ApplyGuardrail API, but each application has to call it. Kong's **AI AWS Guardrails** plugin calls your existing Bedrock guardrail from the gateway on requests and responses, so every route that uses it is covered without app changes. Your guardrail definitions stay in Bedrock.

**5. Semantic caching and prompt-level controls.**
Kong's **AI Semantic Cache** plugin returns a cached response when a new prompt *means* the same thing as an earlier one, using Redis as the vector store. That's different from Bedrock's model-level prompt caching, which reuses a repeated prompt prefix inside one model call. Kong also has prompt guard, prompt template and prompt decorator plugins (described in [Step 3](../3-a2a-agent-gateway-agentcore.md#kong-ai-gateway-plugins)).

**6. One identity layer for the humans, apps and agents calling you.**
IAM governs what *Kong* may do in AWS. Separately, you need to know *who is calling Kong*. Kong applies key auth, OAuth2 or OpenID Connect at the gateway, with Kong Identity (Step 5), Amazon Cognito or another provider as the issuer, and maps callers to consumers and consumer groups that limits and analytics use.

**7. The same policy across accounts, regions and environments outside AWS.**
Konnect manages any number of data planes from one control plane. The same routes and plugins can run on EKS in several accounts or regions, and on data planes outside AWS if part of your estate lives elsewhere.

**8. AI-aware observability in one place.**
Kong records token counts, cost, model, latency and consumer for each AI request in Konnect analytics, and can export traces and metrics over OpenTelemetry to the backend you choose. The AI A2A Proxy plugin adds A2A-specific metrics such as task metadata. The reference architecture also streams Kong metrics into CloudWatch, but this guide doesn't configure that yet.

> **Note on scope.** Points 3–5 and 8 describe Kong capabilities that this guide's steps **don't configure yet**. The guide deploys the data plane, the A2A route to AgentCore and Kong Identity.

## How Kong uses the AWS services you already pay for

Kong adds to your AWS footprint. It doesn't route around it. Here is what this repo actually wires up:

| AWS service | How this guide uses it | Where |
|---|---|---|
| **Amazon EKS** | Runs the Kong data plane as pods, managed by the Kong Operator. | Steps 1–2 |
| **EKS Pod Identity + IAM** | The only way Kong gets AWS permissions. The `bedrock-policy` lists exactly which Bedrock, AgentCore and Secrets Manager actions Kong may call. | Step 2 |
| **Network Load Balancer** | Created by the AWS Load Balancer Controller as Kong's public entry point. | Steps 1–2 |
| **AWS Certificate Manager** | Wildcard certificate on the NLB's 443 listener, issued and renewed by AWS. | Steps 1–2 |
| **Route 53** | Domain registration, DNS validation for ACM, and the `kong-dp.<domain>` alias to the NLB. | Steps 1–2 |
| **Bedrock AgentCore** | Hosts the A2A agent. Kong calls it with AWS IAM auth, so callers don't need AWS credentials. | Step 3 |
| **CloudWatch** | AgentCore runtime logs (`aws logs tail`). | Step 3 |
| **Amazon Bedrock + Guardrails** | IAM permissions are granted (`bedrock:InvokeModel`, `bedrock:ApplyGuardrail`). Shown in the reference architecture, but no route is configured yet. | Step 2 (permissions only) |
| **Secrets Manager** | IAM permissions are granted (`secretsmanager:GetSecretValue`). The reference architecture stores provider credentials and certificates here. | Step 2 (permissions only) |
| **MemoryDB for Redis** | In the reference architecture, the backend for semantic caching, semantic routing and semantic guards. Not deployed by this guide. | Architecture only |

The [who-owns-what](#who-owns-what) table below splits these responsibilities between AWS, Kong and you.

## Who owns what

| AWS-managed | Kong-managed | Your responsibility |
|---|---|---|
| EKS control plane | Konnect control plane (SaaS) | EKS worker nodes and upgrades |
| Network Load Balancer | Kong Identity (OAuth2 server) | Scope of the IAM policy |
| ACM certificate issuance and renewal | Konnect analytics | Kong routes, plugins and decK files |
| Route 53 DNS service | Kong Gateway and Operator releases | Konnect PAT and client secrets |
| Bedrock models | | Agent code (`server_1.py`, …) |
| Bedrock Guardrails service | | Domain and DNS records |
| AgentCore runtime | | Guardrail definitions in Bedrock |
| IAM and Pod Identity service | | Cost monitoring and clean-up |
| CloudWatch | | |

The Kong data plane runs in **your** account, on **your** nodes, so patching the nodes and choosing the Kong image version is your job. The control plane (Konnect) and the Kong Identity service are run by Kong. AWS keeps running everything Kong calls.

## When you probably don't need Kong

Being honest about this makes the rest of the page more useful:

- **One provider, and it's Bedrock.** Bedrock's single API, IAM, Guardrails and inference profiles cover you well.
- **One team, one or two apps.** Per-app integration is cheap when there are few apps. A shared gateway adds another component to run.
- **Low volume or early prototyping.** Budgets and caching matter less when spend is small and usage is predictable.
- **Your agents and tools all live in AgentCore.** AgentCore Gateway and AgentCore Identity may be all the tool governance you need.
- **You need only request-count throttling and API keys.** Amazon API Gateway usage plans do this natively.

In any of these cases, you can start AWS-only and add a gateway later. The Kong data plane can sit in front of the same Bedrock and AgentCore endpoints without changing them.

## A decision checklist

Answer yes or no. If you answer **yes to two or more**, Kong is likely worth evaluating. If you answer **yes to none or one**, AWS-native services alone are probably the simpler choice for now.

- [ ] Do teams call **model providers outside Bedrock**, or plan to?
- [ ] Do you need **per-team or per-agent budgets in tokens or dollars**, enforced inline rather than reported afterwards?
- [ ] Do you want the **same auth, limits and logging** across LLM calls, MCP tool calls and agent-to-agent calls?
- [ ] Do agents **outside AWS** (another cloud, on-prem, a partner) need to call agents or tools that run on AgentCore?
- [ ] Do you need the **same AI policy across several AWS accounts or regions**, or outside AWS?
- [ ] Do you want Bedrock Guardrails applied **without changing application code**?
- [ ] Is **duplicate prompt traffic** a meaningful share of your spend (where semantic caching could help)?

## Getting Kong on AWS

You can start with a [free 30-day trial of Kong Konnect on the AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-77nhc3l2cn5im). Kong also has an [AWS Marketplace partner page](https://konghq.com/partners/awsmarketplace). Check the listing for current terms, since Marketplace offers change over time.

## Sources

Checked against the vendors' own documentation in November 2026:

- Kong: [AI AWS Guardrails plugin](https://developer.konghq.com/plugins/ai-aws-guardrails/), [AI Rate Limiting Advanced](https://developer.konghq.com/plugins/ai-rate-limiting-advanced/), [LLM cost optimization (semantic cache with Redis)](https://developer.konghq.com/cookbooks/llm-cost-optimization/), [AI MCP Proxy](https://developer.konghq.com/plugins/ai-mcp-proxy/), [AI A2A Proxy](https://developer.konghq.com/plugins/ai-a2a-proxy/), [A2A in AI Gateway](https://developer.konghq.com/ai-gateway/a2a/).
- AWS: [ApplyGuardrail API](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails-use-independent-api.html), [Bedrock application inference profiles](https://docs.aws.amazon.com/bedrock/latest/userguide/cost-mgmt-application-inference-profiles.html), [AgentCore Gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway.html), [AgentCore Gateway semantic search](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-using-mcp-semantic-search.html), [API Gateway request throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html).
