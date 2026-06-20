"""Agent 的四个工具(M1):search_recipes / instantiate_recipe / validate / run。
都是本地执行(client-side),由 Orchestrator 实现并喂回结果。"""
from __future__ import annotations

import json

from .ir import ir_to_prompt

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
        "name": "validate",
        "description": "对当前 Graph IR 对照 ComfyUI /object_info 校验(节点存在 / 必填 / 枚举)。返回 ok 与错误列表。",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "run",
        "description": "提交当前 Graph IR 到 ComfyUI 执行,等待完成并取回产物(写入项目文件夹)。",
        "input_schema": {"type": "object", "properties": {}, "required": []},
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


def dispatch(name: str, args: dict, ctx: Context) -> str:
    if name == "search_recipes":
        return json.dumps(ctx.recipes.search(args.get("intent", "")), ensure_ascii=False)

    if name == "instantiate_recipe":
        ctx.graph = ctx.recipes.instantiate(args["id"], args.get("params", {}))
        ctx.validated = False  # 新图未校验
        return json.dumps({"ok": True, "nodes": len(ctx.graph["nodes"])}, ensure_ascii=False)

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
        return json.dumps(run_ir(ctx.graph, ctx.comfy, ctx.store), ensure_ascii=False)

    return f"Error: unknown tool {name}"


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
                allowed = meta[0]
                if val not in allowed:
                    sample = allowed[:6]
                    errors.append(f"节点 {nid} ({ct}): 输入 '{iname}'={val!r} 不在允许值 {sample}…")
    return errors


def run_ir(ir: dict, comfy, store) -> dict:
    """IR -> ComfyUI prompt -> 提交 -> 等待 -> 取回产物。"""
    prompt = ir_to_prompt(ir)
    prompt_id = comfy.submit(prompt)
    history = comfy.wait(prompt_id)
    assets: list[str] = []
    for _node_id, out in history.get("outputs", {}).items():
        for img in out.get("images", []):
            data = comfy.download(img)
            assets.append(store.save_asset(data, img.get("filename", "out.png")))
    return {"prompt_id": prompt_id, "assets": assets}
