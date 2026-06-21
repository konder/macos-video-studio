"""FastAPI 入口(阶段4 API 收口)。

  uvicorn app.main:app --reload --port 8000

提供:健康检查 / 后端 / 配方 / object_info / 项目+分镜 / 校验+执行 / 成片 / op 协同 / 导出。
对应 api-contract.md;/chat 与 /films 暂用同步 JSON,SSE 留作 TODO。
人与 Agent 经同一套 op(/ops)改同一份 Graph IR,无特权写路径。
"""
from __future__ import annotations

import asyncio
import json
import os
import queue
import random
import threading
import time
import urllib.parse
import urllib.request

from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from .agent import make_client, run_agent
from .backends import BackendRegistry
from .comfy import ComfyClient
from .config import settings
from .director import produce_film
from .estimate import estimate as estimate_task
from .export import export_project
from .jobs import JOBS
from .ops import OpError, apply_project_ops, record_change
from .recipes import RecipeRegistry
from .store import ProjectStore, _nid
from .tools import Context, run_ir, validate_ir

app = FastAPI(title="ReelForge Orchestrator")

# Web 客户端(零构建 SPA,同源免 CORS):浏览器开 http://<host>:8000/app/
_WEB_DIR = os.path.join(os.path.dirname(__file__), "web")
if os.path.isdir(_WEB_DIR):
    app.mount("/app", StaticFiles(directory=_WEB_DIR, html=True), name="web")

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


@app.get("/projects")
def list_projects():
    base = settings.projects_dir
    names: list[str] = []
    if os.path.isdir(base):
        for n in sorted(os.listdir(base)):
            if os.path.isfile(os.path.join(base, n, "project.json")):
                names.append(n)
    return {"projects": names}


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
    """直接跑一张图 IR → 异步作业(契约:run 返回 job_id)。"""
    jid = JOBS.create("graph", body.project, total=1, message="提交执行…")

    def work():
        JOBS.update(jid, status="running")
        try:
            res = run_ir(body.graph, _comfy, _store(body.project))
            if res.get("error"):
                JOBS.update(jid, status="error", error=str(res["error"]), message="执行出错")
            else:
                JOBS.update(jid, status="done", result=res, message="完成")
        except Exception as e:  # noqa: BLE001
            JOBS.update(jid, status="error", error=str(e), message=f"失败: {e}")

    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "job_id": jid}


# ---- 预估(耗时/费用,费用闸用) ----
class EstimateIn(BaseModel):
    task: str = "i2v_local"
    backend: str = "local-5090"
    duration: int = 5


@app.post("/graphs/estimate")
def graph_estimate(body: EstimateIn):
    return estimate_task(body.task, body.backend, body.duration)


# ---- 单镜头生成(本地/云,带费用闸:云需先确认估算) ----
class GenerateIn(BaseModel):
    backend: str = "local"      # local | cloud
    confirm: bool = False       # 云调用须 confirm=True(已看过估算)


