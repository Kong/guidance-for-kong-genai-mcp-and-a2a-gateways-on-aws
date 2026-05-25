import uuid
import uvicorn

from starlette.applications import Starlette


from a2a.server.agent_execution import AgentExecutor
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore
from a2a.server.routes.agent_card_routes import create_agent_card_routes
from a2a.server.routes.jsonrpc_routes import create_jsonrpc_routes

from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentSkill,
    # TaskArtifactUpdateEvent,
    TaskState,
)

from a2a.server.tasks import TaskUpdater
from a2a.helpers import new_text_artifact, new_task


class HelloWorldAgentExecutor(AgentExecutor):
    async def execute(self, context, event_queue): # -> None:
        # message/send and message/stream both arrive here

        # A2A separates task lifecycle from task output.
        # 1. announce task exists / started
        task = context.current_task
        if task is None:
            task = new_task(
                task_id=context.task_id or str(uuid.uuid4()),
                context_id=context.context_id or str(uuid.uuid4()),
                state=TaskState.TASK_STATE_SUBMITTED,
                # state=TaskState.TASK_STATE_COMPLETED,
                history=[context.message] if context.message else None,
        )
        await event_queue.enqueue_event(task)
        updater = TaskUpdater(event_queue, task.id, task.context_id)

        # 2. task output event (task produced content)
        result = "that's the response"
        await updater.add_artifact(
            parts=new_text_artifact(
                name="result",
                text="that's the response",
            ).parts,
            name="result",
        )
        await updater.complete()


    async def cancel(self, context, event_queue): # -> None:
        raise Exception('cancel not supported')
        


if __name__ == '__main__':
    skill = AgentSkill(
        id='hello_world',
        name='Returns hello world',
        description='just returns hello world',
        tags=['hello world'],
        examples=['hi', 'hello world'],
    )

    agent_card = AgentCard(
        name='Hello World Agent',
        description='Just a hello world agent',
        version='1.0.0',
        icon_url='http://localhost:9999/icon.png',
        supported_interfaces=[
            AgentInterface(
                url='http://localhost:9999/a2a',
                protocol_binding='JSONRPC',
                # protocol_version='0.3',
                protocol_version='1.0',
            ),
        ],
        default_input_modes=['text'],
        default_output_modes=['text'],
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
            rpc_url='/a2a',
            enable_v0_3_compat=True,
        ),
    ]

    app = Starlette(routes=routes)
    uvicorn.run(app, host='0.0.0.0', port=9999)