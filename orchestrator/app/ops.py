"""op 协议(api-contract.md):人和 Agent 用同一套 op 改同一份 Graph IR(无特权写路径)。

支持的 op:
  {"op":"set_param","node":id,"widget":name,"value":v}
  {"op":"add_node","node":id,"type":class_type,"pos":[x,y],"inputs":{...}}
  {"op":"connect","from":{"node":id,"slot":i},"to":{"node":id,"input":name}}
  {"op":"delete_node","node":id}

apply_ops 对 IR(含 nodes)就地应用一组有序 op,返回新 IR。校验交给 validate。
"""
from __future__ import annotations

import copy


class OpError(ValueError):
    pass


def apply_ops(ir: dict, ops: list[dict]) -> dict:
    out = copy.deepcopy(ir)
    nodes = out.setdefault("nodes", {})
    for op in ops:
        kind = op.get("op")
        if kind == "set_param":
            n = _node(nodes, op["node"])
            n.setdefault("inputs", {})[op["widget"]] = op["value"]
        elif kind == "add_node":
            nid = op["node"]
            if nid in nodes:
                raise OpError(f"节点已存在: {nid}")
            nodes[nid] = {"class_type": op["type"], "inputs": op.get("inputs", {}),
                          "pos": op.get("pos", [0, 0])}
        elif kind == "connect":
            src, dst = op["from"], op["to"]
            if src["node"] not in nodes:
                raise OpError(f"连接源不存在: {src['node']}")
            _node(nodes, dst["node"]).setdefault("inputs", {})[dst["input"]] = [src["node"], src["slot"]]
        elif kind == "delete_node":
            nodes.pop(op["node"], None)
        else:
            raise OpError(f"未知 op: {kind}")
    return out


def _node(nodes: dict, nid: str) -> dict:
    if nid not in nodes:
        raise OpError(f"节点不存在: {nid}")
    return nodes[nid]


# ---- 项目级 op(api-contract.md /projects/{id}/ops)----
# 人和 Agent 用同一套 op 改同一份项目模型(无特权写路径)。
# 项目级 op 改 doc(分镜/资产/选片/元信息);图级 op(set_param/add_node/...)带 shot 字段,
# 改该镜头的 graph IR(复用 apply_ops)。
_GRAPH_OPS = {"set_param", "add_node", "connect", "delete_node"}


def _shot(doc: dict, sid: str) -> dict:
    s = next((s for s in doc.get("shots", []) if s["id"] == sid), None)
    if s is None:
        raise OpError(f"未知镜头: {sid}")
    return s


def _graph_entity(doc: dict, op: dict) -> dict:
    """图级 op 的目标实体:镜头 / 资产 / 角色(都可挂 graph)。"""
    if "shot" in op:
        return _shot(doc, op["shot"])
    if "asset" in op:
        e = next((a for a in doc.get("assets", []) if a["id"] == op["asset"]), None)
        if e is None:
            raise OpError(f"未知资产: {op['asset']}")
        return e
    if "character" in op:
        e = next((c for c in doc.get("characters", []) if c["id"] == op["character"]), None)
        if e is None:
            raise OpError(f"未知角色: {op['character']}")
        return e
    raise OpError("图级 op 缺目标(shot/asset/character)")


def _graph_entity_or_none(doc: dict, op: dict) -> dict | None:
    try:
        return _graph_entity(doc, op)
    except OpError:
        return None