@app.post("/projects/{name}/shots/{shot_id}/generate")
def generate_shot(name: str, shot_id: str, body: GenerateIn):
    """从关键帧生成视频 take。云后端先返回估算等确认(confirm=False),确认后才跑并计费。"""
    store = _store(name)
    doc = store.load()
    shot = next((s for s in doc.get("shots", []) if s["id"] == shot_id), None)
    if shot is None:
        raise HTTPException(404, f"未知镜头 {shot_id}")
    if not shot.get("keyframe"):
        raise HTTPException(400, "该镜头还没有关键帧,无法生成视频")
    is_cloud = body.backend == "cloud"
    est = estimate_task("i2v_local", "cloud-volcano" if is_cloud else "local-5090")
    if is_cloud and not body.confirm:
        return {"needs_confirm": True, "estimate": est}   # 费用闸:先确认

    jid = JOBS.create("i2v", name, total=1, message="生成视频…")
    motion = shot.get("motion_prompt") or "the subject moves naturally, gentle camera motion"
    keyframe = shot["keyframe"]

    def work():
        JOBS.update(jid, status="running")
        try:
            if is_cloud:
                base = os.environ.get("PUBLIC_MEDIA_BASE", "")
                if not base:
                    raise RuntimeError("云生成需公网图床:设 PUBLIC_MEDIA_BASE(关键帧须外部可达)")
                from .cloud import get_volcano
                kf_url = base.rstrip("/") + "/media?path=" + urllib.parse.quote(keyframe, safe="")
                out = get_volcano().i2v(kf_url, motion, duration=5)
                vid = urllib.request.urlopen(out["video_url"], timeout=180).read()
                path = store.save_asset(vid, f"{shot_id}_cloud_{int(time.time())}.mp4")
                JOBS.add_cost(jid, est["cost"])
                d = store.load()
                record_change(d, [{"op": "add_take", "shot": shot_id, "take": _nid("take"),
                                   "video": path, "meta": {"backend": "cloud-volcano",
                                   "recipe": "seedance-i2v", "cost": est["cost"]}}],
                              author="agent", rationale="云生成 take")
                total = round(float((d.get("meta") or {}).get("cost_total", 0)) + est["cost"], 2)
                record_change(d, [{"op": "set_meta", "key": "cost_total", "value": total}],
                              author="agent", rationale=f"云计费 ¥{est['cost']}")
                # data-model:云任务在 IR 用虚拟节点表示(由云适配器解释执行,不进 ComfyUI 图)
                ds = next((s for s in d["shots"] if s["id"] == shot_id), None)
                if ds is not None:
                    ds["graph"] = {"nodes": {"cloud1": {"class_type": "CloudVideo", "inputs": {
                        "provider": "volcano", "model": os.environ.get("VOLCANO_MODEL", "doubao-seedance-1.5-pro"),
                        "image": keyframe, "prompt": motion, "duration": 5,
                        "task_id": out.get("task_id"), "video_url": out.get("video_url")},
                        "pos": [80, 80]}}}
                d["history"][-1]["ts"] = time.time()
                store._write(d)
            else:
                comfy = _registry.route("i2v").client
                from .pipeline import _upload
                iv = _upload(comfy, keyframe)
                ir = _recipes.instantiate("i2v_local", {"input_image": iv, "seed": 42,
                                          "motion_prompt": motion, "filename_prefix": f"{shot_id}_take"})
                errs = validate_ir(ir, comfy.object_info())
                if errs:
                    raise RuntimeError(str(errs))
                res = run_ir(ir, comfy, store)
                if not res.get("assets"):
                    raise RuntimeError(res.get("error", "i2v 无产物"))
                d = store.load()
                record_change(d, [{"op": "add_take", "shot": shot_id, "take": _nid("take"),
                                   "video": res["assets"][0], "meta": {"backend": "local-5090",
                                   "recipe": "i2v_local"}}], author="human", rationale="本地生成 take")
                d["history"][-1]["ts"] = time.time()
                store._write(d)
            JOBS.update(jid, status="done", message="完成")
        except Exception as e:  # noqa: BLE001
            JOBS.update(jid, status="error", error=str(e), message=f"失败: {e}")

    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "job_id": jid, "estimate": est}


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
    """成片改为异步作业:立刻返回 job_id,后台线程跑生成,进度写 JOBS(轮询/WS 取回)。"""
    if not settings.model:
        raise HTTPException(400, "未设 AGENT_MODEL")
    jid = JOBS.create("film", body.project, total=body.n_shots, message="导演拆镜中…")

    def work():
        JOBS.update(jid, status="running")
        try:
            client = make_client()
            res = produce_film(_registry, _recipes, _store(body.project), body.character_image,
                               body.character_desc, body.script, client, settings.model,
                               n_shots=body.n_shots, assets=body.assets,
                               on_event=lambda m: JOBS.event(jid, m))
            JOBS.update(jid, status="done", result=res, message="完成")
        except Exception as e:  # noqa: BLE001
            JOBS.update(jid, status="error", error=str(e), message=f"失败: {e}")

    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "job_id": jid}


