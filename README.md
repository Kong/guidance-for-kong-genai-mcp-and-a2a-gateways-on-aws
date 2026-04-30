# Guidance for Multi-Agent, Multi-Provider Advanced AI Gateway on AWS

## Summary
This implementation guide provides an overview of the Guidance for Multi-Agent, Multi-Provider Advanced AI Gateway on AWS, its reference architecture, deployment considerations, and configuration steps. Designed for the Agentic Era, this guide is intended for Solution Architects, AI Engineers, Platform Teams, and Cloud computing professionals who want to deploy a secure, observable, and highly efficient **Kong AI Gateway** and **Agent Gateway** environment on Amazon Web Services (AWS).

## Overview
As enterprises move from simple GenAI applications to complex multi-agent systems, organizations need an AI connectivity layer that governs interactions safely and at machine speed.
This implementation guide provides an automated AWS Cloud Development Kit (AWS CDK) and HashiCorp Terraform-based deployment of the **Kong AI Gateway** onto Amazon Elastic Container Service (Amazon ECS) or Amazon Elastic Kubernetes Service (Amazon EKS). It aims to be pre-configured with defaults allowing users to rapidly spin up Kong's unified gateway, serving as a comprehensive “Context Mesh” that securely brings together APIs, Large Language Models (LLMs), and autonomous agents.
It provides powerful features out-of-the-box, such as native Amazon Bedrock integration, AI Semantic Caching, multi-provider LLM routing, Agent-to-Agent (A2A) governance, and advanced AI Cost Optimization (AI FinOps).

![Architecture Diagram](assets/images/konnect.png)


## The Why: Features and Benefits
Without an AI connectivity strategy, there is no visibility, governance, or cost control. Kong AI Gateway serves as a complete enterprise solution for managing and standardizing interactions across your entire digital ecosystem.
* **A Unified Control Plane for Agents and LLMs**: Proxies and governs all Agent-to-Agent (A2A) communication and LLM consumption through a single, standardized gateway. Maintain audit trails of every RPC call, including caller identity, capabilities invoked, and outcomes.
* **AI Cost Optimization & FinOps**: Stop margin erosion and implement robust AI FinOps. Administrators can track token usage dynamically, configure usage-based billing, enforce quotas, and drastically reduce latency and costs using AI Semantic Caching (via Amazon ElastiCache/Redis).
* **Multi-Provider Routing and Fallback**: Features a single API for seamless integration with multiple LLM providers. Handle standardized inputs/outputs across models (Amazon Bedrock, OpenAI, Anthropic, etc.) and establish intelligent load balancing, failover mechanisms, and fallback routing to ensure maximum uptime.
* **Context Mesh & MCP Governance**: Protect your Model Context Protocol (MCP) servers and the data context your agents consume. Kong ensures only authorized agents can access sensitive APIs or invoke specific capabilities.
* **Security and Compliance**: Protect against prompt injection and enforce content rules using the AI Prompt Guard and AI Prompt Decorator plugins. Enforce centralized authentication, rate limiting, and real-time observability across all AI traffic.


## Use Cases
1. **Agentic Infrastructure Governance**: Provide a dedicated Agent Gateway to standardize A2A security and observability without changing how agents are built.
1. **Multi-Provider LLM Integration**: Focus on application logic rather than managing complex API calls. Seamlessly switch between different LLM providers (e.g., Amazon Bedrock, Azure OpenAI, Cohere) using a consistent interface.
1. **AI Cost Control**: Track token consumption across teams and models, set related budgets, and implement semantic caching to eliminate redundant LLM calls.
1. **Load Balancing**: Distribute high-volume inference requests across multiple LLM endpoints for superior performance and redundancy.





## Architecture Overview
The following outlines the reference implementation architecture for deploying the Kong AI Gateway on AWS.

