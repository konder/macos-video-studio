"""搭图 Agent 工具集(agent-system §4):配方(search/instantiate)+ 图编辑原语
(set_param/add_node/connect/delete_node)+ estimate + validate + run。
图编辑原语让 Agent 与人走同一套 op 改同一份 IR(无特权写路径,对称写入)。"""
from __future__ import annotations

import json

import time

from .estimate import estimate as estimate_task
from .ir import ir_to_prompt
from .ops import apply_ops, record_change
from .store import _nid

# 原始 JSON schema 工具定义,直接传给 Anthropic Messages API。
TOOL_SCHEMAS = [
    {
        "name": "search_recipes",
        "description": "按意图检索配方库,返回可用配方列表(含 id / 标题 / 阶段 / 可调参数)。",
        "input_schema": {
            "type": "object",
            "properties": {"intent": {"type": "string", "description": "用户意图 / 任务描述"}},
            "required": ["intent"],
        },
    },
    {
        "name": "instantiate_recipe",
        "description": "用参数实例化某配方为 Graph IR(prompt 格式 + pos),设为当前图。",
        "input_schema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "配方 id,如 char_concept"},
                "params": {"type": "object", "description": "参数键值,如 {prompt, width, steps, ...}"},
            },
            "required": ["id", "params"],
        },
    },
    {
        "name": "set_param",
        "description": "改当前图某节点的一个 widget 参数(局部改图原语)。附 rationale 说明为什么这么改。",
        "input_schema": {
            "type": "object",
            "properties": {
                "node": {"type": "string", "description": "节点 id"},
                "widget": {"type": "string", "description": "参数名,如 steps / cfg / seed"},
                "value": {"description": "新值(数字/字符串/布尔)"},
                "rationale": {"type": "string", "description": "为什么这么调"},
            },
            "required": ["node", "widget", "value"],
        },
    },
    {
        "name": "add_node",
        "description": "新增一个节点(局部改图原语)。type 必须是 /object_info 里真实存在的 class_type。",
        "input_schema": {
            "type": "object",
            "properties": {
                "node": {"type": "string", "description": "新节点 id(唯一)"},
                "type": {"type": "string", "description": "class_type"},
                "inputs": {"type": "object", "description": "初始 widget/输入(可空)"},
                "pos": {"type": "array", "items": {"type": "number"}, "description": "[x,y] 画布坐标"},
                "rationale": {"type": "string"},
            },
            "required": ["node", "type"],
        },
    },
    {
        "name": "connect",
        "description": "连一条边:from_node 的第 from_slot 个输出 → to_node 的 to_input 输入。",
        "input_schema": {
            "type": "object",
            "properties": {
                "from_node": {"type": "string"}, "from_slot": {"type": "integer"},
                "to_node": {"type": "string"}, "to_input": {"type": "string"},
                "rationale": {"type": "string"},
            },
            "required": ["from_node", "from_slot", "to_node", "to_input"],
        },
    },
    {
        "name": "delete_node",
        "description": "删除当前图的一个节点(局部改图原语)。",
        "input_schema": {
            "type": "object",
            "properties": {"node": {"type": "string"}, "rationale": {"type": "string"}},
            "required": ["node"],
        },
    },
    {
        "name": "estimate",
        "description": "预估当前图的耗时/显存/费用(本地无现金成本;视频任务更慢)。run 前可先看。",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "validate",
        "description": "对当前 Graph IR 对照 ComfyUI /object_info 校验(节点存在 / 必填 / 枚举)。返回 ok 与错误列表。",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "run",
        "description": "提交当前 Graph IR 到 ComfyUI 执行,等待完成并取回产物(写入项目文件夹)。",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "create_asset",
        "description": "创建一个资产(角色/服装/道具/场景/风格)的完整动作:在当前项目里**先建出该资产**"
                       "(立刻出现在资产库/左侧树)→ 用文字实例化它的生成流程 → 执行 → 把产物回填为预览图。"
                       "用户说'生成一个角色/做个场景'等就用它,一步到位。",
        "input_schema": {
            "type": "object",
            "properties": {
                "atype": {"type": "string", "enum": ["character", "wardrobe", "prop", "environment", "styleframe"],
                          "description": "资产类型"},
                "name": {"type": "string", "description": "资产名称(中文友好)"},
                "prompt": {"type": "string", "description": "外观/内容描述(高质量英文 prompt 更佳)"},
            },
            "required": ["atype", "name", "prompt"],
        },
    },
]


