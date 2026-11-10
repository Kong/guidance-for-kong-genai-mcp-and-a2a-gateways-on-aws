# images/

These are the diagrams used by the [README](../README.md), the step docs and the concept docs.

## Conventions

- **`architecture/`** holds diagrams that aren't tied to one step. Each **`step<N>-<topic>/`** folder holds diagrams for one step, where `<N>` matches the step number.
- **Numeric prefixes** (`01-`, `02-`, …) set the order.
- **Lowercase kebab-case**, no spaces.
- Every image has **alt text** describing what it shows, followed by a one-line *italic caption*.
- The SVG diagrams use a solid white background so they read in GitHub's light and dark themes, and plain labeled boxes without vendor logos.

## What's here

| Path | What it shows | Used in |
|---|---|---|
| `architecture/01-reference-architecture.png` | AWS reference architecture: NLB, EKS, Kong data plane, Bedrock, AgentCore, MemoryDB, Secrets Manager, Konnect | README, solution overview |
| `architecture/03-kong-ai-gateway-agentcore.png` | Kong AI Gateway with Bedrock AgentCore | [concepts/kong-ai-gateway-and-agentcore.md](../docs/concepts/kong-ai-gateway-and-agentcore.md) |
| `architecture/04-llm-genai-flow.png` | LLM/GenAI request flow | [concepts/llm-gateway-flow.md](../docs/concepts/llm-gateway-flow.md) |
| `architecture/05-all-flows.png` | LLM, MCP and A2A flows together | [concepts/all-flows.md](../docs/concepts/all-flows.md) |
| `architecture/10-aws-only-vs-aws-plus-kong.svg` | An AWS-only GenAI stack next to AWS + Kong | README |
| `architecture/11-life-of-a-request.svg` | Numbered path of one request, from client to AgentCore and back | README |
| `step3-a2a/01-a2a-flow.png` | A2A flow through Kong's Agent Gateway | [Step 3](../3-a2a-agent-gateway-agentcore.md) |
| `step4-mcp/01-mcp-flow.png` | MCP flow through Kong's MCP Gateway | [Step 4](../4-mcp-gateway.md) |
