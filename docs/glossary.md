# Glossary

These are plain-language definitions for every acronym and product term used in this guide, in alphabetical order. Back to the [README](../README.md).

| Term | What it means here |
|---|---|
| **A2A (Agent2Agent protocol)** | An open protocol that lets AI agents talk to each other: one agent sends a task, another works on it and returns results. Agents describe themselves with an **Agent Card**. Step 3 uses it. See [a2a-protocol.org](https://a2a-protocol.org/). |
| **ACM (AWS Certificate Manager)** | AWS service that issues and renews TLS certificates. Step 1 issues a wildcard certificate that the NLB uses for HTTPS. |
| **Agent** | A program that uses an LLM to decide what to do, often calling tools or other agents to finish a task. |
| **Agent Card** | A JSON document an A2A agent publishes, usually at `/.well-known/agent-card.json`, describing its name, skills and endpoint. Like a business card for the agent. |
| **Agent Gateway** | Kong's name for the part of Kong AI Gateway that handles agent-to-agent (A2A) traffic. On the AI Gateway it's built from **Agent** entities (Step 3). |
| **Agent Skill** | One capability listed in an Agent Card (for example, "returns hello world" for the Step 3 stub). |
| **AgentCore (Amazon Bedrock AgentCore)** | AWS's managed platform for running agents and MCP servers. **AgentCore Runtime** hosts them, **AgentCore Gateway** exposes tools over MCP, and **AgentCore Identity** manages credentials. This guide deploys an agent to AgentCore Runtime with the **AgentCore CLI** (`agentcore`). |
| **AI A2A Proxy plugin** | Kong plugin (`ai-a2a-proxy`) that handles A2A traffic on a classic Kong Gateway route. The AI Gateway's Agent entity uses it under the hood: the data plane log shows `[ai-a2a-proxy] Creating aws_iam auth handler` when it signs AgentCore calls. |
| **AI AWS Guardrails plugin** | Kong plugin that checks requests and responses against an existing Amazon Bedrock guardrail. Not configured by this guide. |
| **AI Gateway (Kong AI Gateway)** | Kong's gateway for AI traffic. In Konnect, an **AI Gateway** is its own kind of control plane where you declare Agents, MCP Servers, Models, Model Providers and Auth Strategies instead of services, routes and plugins. This guide's is `kong-aws-ai` (Step 2). It covers three logical parts: LLM Gateway, MCP Gateway and Agent Gateway. |
| **Auth Strategy (AI Gateway)** | An AI Gateway entity that authenticates callers, here with OpenID Connect introspection against Kong Identity. Attached to the Agent, MCP Server and Model in Steps 5 and 6. |
| **AI MCP Proxy plugin** | Kong plugin that proxies MCP traffic, or turns REST APIs into MCP tools, on a classic Kong Gateway route. On the AI Gateway, the **MCP Server** entity does this job. |
| **AI Proxy / AI Proxy Advanced plugins** | Kong plugins that route LLM requests to providers such as Bedrock, OpenAI or Anthropic on a classic Kong Gateway. On the AI Gateway, **Model** and **Model Provider** entities do this job (Step 6). |
| **AI Policy (AI Gateway)** | An AI Gateway entity that adds behavior to AI traffic, such as a rate limit, a guardrail or PII redaction. It applies globally or to the Agents, MCP Servers or Models it's attached to. Step 8 attaches a `rate-limiting` policy to the agent. |
| **AI Rate Limiting Advanced plugin** | Kong plugin that limits AI usage by tokens or cost rather than request count, per consumer, group, model or provider. |
| **AI Semantic Cache plugin** | Kong plugin that returns a stored response when a new prompt means the same as an earlier one. It uses Redis (on AWS: MemoryDB or ElastiCache) as the vector store. |
| **ALB / NLB** | Application Load Balancer / Network Load Balancer, AWS's managed load balancers. This guide uses an **NLB** in front of Kong. |
| **AWS Load Balancer Controller** | A Kubernetes add-on that creates AWS load balancers when a Kubernetes service asks for one. Installed in Step 1. |
| **awscurl** | A `curl`-like tool that signs requests with your AWS credentials (SigV4). Step 3 uses it to call the SigV4 AgentCore runtime directly. |
| **CLI** | Command-line interface: a tool you run by typing commands in a terminal. |
| **Client credentials grant** | An OAuth2 flow for machine-to-machine access: a client trades its ID and secret for an access token. Step 5 uses it. |
| **CloudWatch (Amazon CloudWatch)** | AWS's logs, metrics and alarms service. AgentCore writes its runtime logs here. |
| **Cognito (Amazon Cognito)** | AWS's managed user directory and OAuth2/OIDC provider. An alternative to Kong Identity. |
| **Consumer / consumer group** | Kong's representation of whoever is calling the gateway (a user, app or agent), and a named group of them. Limits and analytics can be applied per consumer or group. |
| **Control plane** | Where gateway configuration is defined and managed. Here it's a **Konnect AI Gateway**. It doesn't handle your API or AI traffic. |
| **CP / DP** | Short for control plane / data plane. |
| **CRD (Custom Resource Definition)** | A Kubernetes extension that adds new object types. The Kong Operator adds CRDs such as `KonnectAIGateway` and `AIGatewayDataPlane` (Step 2). |
| **Data plane** | The part of the gateway that actually handles traffic. Here it's Kong AI Gateway pods (`kong/kong-ai-gateway`) on your EKS cluster. |
| **EKS (Amazon Elastic Kubernetes Service)** | AWS's managed Kubernetes. The Kong data plane runs here. |
| **eksctl** | A CLI for creating and managing EKS clusters. |
| **ElastiCache / MemoryDB** | AWS's managed Redis-compatible services. The reference architecture uses **MemoryDB for Redis** for Kong's semantic features. |
| **FinOps** | The practice of managing and attributing cloud spend. |
| **Guardrails (Amazon Bedrock Guardrails)** | AWS service that checks prompts and responses for harmful content, denied topics, PII and more. Its standalone **ApplyGuardrail** API works with models outside Bedrock too. |
| **httpbin** | A test API that echoes back the request it receives. Step 4 runs one (go-httpbin) inside the cluster, and its MCP tools call it so you can see exactly what Kong sent. Step 7 points the tools at the inventory API instead. |
| **Helm** | A package manager for Kubernetes. It installs the Load Balancer Controller and the Kong Operator. |
| **Hosted zone** | A Route 53 container for the DNS records of one domain. |
| **Inventory API** | The small in-cluster REST API Step 7 runs (`code/inventory/inventory-api.yaml`), with three products and four orders. The MCP tools call it, so the agent's answers contain data the model couldn't know. |
| **IAM (AWS Identity and Access Management)** | AWS's permission system. Kong's AWS access in this guide is defined entirely by an IAM policy. |
| **IdP (Identity Provider)** | A service that issues identity tokens. Kong Identity is the IdP in Step 5. |
| **Introspection** | An OAuth2 endpoint where a gateway asks the IdP "is this token still valid, and what does it allow?" Step 5's Auth Strategy uses it. |
| **JSON-RPC** | A simple request/response format in JSON (`method`, `params`, `id`). Both MCP and A2A use it. |
| **JWT (JSON Web Token)** | A signed token format for access tokens. Kong Identity issues them, and `jwt-cli` decodes them (Step 5). |
| **k9s** | A terminal UI for watching Kubernetes resources. Optional. |
| **Kong Identity** | Kong's OAuth2 authorization server, built into Konnect. Issues the tokens Kong checks on every route (Step 5). |
| **Kong Konnect** | Kong's SaaS platform: the control plane, analytics, Kong Identity and more. |
| **kongctl** | Kong's CLI for Konnect. Steps 3 to 8 use it to declare AI Gateway entities from YAML (`kongctl diff`, `kongctl apply`). |
| **Kong Operator** | A Kubernetes controller that creates Konnect AI Gateways and their data planes from Kubernetes YAML. Installed in Step 2. |
| **kubectl** | The standard CLI for Kubernetes. |
| **LLM (Large Language Model)** | A model that generates text, such as Anthropic Claude or Amazon Nova on Bedrock. |
| **LLM Gateway** | Kong's name for the part of Kong AI Gateway that handles model traffic. On the AI Gateway it's built from **Model** and **Model Provider** entities (Step 6). Described in [concepts/llm-gateway-flow.md](concepts/llm-gateway-flow.md). |
| **MCP (Model Context Protocol)** | An open protocol for describing tools and data sources so that LLMs and agents can discover and call them in a standard way. See [modelcontextprotocol.io](https://modelcontextprotocol.io/). |
| **MCP Gateway** | Kong's name for the part of Kong AI Gateway that handles MCP traffic. On the AI Gateway it's built from **MCP Server** entities (Step 4). |
| **MCP Server (AI Gateway)** | An AI Gateway entity that publishes MCP tools. Type `conversion-listener` turns REST operations into tools and serves them itself (Step 4). |
| **MCP server / MCP tool** | An MCP server publishes one or more tools (functions an agent can call). Clients **initialize** a session, **list** the tools (`tools/list`) and **call** one (`tools/call`). In Step 4, Kong is the MCP server. |
| **MCP session ID** | An identifier an MCP server may return in the `Mcp-Session-Id` header when a client initializes. The client sends it back on later requests. |
| **Model / Model Provider (AI Gateway)** | AI Gateway entities for LLM traffic. A **Model Provider** holds a provider's connection and credentials (here Bedrock with Pod Identity). A **Model** is the name clients request (here `nova-micro`), routed to a provider's model (Step 6). |
| **mTLS** | Mutual TLS: both sides present certificates. The Kong data plane uses it to connect to Konnect. |
| **OAuth2 / OIDC (OpenID Connect)** | Standards for issuing and checking access tokens. In Step 5, an OpenID Connect **Auth Strategy** checks every call to the agent, the MCP server and the model against Kong Identity. |
| **OpenAPI** | A standard format for describing REST APIs. The tool `parameters` in Step 4's MCP Server use OpenAPI-style parameter definitions. |
| **OTel (OpenTelemetry)** | An open standard for traces, metrics and logs. Kong can export to any compatible backend. |
| **PAT (Personal Access Token)** | A token you generate in Konnect so that the Kong Operator, kongctl and `curl` can call Konnect APIs as you. |
| **PII** | Personally identifiable information. |
| **Pod Identity (EKS Pod Identity)** | EKS feature that gives pods an IAM role without static keys. The AI Gateway data plane gets its IAM role through it (Step 2), to sign calls to AgentCore and Bedrock. |
| **Route / service (Kong)** | On a classic Kong Gateway, a **service** is an upstream Kong forwards to, and a **route** is the path or host rule that sends requests to it. On the AI Gateway, each Agent, MCP Server and Model has its own route settings instead. |
| **Route 53 (Amazon Route 53)** | AWS's DNS and domain registration service. |
| **SAT (System Access Token)** | A Konnect token owned by a system account rather than a person. An alternative to a PAT. |
| **Rate limit** | A cap on how many requests a caller may send in a time window. Requests over the cap get `429 Too Many Requests` without reaching the backend. Step 8 limits `/a2a` to 5 requests a minute. |
| **Secrets Manager (AWS Secrets Manager)** | AWS service for storing and rotating credentials. Step 7 keeps the agent's Kong Identity client secret there. |
| **SigV4** | AWS Signature Version 4, the way requests to AWS APIs are signed with IAM credentials. AgentCore runtimes require it by default. The AI Gateway signs AgentCore (Step 3) and Bedrock (Step 6) calls with it. |
| **Strands** | An open-source agent SDK from AWS. The AgentCore CLI's default template uses it, and so does the Step 7 inventory agent, to call the model and MCP tools through Kong. |
| **Streamable HTTP** | The MCP transport that runs over ordinary HTTP POST requests, with optional `text/event-stream` responses. Step 4's `/mcp` endpoint uses it. |
| **TLS** | Transport Layer Security, the "S" in HTTPS. |
| **Token (LLM)** | A chunk of text that models count for limits and billing. Not the same as an access token. |
| **uv** | A fast Python package and environment manager, used to set up the sample agents. |
| **VPC** | Virtual Private Cloud, your isolated network in AWS. |
| **WAF (AWS WAF)** | AWS's web application firewall. |
