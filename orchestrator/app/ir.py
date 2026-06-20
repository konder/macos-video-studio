"""Graph IR <-> ComfyUI 格式转换。

IR = ComfyUI 执行用的 `prompt` 格式为事实来源 + 每节点 `pos` 给画布布局
(决策见 docs/data-model.md §2)。

IR 形状:
    {"nodes": {"<id>": {"class_type": str, "inputs": {...}, "pos": [x, y]}}}

`inputs` 里的连线用 [上游节点id, 输出槽] 数组表示,与 ComfyUI 一致。
"""
from __future__ import annotations


def ir_to_prompt(ir: dict) -> dict:
    """IR -> ComfyUI /prompt 入参(去掉 pos)。"""
    return {
        nid: {"class_type": n["class_type"], "inputs": n.get("inputs", {})}
        for nid, n in ir["nodes"].items()
    }


def prompt_to_ir(prompt: dict, pos: dict | None = None) -> dict:
    """ComfyUI prompt(+可选 pos 表)-> IR。用于无损往返校验。"""
    pos = pos or {}
    return {
        "nodes": {
            nid: {
                "class_type": n["class_type"],
                "inputs": n.get("inputs", {}),
                "pos": pos.get(nid, [0, 0]),
            }
            for nid, n in prompt.items()
        }
    }