### Architecture Steps
1. **Traffic Ingress**: Client applications and autonomous agents access the Kong AI Gateway proxy API via an Amazon Route 53 endpoint, protected against common web exploits using AWS Web Application Firewall (AWS WAF).
1. **Load Balancing**: AWS WAF forwards requests to an Application Load Balancer (ALB), which automatically distributes traffic to Kong Data Plane instances running as containers within Amazon ECS (Fargate) tasks or Amazon EKS pods. TLS/SSL is secured using AWS Certificate Manager (ACM).
1. **Kong AI Gateway Data Plane**: The deployed containers act as your high-performance, low-latency AI proxy. They process plugins natively (e.g., AI Proxy, AI Semantic Cache, AI Prompt Guard) before requests ever reach the foundation models.
1. **Control Plane (Kong Konnect): Kong Data Planes communicate securely with the Kong Konnect SaaS Control Plane. This provides platform teams with a centralized UI to push declarative configurations, monitor detailed AI analytics, and manage multi-tenant access.
1. **LLM Integrations**: Kong integrates natively with **Amazon Bedrock** to seamlessly handle prompt translation, model access, and routing to models like Amazon Nova or Anthropic Claude.
Pre-existing configurations easily route secondary traffic to third-party providers (OpenAI, Vertex AI) using native Kong AI plugins.
1. **AWS Services Integration**:
    * **Amazon ElastiCache (Redis)**: Acts as the high-speed backend for Kong's AI Semantic Caching, enabling multi-tenant prompt caching to optimize costs.
    * **AWS Secrets Manager**: Securely stores Kong Konnect control plane certificates, external model provider credentials, and sensitive configurations.
    * **Amazon S3 & CloudWatch**: Kong Data Planes and the Control Plane stream robust API and AI metrics (token usage, latency, error rates) to CloudWatch and persistent logs to Amazon S3.




## Plan Your Deployment
You can customize how your Kong AI Gateway is deployed and accessed based on specific network topologies and compliance requirements.

### Deployment Scenarios

#### Scenario 1: Default - Public with CloudFront (Recommended)
- Provides global performance with low-latency access via AWS CloudFront edge locations.
- AWS Shield Standard DDoS protection.
- Ideal for global user bases and globally distributed multi-agent systems.

#### Scenario 2: Custom Domain with CloudFront
- Professional appearance and brand consistency utilizing a custom Amazon Route 53 domain (e.g., ai-gateway.example.com).

#### Scenario 3: Private VPC Only (Highly Regulated Environments)
- Maximum security for internal enterprise applications. Complete isolation from the public internet.
- Traffic resolves only via VPN, AWS Direct Connect, or Transit Gateway. Ideal for organizations managing highly sensitive Context Meshes.




## How to: Deploy the Guidance
Before deploying, ensure you have an active Kong Konnect account. If you do not have one, you can [get started with a free 30-day trial of Kong Konnect on the AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-77nhc3l2cn5im).

### Prerequisite CLI Tools
- Install Docker CLI
- Install AWS CLI
- Install terraform CLI
- If using Amazon EKS, install kubectl

### Deployment Steps
1. **Clone the Repository** and navigate to the deployment directory.
2. **Configure Kong Konnect Secrets**: Generate a Data Plane certificate from your Kong Konnect control plane and store the Telemetry/Control Plane endpoints in AWS Secrets Manager.
3. **Set Environment Variables**: Configure your .env file for your selected orchestrator (DEPLOYMENT_PLATFORM="EKS" or "ECS").
4. **Run Terraform**:
```bash
terraform init
terraform apply
```
5. **Time to deploy**: Approximately 30-40 minutes.


### Example: Consuming Amazon Bedrock through Kong AI Gateway
Once deployed, your applications no longer need to manage complex LLM SDKs or AWS SigV4 signing directly for every service. Kong handles the heavy lifting. You can communicate with Amazon Bedrock via a standard unified HTTP request:

```python
import os
import requests

# Set your Kong API Gateway endpoint and authentication
KONG_ENDPOINT = os.getenv("KONG_AI_PROXY_ENDPOINT") # e.g., https://ai-gateway.yourdomain.com/v1/chat/completions
KONG_API_KEY = os.getenv("KONG_CONSUMER_API_KEY")

headers = {
    "Authorization": f"Bearer {KONG_API_KEY}",
    "Content-Type": "application/json"
}

# The payload format is standardized. Kong automatically translates this 
# into the correct Amazon Bedrock Converse API format.
payload = {
    "model": "bedrock/anthropic.claude-3-5-sonnet-20240620-v1:0", 
    "messages": [
        {"role": "user", "content": "Explain the concept of Agentic AI governance."}
    ]
}

response = requests.post(KONG_ENDPOINT, headers=headers, json=payload)

print(response.json())
```