@app.get("/jobs/{job_id}")
def get_job(job_id: str):
    j = JOBS.get(job_id)
    if not j:
        raise HTTPException(404, f"未知作业 {job_id}")
    return j


@app.websocket("/events")
async def events_ws(ws: WebSocket):
    """事件流:推送本项目作业快照(状态/进度/消息/费用)。无新事件则静默。
    断线后客户端可改用 GET /jobs/{id} 拉回(契约)。节点级 latent 预览需订阅 ComfyUI WS,后续接。"""
    await ws.accept()
    project = ws.query_params.get("project")
    seen: dict[str, float] = {}
    try:
        while True:
            for j in JOBS.list(project):
                if seen.get(j["id"]) != j["updated"]:
                    seen[j["id"]] = j["updated"]
                    await ws.send_json(j)
            await asyncio.sleep(0.5)
    except WebSocketDisconnect:
        pass
    except Exception:  # noqa: BLE001
        pass


# ---- op 协同(人/Agent 同构改 IR) ----
class OpsIn(BaseModel):
    project: str = "demo"
    shot_id: str
    ops: list[dict]
    check: bool = True  # 应用后是否对照 /object_info 校验
    author: str = "human"
    rationale: str = ""


@app.post("/projects/{name}/shots/{shot_id}/ops")
def shot_ops(name: str, shot_id: str, body: OpsIn):
    """镜头级图 op:语法糖,自动给每个 op 注入 shot 字段,走统一历史(record_change)。
    含校验:先在副本上应用+对照 /object_info,通过才落库入历史。"""
    import copy
    store = _store(name)
    doc = store.load()
    if not any(s["id"] == shot_id for s in doc.get("shots", [])):
        raise HTTPException(404, f"未知镜头 {shot_id}")
    ops = [{**op, "shot": shot_id} for op in body.ops]
    try:
        trial = apply_project_ops(copy.deepcopy(doc), ops)
    except OpError as e:
        raise HTTPException(400, str(e))
    new_ir = next(s for s in trial["shots"] if s["id"] == shot_id).get("graph") or {"nodes": {}}
    errors = validate_ir(new_ir, _comfy.object_info()) if body.check else []
    if errors:
        return {"ok": False, "errors": errors, "graph": new_ir}
    change = record_change(doc, ops, author=body.author, rationale=body.rationale)
    change["ts"] = time.time(); doc["history"][-1]["ts"] = change["ts"]
    store._write(doc)
    return {"ok": True, "seq": change["seq"], "graph": new_ir}


# ---- 项目级 op / 统一历史(api-contract.md)----
# 人和 Agent 经同一套 op 改同一份模型,落进同一条历史(单调 seq)。无特权写路径。
class ChangeIn(BaseModel):
    ops: list[dict]
    author: str = "human"           # human | agent
    rationale: str = ""             # 「为什么这么搭」
    tool_call: str | None = None
    check: bool = True              # 含图级 op 时对照 /object_info 校验


@app.post("/projects/{name}/ops")
def project_ops(name: str, body: ChangeIn):
    store = _store(name)
    doc = store.load()
    try:
        change = record_change(doc, body.ops, author=body.author,
                               rationale=body.rationale, tool_call=body.tool_call)
    except OpError as e:
        raise HTTPException(400, str(e))
    change["ts"] = time.time()
    doc["history"][-1]["ts"] = change["ts"]
    store._write(doc)
    return {"ok": True, "seq": change["seq"], "change": change}


