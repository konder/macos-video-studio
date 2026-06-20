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


def apply_project_ops(doc: dict, ops: list[dict]) -> dict:
    """对项目 doc 就地应用一组有序 op,返回 doc。图级 op 走 apply_ops 落到 shot.graph。"""
    for op in ops:
        kind = op.get("op")
        if kind in _GRAPH_OPS:
            shot = _shot(doc, op["shot"])
            shot["graph"] = apply_ops(shot.get("graph") or {"nodes": {}}, [op])
        elif kind == "select_take":
            shot = _shot(doc, op["shot"])
            if op["take"] not in [t["id"] for t in shot.get("takes", [])]:
                raise OpError(f"未知 take: {op['take']}")
            shot["selected_take"] = op["take"]
        elif kind == "set_meta":
            doc.setdefault("meta", {})[op["key"]] = op["value"]
        elif kind == "set_refs":
            _shot(doc, op["shot"])["refs"] = op.get("refs", [])
        elif kind == "set_shot_field":      # script/scene_prompt/motion_prompt 等导演层文本
            field = op["field"]
            if field not in {"script", "scene_prompt", "motion_prompt"}:
                raise OpError(f"不可改字段: {field}")
            _shot(doc, op["shot"])[field] = op["value"]
        else:
            raise OpError(f"未知 op: {kind}")
    return doc


def record_change(doc: dict, ops: list[dict], author: str = "human",
                  rationale: str = "", tool_call: str | None = None) -> dict:
    """应用 ops 并以单调 seq 记入统一历史。返回该 change(含 seq)。"""
    apply_project_ops(doc, ops)
    seq = int(doc.get("seq", 0)) + 1
    doc["seq"] = seq
    change = {"seq": seq, "author": author, "rationale": rationale,
              "tool_call": tool_call, "ops": ops}
    doc.setdefault("history", []).append(change)
    return change