### Implementing AI Cost Optimization
To activate AI Semantic Caching:
1. Log into your **Kong Konnect** Control Plane.
1. Select your AI Gateway Service.
1. Add the **AI Semantic Cache** plugin.
1. Point the configuration to your deployed Amazon ElastiCache (Redis) instance URL.
1. Define the similarity threshold (e.g., 0.95). Any future LLM requests that hit this semantic threshold will be served instantly from ElastiCache, bypassing the Bedrock/LLM call entirely, reducing latency to milliseconds, and optimizing token costs.








# Kong + AWS - Guidance for GenAI, MCP and A2A Gateway on AWS
Summary
This implementation guide provides a comprehensive overview of the Guidance for Generative AI, MCP and A2A Gateway on AWS, including its reference architecture, core components, and key design considerations for deployment.

The guide outlines how organizations can build a unified gateway to securely access and orchestrate multiple Generative AI (GenAI) providers in addition to emerging architectural patterns such as Model Context Protocol (MCP) for standardized tool and context exchange, Agent-to-Agent (A2A) communication for distributed AI Agents while maintaining governance, observability, and scalability. These patterns enable more advanced use cases, including multi-agent collaboration, tool chaining, and dynamic decision-making across heterogeneous AI services.

It also covers best practices for integrating GenAI capabilities into enterprise environments, including secure API exposure, traffic control, identity propagation, and policy enforcement across providers. It highlights how a centralized gateway can mediate interactions not only between applications and models, but also between agents and external tools, enabling consistent governance across MCP-enabled ecosystems and A2A interactions.

Detailed deployment considerations are included to help teams plan for scalability, high availability, cost optimization, and compliance requirements within AWS. Step-by-step configuration guidance is provided for implementing the solution using AWS services, ensuring seamless integration with existing cloud-native architectures and DevOps workflows.

This guide is intended for solution architects, business decision-makers, DevOps engineers, data scientists, and cloud professionals who want to design and implement a robust, extensible, and future-ready AI Agents with multi-provider GenAI platform on AWS.


Overview

Here’s the revised version including AgentCore alongside Kong AI Gateway, LLM, MCP, and Agent Gateways:

⸻

Overview

This implementation guide provides an automated deployment of Kong AI Gateway using AWS Cloud Development Kit (AWS CDK) and HashiCorp Terraform onto container orchestration platforms such as Amazon Elastic Container Service (Amazon ECS) and Amazon Elastic Kubernetes Service (Amazon EKS) on AWS. The solution is pre-configured with sensible defaults to help organizations rapidly deploy a production-ready AI gateway.

The architecture extends beyond a traditional LLM proxy by incorporating four complementary layers:

* LLM Gateway for unified access to multiple model providers
* MCP Gateway to standardize tool and context exchange via the Model Context Protocol
* Agent Gateway to orchestrate and govern autonomous and multi-agent systems, including Agent-to-Agent (A2A) communication
* AgentCore integration to provide a managed runtime for executing, scaling, and coordinating AI agents and toolchains

Together, these components form a cohesive AI control plane that manages model inference, agent workflows, and contextual interactions across heterogeneous environments.

The solution integrates natively with Amazon Bedrock, supporting foundation models, managed prompts, and conversation state. Enterprise-grade authentication is enabled through OAuth 2.0 and JWT-based identity providers (such as Okta), ensuring secure and scalable access for users, applications, and agents.

⸻

Features and benefits

This comprehensive platform delivers a unified enterprise solution for governing interactions across LLMs, MCP-enabled tools, and AI agents, enhanced by AgentCore as the execution backbone.

At its core, Kong AI Gateway provides a single, consistent API layer for multiple LLM providers—including Amazon Bedrock, OpenAI, Azure OpenAI, Cohere, and others—standardizing request and response formats across text generation, embeddings, and multimodal workloads. It abstracts provider-specific APIs while maintaining flexibility and portability.