def apply_project_ops(doc: dict, ops: list[dict]) -> dict:
    """对项目 doc 就地应用一组有序 op,返回 doc。图级 op 走 apply_ops 落到 shot.graph。

    所有创建型 op 的 id 由调用方放进 op(create_shot.id/add_take.take/create_*.id),
    以保证变更可重放、撤销可逆(不在此处随机生成 id)。
    """
    for op in ops:
        kind = op.get("op")
        # ---- 图级(改某镜头/资产/角色的 graph IR;目标对称)----
        if kind in _GRAPH_OPS:
            ent = _graph_entity(doc, op)
            ent["graph"] = apply_ops(ent.get("graph") or {"nodes": {}}, [op])
        elif kind == "set_pos":
            ent = _graph_entity(doc, op)
            nodes = (ent.setdefault("graph", {"nodes": {}})).setdefault("nodes", {})
            if op["node"] not in nodes:
                raise OpError(f"节点不存在: {op['node']}")
            nodes[op["node"]]["pos"] = op["pos"]
        # ---- 镜头 ----
        elif kind == "create_shot":
            if "id" not in op:
                raise OpError("create_shot 缺 id")
            doc.setdefault("shots", []).append({
                "id": op["id"], "script": op.get("script", ""), "refs": op.get("refs", []),
                "scene_prompt": op.get("scene_prompt", ""), "motion_prompt": op.get("motion_prompt", ""),
                "keyframe": None, "takes": [], "selected_take": None, "graph": None})
        elif kind == "delete_shot":
            doc["shots"] = [s for s in doc.get("shots", []) if s["id"] != op["shot"]]
        elif kind == "set_keyframe":
            _shot(doc, op["shot"])["keyframe"] = op["keyframe"]
        elif kind == "add_take":
            shot = _shot(doc, op["shot"])
            if "take" not in op:
                raise OpError("add_take 缺 take(id)")
            shot.setdefault("takes", []).append(
                {"id": op["take"], "video": op.get("video"), "meta": op.get("meta", {})})
            if shot.get("selected_take") is None:
                shot["selected_take"] = op["take"]
        elif kind == "select_take":
            shot = _shot(doc, op["shot"])
            if op["take"] not in [t["id"] for t in shot.get("takes", [])]:
                raise OpError(f"未知 take: {op['take']}")
            shot["selected_take"] = op["take"]
        elif kind == "set_refs":            # = assign_asset:设镜头引用的角色/资产
            _shot(doc, op["shot"])["refs"] = op.get("refs", [])
        elif kind == "set_shot_field":      # script/scene_prompt/motion_prompt 等导演层文本
            field = op["field"]
            if field not in {"script", "scene_prompt", "motion_prompt"}:
                raise OpError(f"不可改字段: {field}")
            _shot(doc, op["shot"])[field] = op["value"]
        # ---- 资产 / 角色 ----
        elif kind == "create_character":
            if "id" not in op:
                raise OpError("create_character 缺 id")
            doc.setdefault("characters", []).append({
                "id": op["id"], "name": op.get("name", ""), "source": op.get("source", "text"),
                "finals": op.get("finals", []), "trigger": op.get("trigger", ""),
                "lora": op.get("lora"), "similarity": op.get("similarity"),
                "graph": op.get("graph"), "prompt": op.get("prompt", ""),
                "width": op.get("width"), "height": op.get("height")})
        elif kind == "create_asset":
            if "id" not in op:
                raise OpError("create_asset 缺 id")
            doc.setdefault("assets", []).append({
                "id": op["id"], "type": op.get("type", "prop"), "name": op.get("name", ""),
                "prompt": op.get("prompt", ""), "finals": op.get("finals", []),
                "meta": op.get("meta", {}), "graph": op.get("graph"),
                "width": op.get("width"), "height": op.get("height")})
        elif kind == "set_character_field":   # 身份锁定卡:name/trigger/lora/similarity/finals
            field = op["field"]
            if field not in {"name", "trigger", "lora", "similarity", "finals"}:
                raise OpError(f"角色不可改字段: {field}")
            c = next((c for c in doc.get("characters", []) if c["id"] == op["id"]), None)
            if c is None:
                raise OpError(f"未知角色: {op['id']}")
            c[field] = op["value"]
        elif kind == "set_asset_field":
            field = op["field"]
            if field not in {"name", "prompt", "type", "finals"}:
                raise OpError(f"资产不可改字段: {field}")
            a = next((a for a in doc.get("assets", []) if a["id"] == op["id"]), None)
            if a is None:
                raise OpError(f"未知资产: {op['id']}")
            a[field] = op["value"]
        elif kind == "set_meta":
            doc.setdefault("meta", {})[op["key"]] = op["value"]
        elif kind == "delete_character":
            doc["characters"] = [c for c in doc.get("characters", []) if c["id"] != op["id"]]
        elif kind == "delete_asset":
            doc["assets"] = [a for a in doc.get("assets", []) if a["id"] != op["id"]]
        elif kind == "delete_take":
            shot = _shot(doc, op["shot"])
            shot["takes"] = [t for t in shot.get("takes", []) if t["id"] != op["take"]]
            if shot.get("selected_take") == op["take"]:
                shot["selected_take"] = shot["takes"][0]["id"] if shot["takes"] else None
        else:
            raise OpError(f"未知 op: {kind}")
    return doc