class Context:
    """一次会话的运行时:ComfyUI 客户端 / 配方库 / 项目存储 / 当前图。"""

    def __init__(self, comfy, recipes, store) -> None:
        self.comfy = comfy
        self.recipes = recipes
        self.store = store
        self.graph: dict | None = None
        self.validated: bool = False  # 当前图是否已 validate 通过(run 的前置门槛)
        self.last_assets: list[str] = []  # 最近一次 run 的产物路径(供 save_asset 登记)


def dispatch(name: str, args: dict, ctx: Context) -> str:
    if name == "search_recipes":
        return json.dumps(ctx.recipes.search(args.get("intent", "")), ensure_ascii=False)

    if name == "instantiate_recipe":
        ctx.graph = ctx.recipes.instantiate(args["id"], args.get("params", {}))
        ctx.validated = False  # 新图未校验
        return json.dumps({"ok": True, "nodes": len(ctx.graph["nodes"])}, ensure_ascii=False)

    # ---- 图编辑原语(与人走同一套 op,改 ctx.graph)----
    if name in ("set_param", "add_node", "connect", "delete_node"):
        if ctx.graph is None:
            return "Error: 还没有当前图,请先 instantiate_recipe。"
        if name == "set_param":
            op = {"op": "set_param", "node": args["node"], "widget": args["widget"], "value": args["value"]}
        elif name == "add_node":
            op = {"op": "add_node", "node": args["node"], "type": args["type"],
                  "inputs": args.get("inputs", {}), "pos": args.get("pos", [0, 0])}
        elif name == "connect":
            op = {"op": "connect", "from": {"node": args["from_node"], "slot": args["from_slot"]},
                  "to": {"node": args["to_node"], "input": args["to_input"]}}
        else:
            op = {"op": "delete_node", "node": args["node"]}
        try:
            ctx.graph = apply_ops(ctx.graph, [op])
        except Exception as e:  # noqa: BLE001
            return f"Error: {e}"
        ctx.validated = False   # 改图后需重新 validate 才能 run
        return json.dumps({"ok": True, "nodes": len(ctx.graph["nodes"]),
                           "rationale": args.get("rationale", "")}, ensure_ascii=False)

    if name == "estimate":
        if ctx.graph is None:
            return "Error: 还没有当前图。"
        cts = {n.get("class_type", "") for n in ctx.graph["nodes"].values()}
        is_video = any(("Wan" in c or "WAN" in c or "Video" in c or "I2V" in c or "i2v" in c) for c in cts)
        return json.dumps(estimate_task("i2v_local" if is_video else "keyframe_edit", "local-5090"),
                          ensure_ascii=False)

    if name == "validate":
        if ctx.graph is None:
            return "Error: 还没有当前图,请先 instantiate_recipe。"
        errors = validate_ir(ctx.graph, ctx.comfy.object_info())
        ctx.validated = not errors
        return json.dumps({"ok": not errors, "errors": errors}, ensure_ascii=False)

    if name == "run":
        if ctx.graph is None:
            return "Error: 还没有当前图。"
        # 执行前置门槛:必须先 validate 通过(决策 dev-kickoff §3:validate → run)
        if not ctx.validated:
            return "Error: 当前图尚未 validate 通过,请先调用 validate;若有错误改正后再 run。"
        res = run_ir(ctx.graph, ctx.comfy, ctx.store)
        ctx.last_assets = res.get("assets", []) or []
        return json.dumps(res, ensure_ascii=False)

    if name == "create_asset":
        # 完整动作:先建实体(入树)→ 实例化流程 → 执行 → 回填预览。每步经 op 入历史(与人同构)。
        atype = args.get("atype", "prop")
        aname = args.get("name") or "未命名资产"
        prompt = args.get("prompt") or aname
        is_char = atype == "character"
        aid = _nid("char" if is_char else atype[:4])
        ir = ctx.recipes.instantiate("char_concept", {"prompt": prompt, "seed": 42})
        # 1) 先建出资产(finals 空 + 已挂流程)→ 立刻出现在左侧树
        create_op = {"op": "create_character" if is_char else "create_asset", "id": aid,
                     "name": aname, "prompt": prompt, "finals": [], "graph": ir}
        if not is_char:
            create_op["type"] = atype
        _commit_ctx(ctx, [create_op], f"新建{atype} {aname}")
        # 2) 执行流程
        errs = validate_ir(ir, ctx.comfy.object_info())
        if errs:
            return json.dumps({"ok": False, "asset_id": aid, "error": f"流程校验失败: {errs}"}, ensure_ascii=False)
        res = run_ir(ir, ctx.comfy, ctx.store)
        ctx.last_assets = res.get("assets", []) or []
        if not ctx.last_assets:
            return json.dumps({"ok": False, "asset_id": aid, "error": res.get("error", "无产物")}, ensure_ascii=False)
        # 3) 回填预览(finals)
        field_op = "set_character_field" if is_char else "set_asset_field"
        _commit_ctx(ctx, [{"op": field_op, "id": aid, "field": "finals", "value": ctx.last_assets}], "更新资产预览")
        return json.dumps({"ok": True, "asset_id": aid, "finals": ctx.last_assets}, ensure_ascii=False)

    return f"Error: unknown tool {name}"


