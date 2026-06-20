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


def asset_prompt(atype: str, prompt: str, style: str = "realistic") -> str:
    """按资产类型增强 prompt。角色 → 站姿全身三视角(正/侧/背)、纯白底、按项目风格。"""
    if atype != "character":
        return prompt
    look = ("anime style, clean cel-shaded illustration" if style == "anime"
            else "photorealistic, ultra-realistic studio photograph, natural soft lighting, sharp focus")
    return (f"{prompt}, full body from head to toe, standing upright straight, "
            "three separate full-body views of the same person side by side in one image: "
            "front view, side view, back view, consistent character design, "
            "plain seamless white background, no furniture no props, " + look)


def asset_dims(atype: str) -> tuple[int, int]:
    """角色三视角用宽幅,其余方形。"""
    return (1536, 768) if atype == "character" else (1024, 1024)


class RecipeRegistry:
    def __init__(self) -> None:
        self.recipes: dict[str, dict] = {}
        for f in glob.glob(os.path.join(RECIPE_DIR, "*.json")):
            with open(f, encoding="utf-8") as fh:
                r = json.load(fh)
            self.recipes[r["id"]] = r

    def search(self, intent: str) -> list[dict]:
        """关键词检索(agent-system §3 的轻量版):按 intent 词在 id/title/stage/note 上打分排序;
        无 intent 或全不命中则返回全部(不漏召回)。向量检索后续接。"""
        def summary(r: dict) -> dict:
            return {"id": r["id"], "title": r.get("title"), "stage": r.get("stage"),
                    "params": list(r.get("params_schema", {}).keys()), "note": r.get("_note")}

        items = list(self.recipes.values())
        low = intent.lower().strip()
        if not low:
            return [summary(r) for r in items]

        # 中文无空格:用「配方关键词」逐个在 intent 串里做子串匹配(而非切分 intent)。
        def score(r: dict) -> int:
            kws = list(self._STAGE_WORDS.get(r.get("stage", ""), []))
            kws += [r["id"], r.get("stage", "")]
            kws += str(r.get("title", "")).lower().replace("(", " ").replace(")", " ").split()
            return sum(1 for k in kws if k and str(k).lower() in low)

        scored = sorted(((score(r), r) for r in items), key=lambda x: -x[0])
        hits = [summary(r) for s, r in scored if s > 0]
        return hits or [summary(r) for r in items]

    # 中文意图 → 阶段关键词(让"视频""定妆""关键帧"等能命中对应 stage)
    _STAGE_WORDS = {
        "asset": ["角色", "定妆", "定稿", "人物", "character", "asset", "多视角"],
        "storyboard": ["关键帧", "分镜", "场景", "keyframe", "compose"],
        "generate": ["视频", "图生视频", "动起来", "i2v", "video", "成片"],
        "post": ["超分", "补帧", "upscale", "高清"],
    }

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