@app.post("/projects/{name}/shots/{shot_id}/graph/build")
def build_shot_graph(name: str, shot_id: str, task: str = "keyframe_edit", force: bool = False):
    """技术层:把镜头某任务实例化为 Graph IR 并落库(shot.graph),供节点画布展示/编辑。
    已有 graph 时默认返回现有(保留 op 编辑);force=True 才按配方重建。
    task=keyframe_edit(生成关键帧)| i2v_local(关键帧→视频)。"""
    store = _store(name)
    doc = store.load()
    shot = next((s for s in doc["shots"] if s["id"] == shot_id), None)
    if shot is None:
        raise HTTPException(404, f"未知镜头 {shot_id}")
    if shot.get("graph") and not force:
        return {"ok": True, "task": task, "graph": shot["graph"]}
    refs = shot.get("refs") or []
    char = next((c for c in doc.get("characters", []) if c["id"] in refs), None)
    img = os.path.basename((char or {}).get("finals", ["input.png"])[0]) if char else "input.png"
    if task == "i2v_local":
        ir = _recipes.instantiate("i2v_local", {
            "input_image": os.path.basename(shot.get("keyframe") or "keyframe.png"),
            "motion_prompt": shot.get("motion_prompt") or "",
            "seed": 42, "filename_prefix": f"{shot_id}_take"})
    else:
        ir = _recipes.instantiate("keyframe_edit", {
            "input_image": img, "prompt": shot.get("scene_prompt") or shot.get("script") or "",
            "seed": 42, "filename_prefix": f"{shot_id}_keyframe"})
    shot["graph"] = ir
    store._write(doc)
    return {"ok": True, "task": task, "graph": ir}


@app.post("/projects/{name}/upload")
async def upload_asset(name: str, request: Request, filename: str = "asset.png"):
    """上传参考图/定稿图到项目 assets/(原始字节 body,免 python-multipart 依赖)。
    返回项目内相对路径,供 create_character/create_asset 的 finals 引用。"""
    data = await request.body()
    if not data:
        raise HTTPException(400, "空文件")
    path = _store(name).save_asset(data, filename)
    return {"ok": True, "path": path}


@app.post("/projects/{name}/undo")
def undo(name: str):
    """撤销最近一个可撤销变更:把它的逆操作作为新变更追加(线性历史,不删已产出 take)。"""
    store = _store(name)
    doc = store.load()
    hist = doc.get("history", [])
    last = next((c for c in reversed(hist) if not c.get("undone")), None)
    if last is None:
        raise HTTPException(400, "没有可撤销的变更")
    if not last.get("undoable") or not last.get("inverse"):
        raise HTTPException(400, f"#{last['seq']} 不可撤销(含已产出 take 或删除)")
    try:
        change = record_change(doc, last["inverse"], author="human", rationale=f"撤销 #{last['seq']}")
    except OpError as e:
        raise HTTPException(400, str(e))
    last["undone"] = True
    change["ts"] = time.time(); doc["history"][-1]["ts"] = change["ts"]
    store._write(doc)
    return {"ok": True, "seq": change["seq"], "undone": last["seq"]}


# ---- 镜头编辑租约(单镜头单 actor 持笔;接管=转移租约)----
LOCKS: dict = {}   # {("project","shot"): {"actor","ts"}}


class LockIn(BaseModel):
    actor: str = "human"   # human | agent


@app.post("/projects/{name}/shots/{shot_id}/lock")
def acquire_lock(name: str, shot_id: str, body: LockIn):
    LOCKS[(name, shot_id)] = {"actor": body.actor, "ts": time.time()}
    return {"ok": True, "shot": shot_id, "actor": body.actor}


@app.delete("/projects/{name}/shots/{shot_id}/lock")
def release_lock(name: str, shot_id: str):
    LOCKS.pop((name, shot_id), None)
    return {"ok": True, "shot": shot_id}


@app.get("/projects/{name}/locks")
def list_locks(name: str):
    return {"locks": {sid: v for (p, sid), v in LOCKS.items() if p == name}}


# ---- 资产生成(模板→实例:文字 / 文字+参考图 → 出图)----
class AssetGenIn(BaseModel):
    atype: str            # character | wardrobe | prop | environment | styleframe
    name: str
    prompt: str
    ref_path: str | None = None   # 项目内参考图路径(已上传);空=纯文生图
    width: int | None = None
    height: int | None = None


