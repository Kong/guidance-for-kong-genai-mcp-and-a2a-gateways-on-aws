import importlib.metadata; print("A2A SDK version:", importlib.metadata.version('a2a-sdk'))

import json
import uuid
import uvicorn

from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware

from a2a.server.agent_execution import AgentExecutor
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore, TaskUpdater
from a2a.server.routes.agent_card_routes import create_agent_card_routes
from a2a.server.routes.jsonrpc_routes import create_jsonrpc_routes

from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
    TaskState,
)
from a2a.helpers import new_text_artifact, new_task


# ---------------------------------------------------------------------------
# Middleware: log all incoming headers
# ---------------------------------------------------------------------------
class LogHeaders(BaseHTTPMiddleware):
    def __init__(self, app, label="headers"):
        super().__init__(app)
        self.label = label

    async def dispatch(self, request, call_next):
        print(f"==== {self.label} ====", flush=True)
        for k, v in request.headers.items():
            print(f"  {k}: {v}", flush=True)
        print(f"==== end {self.label} ====", flush=True)
        return await call_next(request)


# ---------------------------------------------------------------------------
# Middleware: infer the A2A protocol version from the request body and set
# the A2A-Version header so the version validator always passes.
# Supports both v0.3 (method names like "message/send") and v1.0 ("SendMessage")
# clients without requiring them to set any header.
# ---------------------------------------------------------------------------
class NormalizeVersion(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        body = await request.body()

        version = "1.0"  # default
        if body:
            try:
                payload = json.loads(body)
                method = payload.get("method", "")
                # v0.3 methods are slash-style; v1.0 methods are PascalCase
                if "/" in method:
                    version = "0.3"
            except Exception:
                pass

        # Replace any client-provided A2A-Version with the inferred one
        new_headers = [
            (k, v) for k, v in request.scope["headers"]
            if k.lower() != b"a2a-version"
        ]
        new_headers.append((b"a2a-version", version.encode()))
        request.scope["headers"] = new_headers

        # Replay the body since we consumed it
        async def receive():
            return {"type": "http.request", "body": body, "more_body": False}

        request._receive = receive

        print(f"[NormalizeVersion] method-style → A2A-Version: {version}", flush=True)
        return await call_next(request)


# ---------------------------------------------------------------------------
# Agent executor
# ---------------------------------------------------------------------------
class HelloWorldAgentExecutor(AgentExecutor):
    async def execute(self, context, event_queue):
        task = context.current_task
        if task is None:
            task = new_task(
                task_id=context.task_id or str(uuid.uuid4()),
                context_id=context.context_id or str(uuid.uuid4()),
                state=TaskState.TASK_STATE_SUBMITTED,
                history=[context.message] if context.message else None,
            )
        await event_queue.enqueue_event(task)
        updater = TaskUpdater(event_queue, task.id, task.context_id)

        await updater.add_artifact(
            parts=new_text_artifact(
                name="result",
                text="that's the response",
            ).parts,
            name="result",
        )
        await updater.complete()

    async def cancel(self, context, event_queue):
        raise Exception("cancel not supported")


# ---------------------------------------------------------------------------
# Build the app
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    skill = AgentSkill(
        id="hello_world",
        name="Returns hello world",
        description="just returns hello world",
        tags=["hello world"],
        examples=["hi", "hello world"],
    )

    agent_card = AgentCard(
        name="Hello World Agent",
        description="Just a hello world agent",
        version="1.0.0",
        icon_url="http://localhost:9000/icon.png",
        supported_interfaces=[
            AgentInterface(
                url="http://localhost:9000/",
                protocol_binding="JSONRPC",
                protocol_version="1.0",
            ),
        ],
        default_input_modes=["text"],
        default_output_modes=["text"],
        capabilities=AgentCapabilities(streaming=True),
        skills=[skill],
    )

    request_handler = DefaultRequestHandler(
        agent_card=agent_card,
        agent_executor=HelloWorldAgentExecutor(),
        task_store=InMemoryTaskStore(),
    )

    routes = [
        *create_agent_card_routes(agent_card=agent_card),
        *create_jsonrpc_routes(
            request_handler=request_handler,
            rpc_url="/",
            enable_v0_3_compat=True,  # accept both message/send (v0.3) and SendMessage (v1.0)
        ),
    ]

    app = Starlette(
        routes=routes,
        middleware=[
            Middleware(LogHeaders, label="incoming headers (from client)"),
            Middleware(NormalizeVersion),
            Middleware(LogHeaders, label="headers after NormalizeVersion"),
        ],
    )

    uvicorn.run(app, host="0.0.0.0", port=9000)