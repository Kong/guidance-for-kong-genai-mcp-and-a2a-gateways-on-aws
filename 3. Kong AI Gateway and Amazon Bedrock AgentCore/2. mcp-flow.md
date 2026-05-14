# Kong AI Gateway and Amazon Bedrock AgentCore


This architecture illustrates a production-ready AI and agentic application platform built on top of the Kong Konnect Platform￼, integrating AI gateways, MCP-based tool orchestration, agent-to-agent communication, observability, and centralized governance across distributed environments.

At the core of the design is the separation between the control plane and the distributed AI execution environments. The centralized Konnect Control Plane provides administrative governance, configuration management, policy distribution, observability integration, and metering capabilities for all AI traffic and agent interactions across the platform. Administrators use this layer to manage APIs, AI routing policies, security controls, telemetry, and operational governance consistently across clusters and environments.

On the execution layer, the architecture deploys Kong AI Gateway components into Amazon EKS-based data plane nodes, providing scalable and secure runtime enforcement for AI workloads. The platform exposes three specialized gateway capabilities:

* Kong LLM Gateway for managing and routing requests to large language model providers such as OpenAI and Anthropic
* Kong MCP Gateway for securely exposing and governing Model Context Protocol (MCP) servers and tools
* Kong Agent Gateway for enabling Agent-to-Agent (A2A) communication patterns and intelligent orchestration between distributed AI agents

Within the AWS Bedrock AgentCore environment, Agent1 interacts with external LLM providers and MCP tools through Kong-managed LLM and MCP routes. MCP Server1 exposes tool interfaces that can be securely consumed by agents while remaining governed through centralized gateway policies. This pattern enables standardized authentication, rate limiting, observability, and policy enforcement across all tool invocations and model interactions.

A second execution environment demonstrates the distributed and multi-agent nature of the architecture. Agent2 and MCP Server2 operate independently while still remaining connected to the centralized Konnect control plane and shared governance model. Through the Kong Agent Gateway and AI A2A Proxy capabilities, agents can securely communicate, delegate tasks, and exchange contextual workflows across environments and clusters.

The architecture also incorporates enterprise-grade operational controls through:

* OpenTelemetry-based distributed tracing and observability
* AI-aware rate limiting and traffic governance
* Centralized metering and billing
* Unified policy enforcement across AI providers and agent ecosystems

By abstracting AI providers, MCP tool servers, and agent communication behind Kong’s gateway layer, the platform delivers a secure, observable, and extensible foundation for enterprise AI adoption. This approach enables organizations to standardize AI governance while supporting heterogeneous LLM providers, distributed agent frameworks, and rapidly evolving MCP ecosystems without tightly coupling applications to individual vendors or protocols.

With the Kong API Gateway Data Plane deployed, we need to configure it exposing an application. For the Development Time, one good option is to mock the application using the [**Kong Mocking Plugin**](https://developer.konghq.com/plugins/mocking/).

With the **Mocking Plugin** we can have a much faster and easier deployment since we don't need to provide actual upstream services or applications.

<img src="../static/images/development-time.png" width="1000" height="850"/>

The **Mocking Plugin** takes an **OpenAPI** specification to mock and expose the application.

The **OpenAPI Spec** we are going to use is [here](../openapi.yml).


## Kong Mocking Plugin

The **decK** (Declarations for Kong) tool is used to configure the **Mocking Plugin**

The **Mocking Plugin** configuration takes the **OpenAPI** specification and defines a **Kong Service** and a **Kong Route**. Note the **Kong Service** is ignored since the **Mocking Plugin** is going to manage the requests. The **decK** file can be found [here](../kong_aws_mock.yaml)


```
deck gateway reset --konnect-control-plane-name kong-aws --konnect-token $PAT -f
deck gateway sync --konnect-control-plane-name kong-aws --konnect-token $PAT kong_aws_mock.yaml
```


## Test the Kong API Gateway Routes

Set the ``DATA_PLANE_LB`` environment variable with domain name:

```
export DATA_PLANE_LB=kong-dp.$AWS_DOMAIN
```

You can use any of these requests to tests the Routes and the Mocking Application:

```
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/getTypeNames | jq
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/getTypeDefinitions | jq
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/createRecord | jq
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/patchRecord | jq
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/searchRecords | jq
curl -s -X POST https://$DATA_PLANE_LB/api/oauth/token | jq
```

For example, the following request:
```
curl -s -X POST https://$DATA_PLANE_LB/api/dataio/getTypeNames | jq
```

Should return this:
```
{
  "typeNames": [
    {
      "label": "CRM Contact",
      "typeName": "Contact"
    },
    {
      "label": "Sales Opportunity",
      "typeName": "Opportunity"
    }
  ]
}
```