@app.post("/projects/{name}/assets/generate")
def generate_asset(name: str, body: AssetGenIn):
    """create-first:先建出资产(入树)→ 执行生成流程(角色=分3次单人全身)→ 回填 finals。"""
    if not body.prompt.strip():
        raise HTTPException(400, "prompt 不能为空")
    from .pipeline import _upload, generate_asset_images
    from .recipes import asset_dims, asset_prompt, asset_view_prompts
    store = _store(name)
    style = (store.load().get("meta") or {}).get("style", "realistic")
    comfy = _registry.route("edit" if body.ref_path else "txt2img").client
    seed = random.randint(1, 2_000_000_000)
    dw, dh = asset_dims(body.atype)
    w, h = body.width or dw, body.height or dh
    is_char = body.atype == "character"
    ref_name = _upload(comfy, body.ref_path) if body.ref_path else None
    # 代表流程图(create-first 展示用):取该类型首视角(或参考编辑图)
    if ref_name:
        repr_ir = _recipes.instantiate("keyframe_edit", {"input_image": ref_name,
                  "prompt": asset_prompt(body.atype, body.prompt, style), "seed": seed,
                  "filename_prefix": f"asset_{body.atype}"})
    else:
        repr_ir = _recipes.instantiate("char_concept", {
            "prompt": asset_view_prompts(body.atype, body.prompt, style)[0][1], "width": w, "height": h, "seed": seed})
    aid = _nid("char" if is_char else body.atype[:4])
    op = {"op": "create_character" if is_char else "create_asset", "id": aid,
          "name": body.name, "prompt": body.prompt, "finals": [], "graph": repr_ir,
          "width": w, "height": h}
    if not is_char:
        op["type"] = body.atype
    d = store.load()
    record_change(d, [op], author="human", rationale=f"新建资产 {body.name}")
    d["history"][-1]["ts"] = time.time()
    store._write(d)

    jid = JOBS.create("asset", name, total=1, message="生成中…")

    def work():
        JOBS.update(jid, status="running")
        try:
            finals, _ = generate_asset_images(comfy, _recipes, store, body.atype, body.prompt, style, w, h, seed, ref_name)
            d2 = store.load()
            field_op = "set_character_field" if is_char else "set_asset_field"
            record_change(d2, [{"op": field_op, "id": aid, "field": "finals", "value": finals}],
                          author="human", rationale="更新资产预览")
            d2["history"][-1]["ts"] = time.time()
            store._write(d2)
            JOBS.update(jid, status="done", message="完成", result={"finals": finals})
        except Exception as e:  # noqa: BLE001
            JOBS.update(jid, status="error", error=str(e), message=f"失败: {e}")

    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "job_id": jid, "asset_id": aid}


class ComposeIn(BaseModel):
    name: str
    asset_ids: list[str]
    prompt: str = ""


