"""FastAPI 入口(M1 最小版)。

  uvicorn app.main:app --reload --port 8000

注:api-contract.md 的 /chat 规定 SSE 流式;此骨架先用同步 JSON 返回(含事件列表),
SSE 留作 TODO。
"""
from __future__ import annotations

from fastapi import FastAPI
from pydantic import BaseModel

from .agent import run_agent
from .comfy import ComfyClient
from .config import settings
from .recipes import RecipeRegistry
from .store import ProjectStore
from .tools import Context

app = FastAPI(title="ReelForge Orchestrator (M1)")

# 进程级单例(配方库与 /object_info 缓存可复用)
_recipes = RecipeRegistry()


class ChatIn(BaseModel):
    message: str
    project: str = "demo"


@app.get("/healthz")
def healthz():
    return {"ok": True, "comfy": settings.comfy_url, "model": settings.model,
            "recipes": list(_recipes.recipes)}


@app.post("/chat")
def chat(body: ChatIn):
    ctx = Context(ComfyClient(), _recipes, ProjectStore(settings.projects_dir, body.project))
    events: list[dict] = []
    text, _ = run_agent(body.message, ctx, on_event=events.append)
    return {"message": text, "events": events, "graph": ctx.graph}