The MCP Gateway introduces a standardized interface for tools, plugins, and contextual data sources. This allows models and agents to dynamically discover and invoke external systems (such as APIs, databases, and enterprise services) in a secure and governed way, enabling composable and extensible AI applications.

The Agent Gateway enables orchestration, routing, and governance of AI agents. It supports advanced patterns such as multi-agent collaboration and Agent-to-Agent (A2A) communication, allowing agents to coordinate tasks, share context, and delegate execution while remaining within policy boundaries.

AgentCore complements this by acting as the managed execution layer for agents. It provides capabilities such as lifecycle management, tool execution, state handling, and scalable runtime environments for agents and workflows. This enables organizations to operationalize agent-based architectures with reliability, elasticity, and governance, without having to build custom orchestration engines from scratch.

The platform enables centralized management of usage across users, teams, applications, and agents. Administrators can define budgets, enforce rate limits, restrict access to specific models or tools, and implement fine-grained routing and policy controls. Intelligent traffic management includes load balancing, automatic failover, retry strategies, and caching to optimize both performance and cost.

Security and compliance are foundational. The solution integrates with Amazon Bedrock Guardrails and extends safety, validation, and policy enforcement across all LLM providers, MCP tools, and agent interactions. It supports secure credential handling, token-based authentication, and end-to-end authorization, ensuring that both human users and autonomous agents operate within defined constraints.

Observability features provide deep visibility into LLM calls, MCP tool usage, and agent workflows, including logs, metrics, and traces. This enables debugging, auditing, performance tuning, and governance at scale.

Cost optimization mechanisms include prompt and response caching, usage attribution across teams and agents, budget enforcement, and real-time monitoring of resource consumption.

All functionality is accessible via APIs and an intuitive administrative UI, allowing operators to manage configurations and policies, while developers and users can test models, invoke tools, and interact with agents.

⸻

Use cases

Multi-provider LLM integration:
Seamlessly interact with multiple LLM providers such as Amazon Bedrock, OpenAI, Azure OpenAI, and Cohere through a unified API, avoiding vendor lock-in.

MCP-enabled tool integration:
Expose and consume tools (databases, APIs, SaaS platforms) via the Model Context Protocol, enabling standardized and dynamic tool usage across models and agents.

Agent orchestration and A2A workflows:
Build distributed AI systems where agents collaborate, coordinate, and delegate tasks using governed Agent-to-Agent communication patterns, powered by Agent Gateway and executed via AgentCore.

Agent runtime and lifecycle management:
Leverage AgentCore to deploy, scale, and manage agent execution environments, including toolchains, memory, and stateful workflows.

Cost management and governance:
Track usage across models, tools, and agents; enforce budgets; and apply rate limiting and policies to control spending and resource utilization.

Simplified development:
Abstract integration complexity by providing consistent interfaces for LLMs, MCP tools, and agents, allowing teams to focus on delivering business value.

Load balancing and resilience:
Distribute traffic across multiple providers and agent runtimes, ensuring high availability, redundancy, and optimal performance.

Access control and authentication:
Manage identities, API keys, and permissions for users, applications, and agents, enforcing fine-grained access control.

Logging and observability:
Gain full visibility into LLM interactions, MCP tool calls, and agent behaviors through comprehensive monitoring and analytics.

⸻

This version positions Kong AI Gateway, combined with AgentCore, as a full-stack AI platform—covering model access, tool interoperability (MCP), and intelligent agent execution and orchestration at scale.



Kong Konnect is a unified API lifecycle management platform that delivers a high-performance runtime engine to govern traditional API, AI, and microservices traffic. Within a Kubernetes environment like VKS, Kong API Gateway (part of Kong Konnect) acts as an intelligent “control tower” translating external requests into secure and governed internal traffic with sub-millisecond latency while providing a single pane of glass for configuration, governance and deep analytics.

