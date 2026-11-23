"""Step 7: an inventory agent that uses the model and the tools through Kong.

Every call this agent makes goes through the Kong AI Gateway:
  - the model:  https://<KONG_URL>/v1   (the nova-micro Model from Step 6)
  - the tools:  https://<KONG_URL>/mcp  (the inventory-tools MCP Server from Steps 4 and 7)
It gets a Kong Identity token (Step 5) and sends it on both, just like any other client.

Environment variables (set in agentcore/agentcore.json under envVars):
  KONG_URL          https://ai-dp.<your domain>
  ISSUER_URL        the Kong Identity issuer URL from Step 5
  AGENT_SECRET_ARN  the Secrets Manager secret that holds the Kong Identity client_id and client_secret

The client secret itself is never in an environment variable. The agent reads it from
Secrets Manager with its execution role, which may read only that one secret.
"""

import json
import os
import time

import boto3
import httpx
from bedrock_agentcore.runtime import serve_a2a
from mcp.client.streamable_http import streamablehttp_client
from strands import Agent
from strands.models.openai import OpenAIModel
from strands.multiagent.a2a.executor import StrandsA2AExecutor
from strands.tools.mcp import MCPClient

KONG_URL = os.environ["KONG_URL"].rstrip("/")
ISSUER_URL = os.environ["ISSUER_URL"].rstrip("/")
AGENT_SECRET_ARN = os.environ["AGENT_SECRET_ARN"]

SYSTEM_PROMPT = """
You are the inventory assistant for a small online store.
Use the check_inventory tool to look up stock for a SKU, and the list_orders tool to see orders.
Always call a tool before answering a question about stock or orders. Never guess numbers.
Answer in one or two short sentences.
"""

_token = {"value": None, "expires_at": 0.0}
_client = {}


def get_client_credentials() -> dict:
    """Read the Kong Identity client ID and secret from Secrets Manager, once per process."""
    if not _client:
        region = AGENT_SECRET_ARN.split(":")[3]
        secret = boto3.client("secretsmanager", region_name=region).get_secret_value(SecretId=AGENT_SECRET_ARN)
        _client.update(json.loads(secret["SecretString"]))
        print("[inventory-agent] read the Kong Identity client from Secrets Manager", flush=True)
    return _client


def get_token() -> str:
    """Get a Kong Identity access token with the client credentials grant, and reuse it until it nearly expires."""
    if _token["value"] and time.time() < _token["expires_at"] - 60:
        return _token["value"]
    client = get_client_credentials()
    response = httpx.post(
        f"{ISSUER_URL}/oauth/token",
        data={
            "grant_type": "client_credentials",
            "client_id": client["client_id"],
            "client_secret": client["client_secret"],
            "scope": "scope1",
        },
        timeout=10,
    )
    response.raise_for_status()
    body = response.json()
    _token["value"] = body["access_token"]
    _token["expires_at"] = time.time() + int(body.get("expires_in", 300))
    print("[inventory-agent] got a new Kong Identity token", flush=True)
    return _token["value"]


def create_agent(context_id: str) -> Agent:
    token = get_token()

    # The model: Kong's OpenAI-compatible endpoint. The OpenAI client sends the
    # api_key as "Authorization: Bearer <token>", which is what Kong checks.
    model = OpenAIModel(
        client_args={"api_key": token, "base_url": f"{KONG_URL}/v1"},
        model_id="nova-micro",
        # Nova calls tools most reliably with temperature 0 (see the Nova tool-use troubleshooting guide).
        params={"max_tokens": 1000, "temperature": 0},
    )

    # The tools: Kong's MCP endpoint, with the same token.
    tools = MCPClient(
        lambda: streamablehttp_client(
            url=f"{KONG_URL}/mcp",
            headers={"Authorization": f"Bearer {token}"},
        )
    )

    return Agent(
        name="inventory-agent",
        description="Answers questions about stock and orders, using tools and a model through Kong AI Gateway.",
        model=model,
        system_prompt=SYSTEM_PROMPT,
        tools=[tools],
    )


# serve_a2a binds 0.0.0.0:9000 in the container (the AgentCore A2A contract)
# and publishes the agent card at /.well-known/agent-card.json.
if __name__ == "__main__":
    serve_a2a(StrandsA2AExecutor(agent_factory=create_agent))
