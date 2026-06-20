"""M1 一键自检(命令行):自然语言 → 选配方 → validate → 出图。

  cd orchestrator
  python -m scripts.run_m1 "25岁亚洲女性,齐肩黑发,红色风衣,电影感打光,写实定稿图"

必须在能访问 5090 的内网运行,且已 export ANTHROPIC_API_KEY。
"""
from __future__ import annotations

import sys

from app.agent import run_agent
from app.comfy import ComfyClient
from app.config import settings
from app.recipes import RecipeRegistry
from app.store import ProjectStore
from app.tools import Context

DEFAULT = "生成一个25岁亚洲女性,齐肩黑发,红色风衣,电影感打光,写实人物定稿图"


def main() -> None:
    prompt = " ".join(sys.argv[1:]).strip() or DEFAULT
    ctx = Context(ComfyClient(), RecipeRegistry(), ProjectStore(settings.projects_dir))

    def ev(e: dict) -> None:
        if e["type"] == "tool_call":
            print(f"  → {e['tool']}({e['args']})", flush=True)
        else:
            print(f"  ← {e['tool']}: {e['result'][:200]}", flush=True)

    print(f"ComfyUI: {settings.comfy_url} · model: {settings.model}\n意图: {prompt}\n")
    text, _ = run_agent(prompt, ctx, on_event=ev)
    print("\n=== Agent ===\n" + text)


if __name__ == "__main__":
    main()