Enterprise needs:
Customers today face significant challenges as their Kubernetes environments scale. The proliferation of microservices, external integrations, and new AI workloads increases traffic volume and connectivity complexity, creating material risks to performance and availability. The core issue is a lack of end-to-end governance: as diverse workloads expand, unmanaged interactions make it difficult to apply consistent security and enforce global consumption policies.
Why should customers care?
Kong’s API gateway on VKS addresses these challenges by providing a unified, policy-driven platform for comprehensive connectivity. This architecture validates Kong as the standardized management and traffic governance layer for VKS helping organizations bridge the gap between traditional infrastructure and AI-native agility. It ensures that every request—from the physical host to the deepest AI workload—is secure, optimized, and controlled. This benefits customers by providing a centralized experience that reduces operational complexity and ensures consistent security across all runtimes.
To learn more about how VKS and Kong work together, refer to the full Reference Architecture.





Kong Konnect is a unified API lifecycle management platform that delivers a high-performance runtime engine to govern traditional API, AI, and microservices traffic. Within a Kubernetes environment like VKS, Kong API Gateway (part of Kong Konnect) acts as an intelligent “control tower,” translating external requests into secure and governed internal traffic with sub-millisecond latency while providing a single pane of glass for configuration, governance, and deep analytics. By consolidating control and visibility into a single platform, Kong Konnect enables platform teams and developers to move faster without sacrificing reliability or security, even as systems grow in scale and complexity.

At its core, Kong Konnect bridges the gap between infrastructure and application layers. It abstracts the complexity of service-to-service communication and enforces policies consistently across all traffic flows. Whether handling north-south traffic (external client to cluster) or east-west traffic (service-to-service within the cluster), the gateway ensures that every request is authenticated, authorized, observed, and optimized. This becomes increasingly critical as organizations adopt hybrid architectures that combine traditional services, cloud-native microservices, and AI-driven workloads.

Enterprise needs:

Customers today face significant challenges as their Kubernetes environments scale. The proliferation of microservices, external integrations, and new AI workloads increases traffic volume and connectivity complexity, creating material risks to performance and availability. Each new service introduces additional endpoints, dependencies, and potential failure points. Without a centralized mechanism to manage these interactions, teams often resort to fragmented tooling and inconsistent configurations, which leads to operational inefficiencies and heightened risk.

The core issue is a lack of end-to-end governance. As diverse workloads expand, unmanaged interactions make it difficult to apply consistent security controls, enforce global consumption policies, and maintain observability across the entire system. For example, a single user request may traverse multiple services, APIs, and AI models before returning a response. Without unified governance, tracking, securing, and optimizing that request path becomes extremely difficult.

Security is another major concern. In distributed environments, enforcing zero-trust principles—such as mutual TLS, authentication, and authorization—across all services is non-trivial. Misconfigurations or gaps in policy enforcement can expose sensitive data or create vulnerabilities. Additionally, as AI workloads are introduced, new considerations arise around model access, prompt handling, and data privacy, further increasing the need for robust governance.

Operational complexity also grows significantly. Platform teams must manage ingress controllers, service meshes, API gateways, and observability tools, often across multiple clusters or regions. Without consolidation, this results in duplicated effort, inconsistent policies, and difficulty scaling operations. Developers, meanwhile, face friction when trying to expose or consume services, slowing down innovation and time-to-market.

Why should customers care?

Kong’s API gateway on VKS directly addresses these challenges by providing a unified, policy-driven platform for comprehensive connectivity. Instead of managing multiple disjointed tools, organizations can standardize on a single layer that handles traffic management, security, and observability across all workloads. This dramatically simplifies operations while improving consistency and control.

One of the key benefits is centralized policy enforcement. With Kong, organizations can define authentication, rate limiting, transformation, and security policies once and apply them globally. This ensures that all services—regardless of where they run—adhere to the same standards. For example, an enterprise can enforce API key validation, OAuth2 authentication, or JWT verification across all endpoints without requiring individual service teams to implement these controls themselves.

Performance optimization is another critical advantage. Kong’s high-performance runtime is designed to handle massive volumes of traffic with minimal latency overhead. This is particularly important for latency-sensitive applications such as real-time APIs, financial services, and AI inference workloads. By operating at the edge of the cluster and efficiently routing traffic, Kong ensures that requests are processed quickly and reliably, even under heavy load.

