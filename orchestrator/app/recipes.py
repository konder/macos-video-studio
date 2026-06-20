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


def _look(style: str) -> str:
    return ("anime style, clean cel-shaded illustration" if style == "anime"
            else "photorealistic, realistic photograph")


# 每类资产的"主体 + 取景"基底(不含画风/视角)。关键:服装/道具不画人,场景不画人。
def _type_base(atype: str, prompt: str) -> str:
    if atype == "character":
        return (f"{prompt}, solo, single person, one character only, full body from head to toe, "
                "standing, centered, simple light gray background, neutral expression, even lighting, "
                "8k, highly detailed")
    if atype == "wardrobe":
        return (f"{prompt}, a single clothing garment only, ghost mannequin (invisible body), no person, "
                "product photography, isolated, centered, plain white background, even studio lighting, "
                "8k, highly detailed")
    if atype == "prop":
        return (f"{prompt}, a single object only, no person, product shot, isolated, centered, "
                "plain white background, even studio lighting, 8k, highly detailed")
    if atype == "environment":
        return (f"{prompt}, environment scenery only, no people, wide establishing shot, "
                "cinematic lighting, 8k, highly detailed")
    if atype == "styleframe":
        return f"{prompt}, art-style moodboard, color palette and texture reference, 8k, highly detailed"
    return f"{prompt}, isolated, centered, plain white background, 8k, highly detailed"


# 各类资产的多视角(无 = 单图)。服装/道具也出三视;场景/风格单图。
_VIEWS = {
    "character": [("front", "full-body front view facing camera"), ("side", "full-body side view profile"), ("back", "full-body back view from behind")],
    "wardrobe": [("front", "front view"), ("back", "back view"), ("side", "side view")],
    "prop": [("front", "front view"), ("side", "side view"), ("3/4", "three-quarter angle view")],
}


def asset_view_prompts(atype: str, prompt: str, style: str = "realistic") -> list[tuple[str, str]]:
    """该资产要生成的(label, 完整 prompt)列表;多视=多张,否则单张。"""
    look = _look(style); base = _type_base(atype, prompt); views = _VIEWS.get(atype)
    if not views:
        return [("", f"{look}, {base}")]
    return [(lab, f"{look}, {vp}, {base}") for lab, vp in views]


def asset_prompt(atype: str, prompt: str, style: str = "realistic") -> str:
    """单图增强 prompt(参考图/编辑路径用):取该类型首个视角 + 基底。"""
    look = _look(style); views = _VIEWS.get(atype)
    v = (views[0][1] + ", ") if views else ""
    return f"{look}, {v}{_type_base(atype, prompt)}"


def asset_dims(atype: str) -> tuple[int, int]:
    return {"character": (832, 1216), "wardrobe": (896, 1152), "prop": (1024, 1024),
            "environment": (1344, 768), "styleframe": (1024, 1024)}.get(atype, (1024, 1024))


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