# 撤销:在应用前读当前状态,算出能把 doc 复原的逆操作组(倒序)。
# 不可逆的(add_take/set_keyframe 含已产出 take、delete_*)返回 None → 该变更不可撤销
# (符合 native-ui:撤销改 IR 状态,不删已产出 take)。
_INVERTIBLE_SET = {
    "set_meta": ("meta_key",), "set_param": ("node_widget",), "set_pos": ("shot_node",),
    "set_refs": ("shot",), "set_shot_field": ("shot_field",),
    "set_character_field": ("char_field",), "set_asset_field": ("asset_field",),
}


def invert_ops(doc: dict, ops: list[dict]) -> list[dict] | None:
    """返回可把 doc 复原的逆 op(倒序);任一 op 不可逆则返回 None。"""
    inv: list[dict] = []
    for op in ops:
        k = op.get("op")
        if k == "set_meta":
            prev = (doc.get("meta") or {}).get(op["key"])
            inv.append({"op": "set_meta", "key": op["key"], "value": prev})
        elif k == "set_param":
            n = ((_graph_entity_or_none(doc, op) or {}).get("graph") or {}).get("nodes", {}).get(op["node"], {})
            tgt = {t: op[t] for t in ("shot", "asset", "character") if t in op}
            inv.append({"op": "set_param", **tgt, "node": op["node"],
                        "widget": op["widget"], "value": (n.get("inputs") or {}).get(op["widget"])})
        elif k == "set_pos":
            n = ((_graph_entity_or_none(doc, op) or {}).get("graph") or {}).get("nodes", {}).get(op["node"], {})
            tgt = {t: op[t] for t in ("shot", "asset", "character") if t in op}
            inv.append({"op": "set_pos", **tgt, "node": op["node"], "pos": n.get("pos", [0, 0])})
        elif k == "set_refs":
            inv.append({"op": "set_refs", "shot": op["shot"], "refs": (_find_shot(doc, op["shot"]) or {}).get("refs", [])})
        elif k == "set_shot_field":
            inv.append({"op": "set_shot_field", "shot": op["shot"], "field": op["field"],
                        "value": (_find_shot(doc, op["shot"]) or {}).get(op["field"], "")})
        elif k == "set_character_field":
            c = next((c for c in doc.get("characters", []) if c["id"] == op["id"]), {})
            inv.append({"op": "set_character_field", "id": op["id"], "field": op["field"], "value": c.get(op["field"])})
        elif k == "set_asset_field":
            a = next((a for a in doc.get("assets", []) if a["id"] == op["id"]), {})
            inv.append({"op": "set_asset_field", "id": op["id"], "field": op["field"], "value": a.get(op["field"])})
        elif k == "select_take":
            prev = (_find_shot(doc, op["shot"]) or {}).get("selected_take")
            if not prev:
                return None
            inv.append({"op": "select_take", "shot": op["shot"], "take": prev})
        elif k == "create_shot":
            inv.append({"op": "delete_shot", "shot": op["id"]})
        elif k == "create_character":
            inv.append({"op": "delete_character", "id": op["id"]})
        elif k == "create_asset":
            inv.append({"op": "delete_asset", "id": op["id"]})
        else:
            return None   # add_take / set_keyframe / delete_* 等:不可撤销(保留产物)
    inv.reverse()
    return inv


def _find_shot(doc: dict, sid: str) -> dict | None:
    return next((s for s in doc.get("shots", []) if s["id"] == sid), None)


def record_change(doc: dict, ops: list[dict], author: str = "human",
                  rationale: str = "", tool_call: str | None = None) -> dict:
    """应用 ops 并以单调 seq 记入统一历史。先算逆操作(用于撤销),再应用。返回该 change。"""
    inverse = invert_ops(doc, ops)      # 必须在 apply 前读旧状态
    apply_project_ops(doc, ops)
    seq = int(doc.get("seq", 0)) + 1
    doc["seq"] = seq
    change = {"seq": seq, "author": author, "rationale": rationale,
              "tool_call": tool_call, "ops": ops, "inverse": inverse,
              "undoable": inverse is not None, "undone": False}
    doc.setdefault("history", []).append(change)
    return change
