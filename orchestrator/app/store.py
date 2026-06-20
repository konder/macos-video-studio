"""项目持久化:一个项目 = 一个文件夹(project.json + 媒体 + 缩略图)。
决策见 docs/data-model.md §4。生产环境 PROJECTS_DIR 指向 NAS /mnt/nas。

project.json schema(阶段2 定稿):
{
  "meta": {title, created, aspect, resolution, fps, style, ...},
  "characters": [ {id, name, source, finals:[path], trigger, lora, created} ],   # Character Bible
  "assets":     [ ... ],                                                          # 服装/道具/场景(后续)
  "shots":      [ {id, script, refs:[char_id], scene_prompt, motion_prompt,
                   keyframe, takes:[{id, video, meta}], selected_take, graph} ]
}
"""
from __future__ import annotations

import json
import os
import time
import uuid


def _nid(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:8]}"


class ProjectStore:
    def __init__(self, projects_dir: str, name: str = "demo") -> None:
        self.root = os.path.join(projects_dir, name)
        self.assets_dir = os.path.join(self.root, "assets")
        os.makedirs(self.assets_dir, exist_ok=True)
        self.project_path = os.path.join(self.root, "project.json")
        if not os.path.exists(self.project_path):
            self._write({
                "meta": {"title": name, "created": time.time(),
                         "aspect": "16:9", "resolution": "1080p", "fps": 24,
                         "style": "realistic"},
                "characters": [], "assets": [], "shots": [],
            })

    def _write(self, data: dict) -> None:
        with open(self.project_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load(self) -> dict:
        with open(self.project_path, encoding="utf-8") as f:
            return json.load(f)

    def save_asset(self, data: bytes, filename: str) -> str:
        # 防目录穿越:只取文件名
        safe = os.path.basename(filename) or "asset.bin"
        path = os.path.join(self.assets_dir, safe)
        with open(path, "wb") as f:
            f.write(data)
        return path

    # ---- Character Bible ----
    def add_character(self, name: str, source: str = "text",
                      finals: list[str] | None = None, trigger: str = "",
                      lora: str | None = None) -> dict:
        """加入角色档案:定稿图集 + 触发词 +(可选)LoRA。返回 character。"""
        doc = self.load()
        char = {"id": _nid("char"), "name": name, "source": source,
                "finals": finals or [], "trigger": trigger, "lora": lora,
                "created": time.time()}
        doc["characters"].append(char)
        self._write(doc)
        return char

    def set_character_lora(self, char_id: str, lora: str) -> None:
        doc = self.load()
        for c in doc["characters"]:
            if c["id"] == char_id:
                c["lora"] = lora
        self._write(doc)

    def get_character(self, char_id: str) -> dict | None:
        return next((c for c in self.load()["characters"] if c["id"] == char_id), None)

    # ---- Asset Library(服装/背景/道具/风格,角色见 Character Bible)----
    def add_asset(self, asset_type: str, name: str, prompt: str = "",
                  finals: list[str] | None = None, meta: dict | None = None) -> dict:
        """通用资产:type ∈ wardrobe/prop/environment/styleframe(角色用 add_character)。
        finals = 该资产的参考图集(可作 Qwen-edit 多图参考注入分镜)。"""
        doc = self.load()
        asset = {"id": _nid(asset_type[:4]), "type": asset_type, "name": name,
                 "prompt": prompt, "finals": finals or [], "meta": meta or {},
                 "created": time.time()}
        doc["assets"].append(asset)
        self._write(doc)
        return asset

    def list_assets(self, asset_type: str | None = None) -> list[dict]:
        items = self.load()["assets"]
        return [a for a in items if asset_type is None or a.get("type") == asset_type]

    def get_asset(self, asset_id: str) -> dict | None:
        return next((a for a in self.load()["assets"] if a["id"] == asset_id), None)

    # ---- Shots / takes ----
    def add_shot(self, script: str = "", refs: list[str] | None = None,
                 scene_prompt: str = "", motion_prompt: str = "") -> dict:
        doc = self.load()
        shot = {"id": _nid("shot"), "script": script, "refs": refs or [],
                "scene_prompt": scene_prompt, "motion_prompt": motion_prompt,
                "keyframe": None, "takes": [], "selected_take": None, "graph": None}
        doc["shots"].append(shot)
        self._write(doc)
        return shot

    def _shot(self, doc: dict, shot_id: str) -> dict:
        s = next((s for s in doc["shots"] if s["id"] == shot_id), None)
        if s is None:
            raise KeyError(f"未知镜头: {shot_id}")
        return s

    def set_keyframe(self, shot_id: str, keyframe: str) -> None:
        doc = self.load()
        self._shot(doc, shot_id)["keyframe"] = keyframe
        self._write(doc)

    def add_take(self, shot_id: str, video: str, meta: dict | None = None) -> dict:
        doc = self.load()
        shot = self._shot(doc, shot_id)
        take = {"id": _nid("take"), "video": video, "meta": meta or {}}
        shot["takes"].append(take)
        if shot["selected_take"] is None:
            shot["selected_take"] = take["id"]
        self._write(doc)
        return take

    def select_take(self, shot_id: str, take_id: str) -> None:
        doc = self.load()
        self._shot(doc, shot_id)["selected_take"] = take_id
        self._write(doc)
