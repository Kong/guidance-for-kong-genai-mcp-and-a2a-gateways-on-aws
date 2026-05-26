import asyncio
import httpx
from a2a.client import A2ACardResolver, ClientFactory, ClientConfig
from a2a.types import (
    Message,
    Part,
    TextPart,
    Role,
    TransportProtocol,
)

from uuid import uuid4



async def main():
    base_url = 'http://kong-dp.kong-demo.com/a2a'

    async with httpx.AsyncClient(timeout=60.0 ) as httpx_client:
        # 1. Resolve the agent card
        resolver = A2ACardResolver(
            httpx_client=httpx_client,
            base_url=base_url,
        )
        agent_card = await resolver.get_agent_card()
        print("----- Agent Card -----")
        print(agent_card.model_dump_json(indent=2))
        print("----- Agent Card -----")

        # 2. Create client via ClientFactory
        factory = ClientFactory(
            ClientConfig(
                supported_transports=[TransportProtocol.jsonrpc],
                use_client_preference=True,
                httpx_client=httpx_client,
            )
        )
        client = factory.create(agent_card)

        # 3. Send Messages
        print("\nAgent ready. Type 'quit' to exit.\n")
        while True:
            try:
                prompt = input("User: ")
            except (EOFError, KeyboardInterrupt):
                break
            if prompt.strip().lower() in ("quit", "exit"):
                break
            message = Message(
                role=Role.user,
                parts=[Part(root=TextPart(text=prompt))],
                messageId=str(uuid4()),
            )

            async for event in client.send_message(message):
                if isinstance(event, Message):
                    for part in event.parts:
                        print(part.root.text)
                else:
                    task, update = event
                    print(task)



asyncio.run(main())