Observability and analytics also play a crucial role. Kong Konnect provides deep insights into traffic patterns, service performance, and usage metrics. This visibility allows teams to identify bottlenecks, detect anomalies, and make data-driven decisions about scaling and optimization. For instance, teams can monitor API usage trends, track error rates, and analyze latency distributions across services, all from a centralized dashboard.

Another important aspect is developer productivity. By abstracting away the complexity of networking and security, Kong enables developers to focus on building features rather than managing infrastructure. Self-service capabilities allow teams to expose APIs, configure routes, and apply policies without deep expertise in Kubernetes networking. This accelerates development cycles and reduces dependency on platform teams.

As organizations adopt AI workloads, the need for governance becomes even more pronounced. AI services often involve interactions with large language models, vector databases, and external APIs. Kong provides a consistent layer to manage these interactions, ensuring that requests to AI services are authenticated, monitored, and controlled. This helps organizations maintain compliance and protect sensitive data while enabling innovation in AI-driven applications.

This architecture validates Kong as the standardized management and traffic governance layer for VKS, helping organizations bridge the gap between traditional infrastructure and AI-native agility. By unifying control across all types of workloads, Kong ensures that organizations can scale confidently without losing visibility or control.

It ensures that every request—from the physical host to the deepest AI workload—is secure, optimized, and controlled. This end-to-end coverage is essential in modern environments where workloads are highly distributed and dynamic. Whether a request originates from a mobile app, a web client, or an internal service, Kong provides consistent enforcement and visibility throughout its lifecycle.

This benefits customers by providing a centralized experience that reduces operational complexity and ensures consistent security across all runtimes. Instead of juggling multiple tools and configurations, teams can rely on a single platform to manage their entire API ecosystem. This not only reduces costs but also improves reliability and scalability.

Furthermore, Kong’s cloud-native design aligns seamlessly with Kubernetes principles. It integrates naturally with Kubernetes resources, enabling declarative configuration and automation through infrastructure-as-code practices. This makes it easier to manage environments at scale and maintain consistency across deployments.

In addition, Kong supports hybrid and multi-cloud deployments, allowing organizations to extend their governance model beyond a single cluster or region. This flexibility is critical for enterprises that operate across multiple environments and need a consistent approach to traffic management and security.

Ultimately, Kong Konnect on VKS empowers organizations to build, secure, and scale modern applications with confidence. It transforms the API gateway from a simple routing layer into a strategic control plane for all connectivity, enabling businesses to innovate faster while maintaining the highest standards of performance and security.

To learn more about how VKS and Kong work together, refer to the full Reference Architecture.







The Platform
Together, the following components represent the three layers of the new AI platform::
AI Gateway: Kong AI Gateway (including MCP support) controls both GenAI and MCP flow and orchestrates the existing services like Vector Databases, Event Streaming, etc.
Compute Layer: Akamai Linode Kubernetes Engine (LKE)
Security Layer: Akamai Firewall for AI

Here's the fundamental diagram with the three main components:


A basic LLM request flow goes through the following steps:
User or Agent sends a request with a prompt.
Request passes through Akamai Firewall for AI. Prompt is inspected and sanitized.
Request reaches the infrastructure on Akamai LKE.
Request goes through Kong AI Gateway: The request is Authenticated and routed to the best model.
Model executes inference.
Response flows back to Kong which logs it and generates metrics and traces.
Filtered again by Akamai Firewall for AI.
Return to user.

Multiple variations also exist. Depending on the request, Kong AI Gateway may send queries to the Vector Database to solve, for example, Semantic Routing policies.

Similarly, the Agent might send MCP requests which will be also handled by the Data Plane which is responsible for enforcing policies specifically defined for the MCP Servers and Tools, like, for example OAuth2 Authorization.

Kong AI Gateway
As part of the Kong Konnect product, the Kong AI Gateway is designed to solve several challenges in AI adoption. In fact, modern AI applications rarely rely on a single model. Instead, they combine multiple GenAI providers, Agent frameworks, external MCP (Model Context Protocol) Servers and REST based APIs.