@app.post("/projects/{name}/assets/compose")
def compose_asset(name: str, body: ComposeIn):
    """创建人物卡片:把角色三视 + 服装/道具图**拼版**成一张索引卡(供视频生成参考),
    不重新渲染。asset_ids[0]=角色(主体,取其多视图),其余=组件(各取首图)。"""
    store = _store(name)
    doc = store.load()

    def ent_of(aid):
        return next((c for c in doc.get("characters", []) if c["id"] == aid), None) or \
            next((a for a in doc.get("assets", []) if a["id"] == aid), None)
    if not body.asset_ids:
        raise HTTPException(400, "请至少选一个角色")
    char = ent_of(body.asset_ids[0])
    char_finals = (char or {}).get("finals") or []
    if not char_finals:
        raise HTTPException(400, "角色还没有图")
    style = (doc.get("meta") or {}).get("style", "realistic")
    refs = [char_finals[0]]                       # 角色主参考(image1)
    for cid in body.asset_ids[1:]:                # 服装/道具(image2/3,Qwen-edit 至多 3 图)
        f = (ent_of(cid) or {}).get("finals") or []
        if f:
            refs.append(f[0])
    refs = refs[:3]
    aid = _nid("cmps")
    d = store.load()
    record_change(d, [{"op": "create_asset", "id": aid, "type": "composed", "name": body.name,
                       "prompt": body.prompt, "finals": [],
                       "meta": {"composed_from": body.asset_ids}}], author="human", rationale=f"创建人物卡片 {body.name}")
    d["history"][-1]["ts"] = time.time(); store._write(d)

    jid = JOBS.create("card", name, total=1, message="渲染人物卡片…")

    # 设定卡 prompt:角色身份 + 组件 + 版面
    char_desc = (char.get("prompt") or char.get("name") or "a character")
    comp_names = [ (ent_of(c) or {}).get("name", "") for c in body.asset_ids[1:] ]
    comp_descs = [ ((ent_of(c) or {}).get("prompt") or (ent_of(c) or {}).get("name", "")) for c in body.asset_ids[1:] ]
    look = "anime style, clean cel-shaded" if style == "anime" else "photorealistic, realistic"
    equip = ("，装备/穿戴:" + "、".join(filter(None, comp_descs))) if comp_descs else ""
    sheet_prompt = (f"{look} character design sheet / model reference sheet of ONE single character. "
                    f"Character: {char_desc}{equip}. "
                    f"Layout in one image: full-body turnaround (front, side, back views) of the same character; "
                    f"a row of facial expression headshots; separate detail callouts of the equipment, clothing and props. "
                    f"consistent design, clean plain white background, neat professional concept-art sheet layout. {body.prompt}")

    def work():
        JOBS.update(jid, status="running")
        try:
            from .cloud import bailian_image
            from .pipeline import strip_bg
            JOBS.event(jid, "qwen-image-2.0-pro 渲染设定卡…")
            data = bailian_image(sheet_prompt, size="1664*928", model="qwen-image-2.0-pro")
            path = store.save_asset(data, f"card_{aid}.png")
            path = strip_bg(path)
            d2 = store.load()
            record_change(d2, [{"op": "set_asset_field", "id": aid, "field": "finals", "value": [path]}],
                          author="human", rationale="人物卡片完成")
            d2["history"][-1]["ts"] = time.time(); store._write(d2)
            JOBS.update(jid, status="done", message="完成", result={"finals": [path]})
        except Exception as e:  # noqa: BLE001
            JOBS.update(jid, status="error", error=str(e), message=f"失败: {e}")

    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "job_id": jid, "asset_id": aid}


@app.get("/projects/{name}/assets/{asset_id}/graph")
def get_asset_graph(name: str, asset_id: str):
    """取资产/角色的生成流程 IR(技术层节点画布用)。"""
    doc = _store(name).load()
    ent = next((a for a in doc.get("assets", []) if a["id"] == asset_id), None) or \
        next((c for c in doc.get("characters", []) if c["id"] == asset_id), None)
    if ent is None:
        raise HTTPException(404, f"未知资产/角色 {asset_id}")
    return {"ok": True, "graph": ent.get("graph") or {"nodes": {}}}


class RegenIn(BaseModel):
    prompt: str | None = None         # 改词重生成(保存)
    width: int | None = None          # 改尺寸重生成(保存)
    height: int | None = None


