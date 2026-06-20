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
