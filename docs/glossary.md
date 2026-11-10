# Glossary

These are plain-language definitions for every acronym and product term used in this guide, in alphabetical order. Back to the [README](../README.md).

| Term | What it means here |
|---|---|
| **A2A (Agent2Agent protocol)** | An open protocol that lets AI agents talk to each other: one agent sends a task, another works on it and returns results. Agents describe themselves with an **Agent Card**. Step 3 uses it. See [a2a-protocol.org](https://a2a-protocol.org/). |
| **ACM (AWS Certificate Manager)** | AWS service that issues and renews TLS certificates. Step 1 issues a wildcard certificate that the NLB uses for HTTPS. |
| **Agent** | A program that uses an LLM to decide what to do, often calling tools or other agents to finish a task. |
| **Agent Card** | A JSON document an A2A agent publishes, usually at `/.well-known/agent-card.json`, describing its name, skills and endpoint. Like a business card for the agent. |
| **Agent Gateway** | Kong's name for the part of Kong AI Gateway that handles agent-to-agent (A2A) traffic, mainly through the AI A2A Proxy plugin. |
| **Agent Skill** | One capability listed in an Agent Card (for example, "returns hello world"). |
| **AgentCore (Amazon Bedrock AgentCore)** | AWS's managed platform for running agents and MCP servers. **AgentCore Runtime** hosts them, **AgentCore Gateway** exposes tools over MCP, and **AgentCore Identity** manages credentials. This guide deploys an agent to AgentCore Runtime with the **AgentCore CLI** (`agentcore`). |
| **AI A2A Proxy plugin** | Kong plugin (`ai-a2a-proxy`) that recognizes A2A traffic on a route, records A2A metrics and, in this guide, calls the AgentCore agent. |
| **AI AWS Guardrails plugin** | Kong plugin that checks requests and responses against an existing Amazon Bedrock guardrail. Not configured by this guide. |
| **AI Gateway (Kong AI Gateway)** | Kong Gateway with AI-specific plugins. In this guide it's described as three logical parts: LLM Gateway, MCP Gateway and Agent Gateway. |
| **AI MCP Proxy plugin** | Kong plugin that proxies MCP traffic to MCP servers, or turns REST APIs into MCP tools. Step 4 uses it in **conversion-listener** mode, where Kong both converts REST endpoints into tools and serves them as an MCP server. |
| **AI Proxy / AI Proxy Advanced plugins** | Kong plugins that route LLM requests to providers such as Bedrock, OpenAI or Anthropic. The Advanced version adds load balancing, fallback and semantic routing. |
| **AI Rate Limiting Advanced plugin** | Kong plugin that limits AI usage by tokens or cost rather than request count, per consumer, group, model or provider. |
| **AI Semantic Cache plugin** | Kong plugin that returns a stored response when a new prompt means the same as an earlier one. It uses Redis (on AWS: MemoryDB or ElastiCache) as the vector store. |
| **ALB / NLB** | Application Load Balancer / Network Load Balancer, AWS's managed load balancers. This guide uses an **NLB** in front of Kong. |
| **AWS Load Balancer Controller** | A Kubernetes add-on that creates AWS load balancers when a Kubernetes service asks for one. Installed in Step 1. |
| **awscurl** | A `curl`-like tool that signs requests with your AWS credentials (SigV4). Step 3 uses it to call AgentCore directly. |
| **CLI** | Command-line interface: a tool you run by typing commands in a terminal. |
| **Client credentials grant** | An OAuth2 flow for machine-to-machine access: a client trades its ID and secret for an access token. Step 5 uses it. |
| **CloudWatch (Amazon CloudWatch)** | AWS's logs, metrics and alarms service. AgentCore writes its runtime logs here. |
| **Cognito (Amazon Cognito)** | AWS's managed user directory and OAuth2/OIDC provider. An alternative to Kong Identity. |
| **Consumer / consumer group** | Kong's representation of whoever is calling the gateway (a user, app or agent), and a named group of them. Limits and analytics can be applied per consumer or group. |
| **Control plane** | Where gateway configuration is defined and managed. Here it's **Kong Konnect**. It doesn't handle your API or AI traffic. |
| **CP / DP** | Short for control plane / data plane. |
| **CRD (Custom Resource Definition)** | A Kubernetes extension that adds new object types. The Kong Operator adds CRDs such as `KonnectGatewayControlPlane` and `DataPlane`. |
| **Data plane** | The part of the gateway that actually handles traffic. Here it's Kong Gateway pods on your EKS cluster. |
| **decK** | Kong's CLI for declarative configuration. You describe services, routes and plugins in a YAML file. `deck gateway sync` makes the control plane match the file exactly, `deck gateway apply` only creates or updates (it never deletes), and `deck gateway reset` deletes all existing configuration. Step 3 uses reset and sync; Steps 4 and 5 use apply. |
| **EKS (Amazon Elastic Kubernetes Service)** | AWS's managed Kubernetes. The Kong data plane runs here. |
| **eksctl** | A CLI for creating and managing EKS clusters. |
| **ElastiCache / MemoryDB** | AWS's managed Redis-compatible services. The reference architecture uses **MemoryDB for Redis** for Kong's semantic features. |
| **FinOps** | The practice of managing and attributing cloud spend. |
| **Guardrails (Amazon Bedrock Guardrails)** | AWS service that checks prompts and responses for harmful content, denied topics, PII and more. Its standalone **ApplyGuardrail** API works with models outside Bedrock too. |
| **httpbin** | A public test API (`httpbin.konghq.com`) that echoes back the request it receives. Step 4's MCP tools call it so you can see exactly what Kong sent. |
| **Helm** | A package manager for Kubernetes. It installs the Load Balancer Controller and the Kong Operator. |
| **Hosted zone** | A Route 53 container for the DNS records of one domain. |
| **IAM (AWS Identity and Access Management)** | AWS's permission system. Kong's AWS access in this guide is defined entirely by an IAM policy. |
| **IdP (Identity Provider)** | A service that issues identity tokens. Kong Identity is the IdP in Step 5. |
| **Introspection** | An OAuth2 endpoint where a gateway asks the IdP "is this token still valid, and what does it allow?" Step 5's OpenID Connect plugin uses it. |
| **JSON-RPC** | A simple request/response format in JSON (`method`, `params`, `id`). Both MCP and A2A use it. |
| **JWT (JSON Web Token)** | A signed token format for access tokens. `jwt-cli` decodes them in Step 5. |
| **k9s** | A terminal UI for watching Kubernetes resources. Optional. |
| **Kong Identity** | Kong's OAuth2 authorization server, built into Konnect. Configured in Step 5. |
| **Kong Konnect** | Kong's SaaS platform: the control plane, analytics, Kong Identity and more. |
| **Kong Operator** | A Kubernetes controller that creates Konnect control planes and Kong data planes from Kubernetes YAML. Installed in Step 2. |
| **kubectl** | The standard CLI for Kubernetes. |
| **LLM (Large Language Model)** | A model that generates text, such as Anthropic Claude or Amazon Nova on Bedrock. |
| **LLM Gateway** | Kong's name for the part of Kong AI Gateway that handles model traffic (the AI Proxy plugins). Described in [concepts/llm-gateway-flow.md](concepts/llm-gateway-flow.md). |
| **MCP (Model Context Protocol)** | An open protocol for describing tools and data sources so that LLMs and agents can discover and call them in a standard way. See [modelcontextprotocol.io](https://modelcontextprotocol.io/). |
| **MCP Gateway** | Kong's name for the part of Kong AI Gateway that handles MCP traffic (the AI MCP Proxy plugin). Described in Step 4. |
| **MCP server / MCP tool** | An MCP server publishes one or more tools (functions an agent can call). Clients **initialize** a session, **list** the tools (`tools/list`) and **call** one (`tools/call`). In Step 4, Kong is the MCP server. |
| **MCP session ID** | An identifier an MCP server may return in the `Mcp-Session-Id` header when a client initializes. The client sends it back on later requests. |
| **mTLS** | Mutual TLS: both sides present certificates. The Kong data plane uses it to connect to Konnect. |
| **OAuth2 / OIDC (OpenID Connect)** | Standards for issuing and checking access tokens. In Step 5, Kong's **OpenID Connect plugin** checks every call to `/a2a` against Kong Identity. |
| **OpenAPI** | A standard format for describing REST APIs. The tool `parameters` in Step 4's decK file use OpenAPI-style parameter definitions. |
| **OTel (OpenTelemetry)** | An open standard for traces, metrics and logs. Kong's OTel plugin exports to any compatible backend. |
| **PAT (Personal Access Token)** | A token you generate in Konnect so that CLIs (Kong Operator, decK, `curl`) can call Konnect APIs as you. |
| **PII** | Personally identifiable information. |
| **Pod Identity (EKS Pod Identity)** | EKS feature that gives pods an IAM role without static keys. Kong uses it to call AWS services. |
| **Route / service (Kong)** | A **service** is an upstream Kong forwards to. A **route** is the path or host rule that sends requests to it. Plugins attach to either. |
| **Route 53 (Amazon Route 53)** | AWS's DNS and domain registration service. |
| **SAT (System Access Token)** | A Konnect token owned by a system account rather than a person. An alternative to a PAT. |
| **Secrets Manager (AWS Secrets Manager)** | AWS service for storing and rotating credentials. |
| **SigV4** | AWS Signature Version 4, the way requests to AWS APIs are signed with IAM credentials. AgentCore requires it. |
| **Strands** | An open-source agent SDK from AWS. The AgentCore CLI's default template uses it. |
| **Streamable HTTP** | The MCP transport that runs over ordinary HTTP POST requests, with optional `text/event-stream` responses. Step 4's `/mcp` endpoint uses it. |
| **TLS** | Transport Layer Security, the "S" in HTTPS. |
| **Token (LLM)** | A chunk of text that models count for limits and billing. Not the same as an access token. |
| **uv** | A fast Python package and environment manager, used to set up the sample agents. |
| **VPC** | Virtual Private Cloud, your isolated network in AWS. |
| **WAF (AWS WAF)** | AWS's web application firewall. |
