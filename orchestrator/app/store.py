"""项目持久化:一个项目 = 一个文件夹(project.json + 媒体 + 缩略图)。
决策见 docs/data-model.md §4。生产环境 PROJECTS_DIR 指向 NAS /mnt/nas。
"""
from __future__ import annotations

import json
import os
import time


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
