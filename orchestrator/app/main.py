"""FastAPI 入口(阶段4 API 收口)。

  uvicorn app.main:app --reload --port 8000

提供:健康检查 / 后端 / 配方 / object_info / 项目+分镜 / 校验+执行 / 成片 / op 协同 / 导出。
对应 api-contract.md;/chat 与 /films 暂用同步 JSON,SSE 留作 TODO。
人与 Agent 经同一套 op(/ops)改同一份 Graph IR,无特权写路径。
"""
from __future__ import annotations

import os

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

from .agent import make_client, run_agent
from .backends import BackendRegistry
from .comfy import ComfyClient
from .config import settings
from .director import produce_film
from .export import export_project
from .ops import apply_ops
from .recipes import RecipeRegistry
from .store import ProjectStore
from .tools import Context, run_ir, validate_ir

app = FastAPI(title="ReelForge Orchestrator")

_recipes = RecipeRegistry()
_registry = BackendRegistry()
_comfy = ComfyClient()  # 默认 5090(交互),校验/直接执行用


def _store(name: str) -> ProjectStore:
    return ProjectStore(settings.projects_dir, name)


# ---- 元信息 ----
@app.get("/healthz")
def healthz():
    return {"ok": True, "model": settings.model, "recipes": list(_recipes.recipes),
            "backends": [b["name"] for b in _registry.list()]}


@app.get("/backends")
def backends():
    return {"backends": _registry.list()}


@app.get("/recipes")
def recipes():
    return {"recipes": _recipes.search("")}


@app.get("/object_info")
def object_info():
    return _comfy.object_info()


# ---- 项目 / 分镜 ----
class ProjectIn(BaseModel):
    name: str


@app.post("/projects")
def create_project(body: ProjectIn):
    _store(body.name)
    return {"ok": True, "project": body.name}


@app.get("/projects/{name}")
def get_project(name: str):
    return _store(name).load()


@app.get("/projects/{name}/shots")
def get_shots(name: str):
    return {"shots": _store(name).load().get("shots", [])}


# ---- 校验 / 执行 ----
class GraphIn(BaseModel):
    graph: dict
    project: str = "demo"


@app.post("/graphs/validate")
def graph_validate(body: GraphIn):
    errors = validate_ir(body.graph, _comfy.object_info())
    return {"ok": not errors, "errors": errors}


@app.post("/graphs/run")
def graph_run(body: GraphIn):
    return run_ir(body.graph, _comfy, _store(body.project))


# ---- 成片(导演 Agent:剧本→多镜头) ----
class FilmIn(BaseModel):
    project: str = "demo"
    character_image: str
    character_desc: str
    script: str
    n_shots: int = 3
    assets: list[dict] | None = None


@app.post("/films")
def make_film(body: FilmIn):
    if not settings.model:
        raise HTTPException(400, "未设 AGENT_MODEL")
    client = make_client()
    res = produce_film(_registry, _recipes, _store(body.project), body.character_image,
                       body.character_desc, body.script, client, settings.model,
                       n_shots=body.n_shots, assets=body.assets)
    return res


# ---- op 协同(人/Agent 同构改 IR) ----
class OpsIn(BaseModel):
    project: str = "demo"
    shot_id: str
    ops: list[dict]
    check: bool = True  # 应用后是否对照 /object_info 校验


@app.post("/projects/{name}/shots/{shot_id}/ops")
def shot_ops(name: str, shot_id: str, body: OpsIn):
    store = _store(name)
    doc = store.load()
    shot = next((s for s in doc["shots"] if s["id"] == shot_id), None)
    if shot is None:
        raise HTTPException(404, f"未知镜头 {shot_id}")
    ir = shot.get("graph") or {"nodes": {}}
    new_ir = apply_ops(ir, body.ops)
    errors = validate_ir(new_ir, _comfy.object_info()) if body.check else []
    if errors:
        return {"ok": False, "errors": errors, "graph": new_ir}
    shot["graph"] = new_ir
    store._write(doc)
    return {"ok": True, "graph": new_ir}


# ---- 选片 ----
class SelectIn(BaseModel):
    take_id: str


@app.post("/projects/{name}/shots/{shot_id}/select")
def select_take(name: str, shot_id: str, body: SelectIn):
    store = _store(name)
    try:
        store.select_take(shot_id, body.take_id)
    except KeyError as e:
        raise HTTPException(404, str(e))
    return {"ok": True, "shot": shot_id, "selected_take": body.take_id}


# ---- 云接入状态(阶段6) ----
@app.get("/cloud/status")
def cloud_status():
    from .cloud import load_providers
    provs = load_providers()
    return {"direct_providers": {n: p.configured for n, p in provs.items()},
            "partner_note": "Kling/Vidu/Runway/Luma/Veo 等 partner 节点的 key 配在 ComfyUI,"
                            "作 i2v_cloud 配方经 run_ir 调用(无需本服务 endpoint)"}


# ---- 媒体服务(给客户端显示关键帧/视频;限项目目录内,防穿越) ----
@app.get("/media")
def media(path: str):
    base = os.path.abspath(settings.projects_dir)
    full = os.path.abspath(path) if os.path.isabs(path) else os.path.abspath(os.path.join(os.getcwd(), path))
    if not full.startswith(base) or not os.path.isfile(full):
        raise HTTPException(404, "media not found")
    return FileResponse(full)


# ---- 导出工程(有序片段 + FCPXML) ----
@app.post("/projects/{name}/export")
def export(name: str):
    return export_project(_store(name))


# ---- Agent 对话(M1 四工具循环) ----
class ChatIn(BaseModel):
    message: str
    project: str = "demo"


@app.post("/chat")
def chat(body: ChatIn):
    ctx = Context(ComfyClient(), _recipes, _store(body.project))
    events: list[dict] = []
    text, _ = run_agent(body.message, ctx, on_event=events.append)
    return {"message": text, "events": events, "graph": ctx.graph}
