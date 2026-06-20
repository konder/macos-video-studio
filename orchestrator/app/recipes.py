"""配方库:加载 recipes/*.json,检索 + 用参数实例化为 Graph IR。

配方 = 参数化工作流模板。Agent 主要「选配方 → 填参 → 局部改图」,而非凭空写整张图
(可靠性策略见 docs/agent-system.md §2/§3)。
"""
from __future__ import annotations

import copy
import glob
import json
import os

RECIPE_DIR = os.path.join(os.path.dirname(__file__), "recipes")


class RecipeRegistry:
    def __init__(self) -> None:
        self.recipes: dict[str, dict] = {}
        for f in glob.glob(os.path.join(RECIPE_DIR, "*.json")):
            with open(f, encoding="utf-8") as fh:
                r = json.load(fh)
            self.recipes[r["id"]] = r

    def search(self, intent: str) -> list[dict]:
        """MVP:返回全部配方的摘要。后续接 docs/agent-system.md §3 的向量/关键词混合检索。"""
        return [
            {"id": r["id"], "title": r.get("title"), "stage": r.get("stage"),
             "params": list(r.get("params_schema", {}).keys()), "note": r.get("_note")}
            for r in self.recipes.values()
        ]

    def instantiate(self, recipe_id: str, params: dict) -> dict:
        """填参 → Graph IR(含 pos)。缺省值取自 params_schema。"""
        r = self.recipes[recipe_id]
        merged: dict = {}
        for key, spec in r.get("params_schema", {}).items():
            merged[key] = spec.get("default")
        merged.update(params or {})
        graph = copy.deepcopy(r["graph_template"])
        return _subst(graph, merged)


def _subst(obj, params: dict):
    """递归替换占位符。整串 '{{name}}' 按原类型替换;内嵌则字符串替换。"""
    if isinstance(obj, dict):
        return {k: _subst(v, params) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_subst(x, params) for x in obj]
    if isinstance(obj, str):
        s = obj.strip()
        if s.startswith("{{") and s.endswith("}}"):
            return params.get(s[2:-2].strip())
        for k, v in params.items():
            obj = obj.replace("{{" + k + "}}", str(v))
        return obj
    return obj
