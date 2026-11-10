# images/

These are the diagrams and screenshots referenced from the [README](../README.md) and the numbered step docs.

## Conventions

- **One folder per step**, named `step<N>-<topic>/`, where `<N>` matches the step number in the README and the step doc's filename (`2-kong-konnect-data-plane.md` → `step2-kong/`).
- **`architecture/`** holds diagrams that aren't tied to one step.
- **Numeric prefixes** (`01-`, `02-`, …) give the order an image appears in its step. The new diagrams in `architecture/` start at `10-` so they sort after the existing diagrams.
- **Lowercase kebab-case**, no spaces.
- Every image is referenced with **alt text** that describes what it shows, followed by a one-line *italic caption*.
- **No fabricated screenshots.** Where a real console screenshot is needed but not captured yet, the doc has an HTML comment `<!-- TODO: capture screenshot: ... -->`, the intended image tag commented out, and a visible "Screenshot pending" line. When you add the file, uncomment the image tag and delete the TODO and "pending" lines.
- New diagrams are **SVG** with a solid white background (readable in GitHub's light and dark themes) and plain labeled boxes, with no vendor logos. They come from a small script that isn't in this repo. No PNG exports are included because no SVG rasterizer was available when they were made.

## What's here

| Path | What it shows |
|---|---|
| `architecture/01-reference-architecture.png` | AWS reference architecture: NLB, EKS, Kong data plane, Bedrock, AgentCore, MemoryDB, Secrets Manager, Konnect |
| `architecture/02-konnect-capabilities.png` | Kong capabilities mapped onto AWS (control plane, data plane, providers, AWS infrastructure) |
| `architecture/03-kong-ai-gateway-agentcore.png` | Kong AI Gateway with Bedrock AgentCore |
| `architecture/04-llm-genai-flow.png` | LLM/GenAI request flow |
| `architecture/05-all-flows.png` | LLM, MCP and A2A flows together |
| `architecture/10-aws-only-vs-aws-plus-kong.svg` | An AWS-only GenAI stack next to AWS + Kong |
| `architecture/11-life-of-a-request.svg` | Numbered path of one request, from client to AgentCore and back |
| `architecture/12-who-owns-what.svg` | AWS-managed vs Kong-managed vs your responsibility |
| `step2-kong/01-control-plane.png` | Konnect Gateway Manager listing `kong-aws` |
| `step2-kong/02-data-plane-connected.png` | Konnect Data Plane Nodes, one node Connected / In Sync |
| `step3-a2a/01-a2a-flow.png` | A2A flow through Kong's Agent Gateway |
| `step4-mcp/01-mcp-flow.png` | MCP flow through Kong's MCP Gateway |

## Screenshots still to capture

You need access to a real AWS account and Konnect org to capture these. Use the exact filename, so the commented-out tags in the docs work when you uncomment them.

- [ ] `step1-eks/01-eks-cluster-active.png`: **EKS console** → Clusters (`us-west-2`), cluster `kong314` with Status **Active**. Used in [1-eks-cluster.md](../1-eks-cluster.md).
- [ ] `step1-eks/02-route53-hosted-zone.png`: **Route 53** → Hosted zones → your domain, showing the NS, SOA and ACM validation **CNAME** records. Used in [1-eks-cluster.md](../1-eks-cluster.md).
- [ ] `step1-eks/03-acm-certificate-issued.png`: **ACM console** (`us-west-2`), certificate for `*.<your domain>` with Status **Issued**. Used in [1-eks-cluster.md](../1-eks-cluster.md) and the [README](../README.md).
- [ ] `step2-kong/03-nlb-listeners.png`: **EC2** → Load Balancers → the NLB created for `proxy-kong-aws` → Listeners tab, showing ports **80** and **443**, with the ACM certificate on 443. Used in [2-kong-konnect-data-plane.md](../2-kong-konnect-data-plane.md).
- [ ] `step3-a2a/02-agentcore-runtime-ready.png`: **Bedrock AgentCore console** → Runtimes (`us-west-2`), runtime `agentcorekong`, status **Ready**, protocol **A2A**. Used in [3-a2a-agent-gateway-agentcore.md](../3-a2a-agent-gateway-agentcore.md).
- [ ] `step3-a2a/03-konnect-a2a-route.png`: **Konnect** → Gateway Manager → `kong-aws` → Routes, showing `a2a-route` (path `/a2a`) with the **ai-a2a-proxy** plugin enabled. Used in [3-a2a-agent-gateway-agentcore.md](../3-a2a-agent-gateway-agentcore.md) and the [README](../README.md).
- [ ] `step5-identity/02-kong-identity-auth-server.png`: **Konnect** → Identity → authorization server `AuthZ_Server_1`, showing client `client1`, scope `scope1` and claim `claim1`. Used (as a live `<img>` tag) in [5-kong-identity-oauth2.md](../5-kong-identity-oauth2.md) and in the [README](../README.md).

## Diagrams referenced but not yet in the repo

The docs point to these, but the files aren't in the repo yet, so they show as broken images until they're added. Get them from the guide's author rather than redrawing them from guesswork.

- [ ] `step4-mcp/02-development-time.png`: "development time" architecture with the Kong Mocking plugin. Used in [4-mcp-gateway.md](../4-mcp-gateway.md).
- [ ] `step5-identity/01-architecture2.png`: "new architecture" for the production-time Kong Identity setup. Used in [5-kong-identity-oauth2.md](../5-kong-identity-oauth2.md).
