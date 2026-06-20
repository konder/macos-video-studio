"""阶段1 管线自检:角色定稿 + 场景 → 关键帧 → 视频 take。

  cd orchestrator
  python -m scripts.run_shot <角色定稿图路径> "<场景编辑指令>" ["<动作描述>"]

例:
  python -m scripts.run_shot ./projects/demo/assets/char.png \
      "Place this exact same woman on a sunny beach at dusk, keep her face, hairstyle and outfit identical." \
      "the woman smiles and her hair moves gently in the breeze, slow cinematic push-in"

必须在能访问 5090 的内网运行。
"""
from __future__ import annotations

import sys

from app.comfy import ComfyClient
from app.config import settings
from app.pipeline import shot_to_video
from app.recipes import RecipeRegistry
from app.store import ProjectStore


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    character_image = sys.argv[1]
    scene_prompt = sys.argv[2]
    motion_prompt = sys.argv[3] if len(sys.argv) > 3 else None

    comfy = ComfyClient()
    recipes = RecipeRegistry()
    store = ProjectStore(settings.projects_dir)
    print(f"ComfyUI: {settings.comfy_url}\n角色: {character_image}\n场景: {scene_prompt}\n" + "=" * 60)

    res = shot_to_video(comfy, recipes, store, character_image, scene_prompt, motion_prompt)
    print("=" * 60)
    if res["errors"]:
        print("❌ 失败:", res["errors"])
        sys.exit(2)
    print(f"✅ 关键帧: {res['keyframe']}")
    print(f"✅ 视频 take: {res['video']}")


if __name__ == "__main__":
    main()