Kong AI Gateway is a powerful set of features built on top of Kong Gateway, designed to help developers and organizations effectively adopt AI capabilities quickly and securely. Logically speaking it provides capabilities to play both roles LLM (or GenAI) and MCP Gateway.
LLM Gateway: While AI providers don’t conform to a standard API specification, the Kong LLM Gateway provides a normalized API layer allowing clients to consume multiple AI services from the same client code base. The AI Gateway provides additional capabilities for credential management, AI usage observability, governance, and tuning through prompt engineering. Developers can use no-code AI Plugins to enrich existing API traffic, easily enhancing their existing application functionality.
MCP Gateway: It sits side-by-side with the Kong LLM Gateway and it is responsible for converting Kong Gateway Services into MCP Servers as well as proxying and protecting existing MCP Servers.

At its core, Kong AI Gateway provides:
GenAI/LLM Provider abstraction: It exposes a unified API that hides differences between LLM providers, allowing applications to switch models without rewriting code.
Semantic Processing: Implements Routing, Caching and Guardrails policies based on semantics.
Advanced and Dynamic Routing Policies based on cost, latency, etc.
Token-based Rate Limiting.
Governance and observability: It centralizes observability signals including metrics, logging and tracing for all LLM and MCP traffic.
Security and policy enforcement: Provides extensive AuthN and AuthZ mechanisms to protect the Models and MCP Server including OAuth/OIDC, API Key, mTLS, etc.


Feature
LLM Gateway Role
MCP Gateway Role
Primary Task
Normalizing APIs across providers (OpenAI, Anthropic, etc.)
Connecting Agents to local/remote tools and data sources.
Policy Focus
Prompt engineering, token rate-limiting, and cost-routing.
AuthN/AuthZ for tools and proxying MCP server traffic.
Abstraction
Hides differences between LLM providers.
Converts standard Gateway Services into MCP-compatible servers. 


Akamai Linode Kubernetes Engine
The Kong Konnect platform provides a Cloud Management Control Plane (CP), which manages all service configurations. Through specific communication channels, it propagates those configurations to all runtime Data Planes (DP) where the Kong AI Gateway resides.

Underneath the Kong Konnect AI Gateway Data Plane sits the compute infrastructure. This is where Akamai Linode Kubernetes Engine (LKE) comes in.

Beside being totally based on Kubernetes, Akamai LKE provides Virtual Machines based on CPU/GPU, Load Balancers, Storage, Global Edge infrastructure and Built-in Network Security.

Akamai Firewall for AI
In this architecture, security is not an afterthought—it is embedded directly into the flow of the AI interaction. Akamai Firewall for AI is deployed here as a high-performance, specialized security layer designed specifically for the nuances of Large Language Models (LLMs).
By sitting alongside the Kong AI Gateway on Akamai’s Edge, FAI provides real-time inspection of the "intent" behind every request. It doesn't just look for malicious code; it understands the context of the conversation. While Kong orchestrates the LLM traffic and MCP flows, Akamai secures the intelligence being exchanged.
The Akamai Firewall for AI introduces sophisticated security policies to address the unique vulnerabilities of the GenAI era:
Prompt Injection Attacks. Manipulating AI-generated responses to leak sensitive information or bypass safety measures.
Toxic Output & Topic Moderation. AI-generated content that may include harmful, offensive language, or restricted topics.
Data Security & Data Exfiltration. Threat actors attempting to extract PII and other sensitive data from AI models.
AI-Specific Denial of Service (DoS). Attackers overloading AI models with high-volume or malicious queries.

Here's a screenshot of a Firewall for AI policy definition:


Conclusion
By unifying Kong AI Gateway with Akamai’s secure cloud infrastructure, organizations can finally move beyond the "experimental" phase of GenAI with total confidence. This "Secure by Design" architecture that effectively decouples your AI logic from the underlying model providers, shielding your business from vendor lock-in and volatile API costs.
For the enterprise, this means accelerated time-to-market for new AI agents, strengthened compliance through rigorous edge filtering, and operational clarity via a single pane of glass for all AI and MCP traffic. Instead of managing fragmented tools, you gain a resilient, high-performance foundation that turns AI from a security risk into a scalable competitive advantage.
Ready to Build?
Explore the documentation from Akamai and Kong to find the right deployment path for your environment.
Experience the Control Plane: Start a 30-day trial of Kong Konnect.
Scale your Infrastructure: Kick off your free Akamai trial today.