@app.post("/projects/{name}/assets/{asset_id}/regenerate")
def regenerate_asset(name: str, asset_id: str, body: RegenIn = RegenIn()):
    """重新出图(角色=分3次单人全身)。可改 prompt / 尺寸并保存。回填 finals(op 入历史)。"""
    from .pipeline import generate_asset_images
    from .recipes import asset_dims
    store = _store(name)
    doc = store.load()
    is_char = False
    ent = next((a for a in doc.get("assets", []) if a["id"] == asset_id), None)
    if ent is None:
        ent = next((c for c in doc.get("characters", []) if c["id"] == asset_id), None)
        is_char = ent is not None
    if ent is None:
        raise HTTPException(404, f"未知资产/角色 {asset_id}")
    atype = "character" if is_char else ent.get("type", "prop")
    style = (doc.get("meta") or {}).get("style", "realistic")
    new_prompt = (body.prompt or "").strip()
    eff_prompt = new_prompt or (ent.get("prompt") or "")
    if not eff_prompt:
        raise HTTPException(400, "该资产没有提示词,无法按词重生成")
    dw, dh = asset_dims(atype)
    w = body.width or ent.get("width") or dw
    h = body.height or ent.get("height") or dh
    seed = random.randint(1, 2_000_000_000)
    jid = JOBS.create("asset", name, total=1, message="重新生成…")

    def work():
        JOBS.update(jid, status="running")
        try:
            comfy = _registry.route("txt2img").client
            finals, repr_graph = generate_asset_images(comfy, _recipes, store, atype, eff_prompt, style, w, h, seed)
            d = store.load()
            e2 = next((a for a in d.get("assets", []) if a["id"] == asset_id), None) or \
                next((c for c in d.get("characters", []) if c["id"] == asset_id), None)
            if e2 is not None:
                e2["graph"] = repr_graph
                e2["width"], e2["height"] = w, h
                if new_prompt:
                    e2["prompt"] = new_prompt
            field_op = "set_character_field" if is_char else "set_asset_field"
            record_change(d, [{"op": field_op, "id": asset_id, "field": "finals", "value": finals}],
                          author="human", rationale="重新生成资产")
            d["history"][-1]["ts"] = time.time()
            store._write(d)
            JOBS.update(jid, status="done", message="完成", result={"finals": finals})
        except Exception as e:  # noqa: BLE001
            JOBS.update(jid, status="error", error=str(e), message=f"失败: {e}")

    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "job_id": jid}


@app.get("/projects/{name}/state")
def project_state(name: str, since: int = 0):
    """断线重连/增量同步:since=0 返回全量 doc;否则返回 seq 之后的变更。"""
    doc = _store(name).load()
    seq = int(doc.get("seq", 0))
    if since <= 0:
        return {"seq": seq, "project": doc}
    changes = [c for c in doc.get("history", []) if c.get("seq", 0) > since]
    return {"seq": seq, "changes": changes}


# ---- 选片 ----
class SelectIn(BaseModel):
    take_id: str


@app.post("/projects/{name}/shots/{shot_id}/select")
def select_take(name: str, shot_id: str, body: SelectIn):
    """选片:走 op + 统一历史(与客户端 /ops 同源,保留此端点为兼容入口)。"""
    store = _store(name)
    doc = store.load()
    try:
        change = record_change(doc, [{"op": "select_take", "shot": shot_id, "take": body.take_id}],
                               author="human", rationale="选用 take")
    except OpError as e:
        raise HTTPException(404, str(e))
    change["ts"] = time.time(); doc["history"][-1]["ts"] = change["ts"]
    store._write(doc)
    return {"ok": True, "shot": shot_id, "selected_take": body.take_id, "seq": change["seq"]}


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
    image: str | None = None        # 粘贴的参考图(项目内路径);附给 Agent 作参考
    history: list[dict] | None = None  # 多轮上下文 [{role, content}]


@app.post("/chat")
def chat(body: ChatIn):
    """搭图 Agent 对话 → SSE 流式(api-contract):tool_call/tool_result/message/done。
    Agent 在后台线程跑,事件经线程安全队列流出。多轮上下文经 history 传入。"""
    q: "queue.Queue" = queue.Queue()
    msg = body.message + (f"\n[用户附带参考图: {body.image}]" if body.image else "")

    def work():
        try:
            ctx = Context(ComfyClient(), _recipes, _store(body.project))
            text, _ = run_agent(msg, ctx, on_event=q.put, history=body.history)
            q.put({"type": "message", "text": text, "graph": ctx.graph})
        except Exception as e:  # noqa: BLE001
            q.put({"type": "error", "error": str(e)})
        finally:
            q.put(None)

    threading.Thread(target=work, daemon=True).start()

    def gen():
        while True:
            e = q.get()
            if e is None:
                yield "event: done\ndata: {}\n\n"
                break
            etype = e.get("type", "message")
            yield f"event: {etype}\ndata: {json.dumps(e, ensure_ascii=False)}\n\n"

    return StreamingResponse(gen(), media_type="text/event-stream")