def _commit_ctx(ctx, ops: list[dict], rationale: str) -> None:
    """Agent 写操作经 op + 统一历史落库(无特权写路径)。"""
    doc = ctx.store.load()
    ch = record_change(doc, ops, author="agent", rationale=rationale)
    ch["ts"] = time.time()
    doc["history"][-1]["ts"] = ch["ts"]
    ctx.store._write(doc)


# 文件名类枚举来自启动时的目录快照,运行时可由 /upload 动态新增 → 不做枚举硬校验。
_DYNAMIC_FILE_ENUMS = {("LoadImage", "image"), ("LoadImageMask", "image"), ("LoadVideo", "file")}


def validate_ir(ir: dict, object_info: dict) -> list[str]:
    """对照 /object_info:节点类型存在、必填项齐、枚举值合法。"""
    errors: list[str] = []
    for nid, node in ir["nodes"].items():
        ct = node["class_type"]
        spec = object_info.get(ct)
        if not spec:
            errors.append(f"节点 {nid}: 未知 class_type '{ct}'")
            continue
        required = spec.get("input", {}).get("required", {})
        inputs = node.get("inputs", {})
        for iname, meta in required.items():
            if iname not in inputs:
                errors.append(f"节点 {nid} ({ct}): 缺必填输入 '{iname}'")
                continue
            val = inputs[iname]
            # 枚举:meta 形如 [["euler","dpmpp_2m",...], {...}];连线值是 [id, slot] 列表,跳过
            if (isinstance(meta, list) and meta and isinstance(meta[0], list)
                    and not isinstance(val, list)):
                # 跳过"运行时动态资产"类文件名枚举:LoadImage 等的文件列表是启动快照，
                # pipeline 上传的新文件不在其中但 run 时可加载(实测),不应误判。
                if (ct, iname) in _DYNAMIC_FILE_ENUMS:
                    continue
                allowed = meta[0]
                if val not in allowed:
                    sample = allowed[:6]
                    errors.append(f"节点 {nid} ({ct}): 输入 '{iname}'={val!r} 不在允许值 {sample}…")
    return errors


def run_ir(ir: dict, comfy, store) -> dict:
    """IR -> ComfyUI prompt -> 提交 -> 等待 -> 取回产物(图像 + 视频)。"""
    prompt = ir_to_prompt(ir)
    prompt_id = comfy.submit(prompt)
    history = comfy.wait(prompt_id)
    status = history.get("status", {})
    if status.get("status_str") == "error":
        msg = _history_error(status)
        return {"prompt_id": prompt_id, "assets": [], "error": msg}
    assets: list[str] = []
    # SaveImage → outputs[node]["images"]; SaveVideo/VHS → ["videos"]/["gifs"]
    for _node_id, out in history.get("outputs", {}).items():
        for kind in ("images", "videos", "gifs"):
            for item in out.get(kind, []):
                if not isinstance(item, dict) or "filename" not in item:
                    continue
                data = comfy.download(item)
                assets.append(store.save_asset(data, item["filename"]))
    return {"prompt_id": prompt_id, "assets": assets}


def _history_error(status: dict) -> str:
    for m in status.get("messages", []):
        if m and m[0] == "execution_error":
            info = m[1]
            return f"{info.get('node_type')}: {str(info.get('exception_message'))[:200]}"
    return "execution error"
