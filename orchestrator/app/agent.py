"""搭图 Agent:Claude tool-use 手动循环。

流程(docs/agent-system.md §2):选配方 → 填参 → validate(对照 /object_info)→ run。
人和 Agent 走同一套 op(此处即四个工具);M1 只验「Agent 搭图」本身是否可靠。
"""
from __future__ import annotations

from typing import Callable

import anthropic

from .config import settings
from . import tools

SYSTEM = """你是 ReelForge 的「搭图 Agent」。目标:把用户的自然语言意图变成一张能在 ComfyUI 跑通的图,并出图。

按这个流程做:
1. search_recipes 选一个合适的配方。
2. instantiate_recipe 用参数实例化为当前图(把用户意图翻成 prompt、分辨率、步数等参数)。
3. validate 对照 ComfyUI /object_info 校验。有错就改参数或换配方后重试,直到通过。
4. validate 通过后 run 执行,取回产物。

信息不足(如分辨率、写实/二次元)时可简要澄清,但能合理默认就别多问。
完成后用中文简述:你选了什么配方、关键参数、产物在哪。"""


def run_agent(
    user_message: str,
    ctx: tools.Context,
    on_event: Callable[[dict], None] | None = None,
    max_iters: int = 12,
) -> tuple[str, tools.Context]:
    client = anthropic.Anthropic()  # 读取环境变量 ANTHROPIC_API_KEY
    messages: list[dict] = [{"role": "user", "content": user_message}]

    for _ in range(max_iters):
        resp = client.messages.create(
            model=settings.model,
            max_tokens=16000,
            thinking={"type": "adaptive"},
            system=SYSTEM,
            tools=tools.TOOL_SCHEMAS,
            messages=messages,
        )
        # 把助手回合原样追加(含 thinking 块,顺序不能改)
        messages.append({"role": "assistant", "content": resp.content})

        if resp.stop_reason != "tool_use":
            text = "".join(b.text for b in resp.content if b.type == "text")
            return text, ctx

        tool_results = []
        for block in resp.content:
            if block.type != "tool_use":
                continue
            if on_event:
                on_event({"type": "tool_call", "tool": block.name, "args": block.input})
            try:
                out = tools.dispatch(block.name, block.input, ctx)
                is_error = False
            except Exception as e:  # 工具失败也要回填,让 Agent 自愈
                out, is_error = f"Error: {e}", True
            if on_event:
                on_event({"type": "tool_result", "tool": block.name, "result": out})
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": block.id,
                "content": out,
                "is_error": is_error,
            })
        messages.append({"role": "user", "content": tool_results})

    return "(已达最大迭代次数,未完成)", ctx
