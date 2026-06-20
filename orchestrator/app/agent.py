"""搭图 Agent：tool-use 手动循环（经 LiteLLM 网关，OpenAI 兼容）。

流程(docs/agent-system.md §2)：选配方 → 填参 → validate(对照 /object_info)→ run。
人和 Agent 走同一套 op(此处即四个工具)；M1 只验「Agent 搭图」本身是否可靠。

模型经 LiteLLM 网关(10.10.10.5:4000)调用，底层模型可自由替换；用 OpenAI SDK，
base_url / api_key 显式传入，绝不改全局 ANTHROPIC_*（不影响同机的 Claude Code）。
tools.TOOL_SCHEMAS 是工具定义的单一来源(Anthropic 风格)，这里转成 OpenAI function 格式。
"""
from __future__ import annotations

import json
from typing import Callable

from openai import OpenAI

from .config import settings
from . import tools

SYSTEM = """你是 ReelForge 的「搭图 Agent」。目标:把用户的自然语言意图变成一张能在 ComfyUI 跑通的图,并出图。

按这个流程做:
1. search_recipes 选一个合适的配方。
2. instantiate_recipe 用参数实例化为当前图(把用户意图翻成 prompt、分辨率、步数等参数;prompt 用高质量英文)。
3. 需要时用图编辑原语局部改图:set_param(改某节点参数)、add_node、connect、delete_node。
   每次改图都带 rationale 说明「为什么这么搭/调」。优先改配方暴露的参数,不要凭空发明拓扑。
4. estimate 预估耗时/费用(尤其视频或云任务,先看一眼)。
5. validate 对照 ComfyUI /object_info 校验。有错就改参数或换配方后重试,直到通过。
6. validate 通过后 run 执行,取回产物。
**重要**:若用户要的是创建一个**资产**(角色/服装/道具/场景/风格,如"生成一个角色"),
直接调 **create_asset(atype, name, prompt)** 一步完成:它会在当前项目里先建出该资产(立刻进左侧树)、
挂好生成流程、执行、把产物回填为预览。**不要**用 search_recipes/instantiate/run 那套散图流程去做资产。
上面的 1–6 步(配方→改图→run)用于非资产的临时出图或在技术层精修已有流程。

信息不足(如分辨率、写实/二次元)时可简要澄清,但能合理默认就别多问。
你与人编辑的是同一份图(同一套 op,无特权);完成后用中文简述:配方、关键参数、为什么这么搭、产物在哪。"""


def _openai_tools() -> list[dict]:
    """Anthropic 风格工具 schema → OpenAI function-tool 格式。"""
    return [
        {
            "type": "function",
            "function": {
                "name": t["name"],
                "description": t["description"],
                "parameters": t["input_schema"],
            },
        }
        for t in tools.TOOL_SCHEMAS
    ]


def make_client() -> OpenAI:
    """指向 LiteLLM 的 OpenAI client（显式传参，不读/不改全局 ANTHROPIC_*）。"""
    if not settings.litellm_api_key:
        raise RuntimeError("缺少 LITELLM_API_KEY（LiteLLM 网关 key）")
    return OpenAI(
        base_url=settings.litellm_base_url.rstrip("/") + "/v1",
        api_key=settings.litellm_api_key,
    )


def list_models(client: OpenAI | None = None) -> list[str]:
    client = client or make_client()
    return [m.id for m in client.models.list().data]


def run_agent(
    user_message: str,
    ctx: tools.Context,
    on_event: Callable[[dict], None] | None = None,
    max_iters: int = 12,
) -> tuple[str, tools.Context]:
    if not settings.model:
        raise RuntimeError("缺少 AGENT_MODEL（要使用的 LiteLLM 模型名，见 list_models）")
    client = make_client()
    openai_tools = _openai_tools()
    messages: list[dict] = [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": user_message},
    ]

    for _ in range(max_iters):
        resp = client.chat.completions.create(
            model=settings.model,
            max_tokens=16000,
            tools=openai_tools,
            tool_choice="auto",
            messages=messages,
        )
        msg = resp.choices[0].message
        tool_calls = msg.tool_calls or []

        # 原样追加助手回合(含 tool_calls)
        assistant: dict = {"role": "assistant", "content": msg.content or ""}
        if tool_calls:
            assistant["tool_calls"] = [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {"name": tc.function.name, "arguments": tc.function.arguments},
                }
                for tc in tool_calls
            ]
        messages.append(assistant)

        if not tool_calls:
            return msg.content or "", ctx

        for tc in tool_calls:
            name = tc.function.name
            try:
                args = json.loads(tc.function.arguments or "{}")
            except json.JSONDecodeError:
                args = {}
            if on_event:
                on_event({"type": "tool_call", "tool": name, "args": args})
            try:
                out = tools.dispatch(name, args, ctx)
            except Exception as e:  # 工具失败也回填，让 Agent 自愈
                out = f"Error: {e}"
            if on_event:
                on_event({"type": "tool_result", "tool": name, "result": out})
            messages.append(
                {"role": "tool", "tool_call_id": tc.id, "content": out}
            )

    return "(已达最大迭代次数,未完成)", ctx
