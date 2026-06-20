"""阶段3 自检:一段剧本 + 角色定稿 → 导演拆镜 → 多镜头一致成片。

  cd orchestrator
  export LITELLM_API_KEY=...  AGENT_MODEL=glm-5.2
  python -m scripts.run_film <角色定稿图> "<角色描述>" "<剧本/情境>" [镜头数]

产物:各镜头关键帧+视频 take 落项目文件夹;最后用 ffmpeg 拼成 film.mp4(若有 ffmpeg)。
"""
from __future__ import annotations

import os
import subprocess
import sys

from app.agent import make_client
from app.backends import BackendRegistry
from app.config import settings
from app.director import produce_film
from app.recipes import RecipeRegistry
from app.store import ProjectStore


def main() -> None:
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    character_image, character_desc, script = sys.argv[1], sys.argv[2], sys.argv[3]
    n_shots = int(sys.argv[4]) if len(sys.argv) > 4 else 3

    client = make_client()
    registry = BackendRegistry()
    recipes = RecipeRegistry()
    store = ProjectStore(settings.projects_dir)
    print(f"模型: {settings.model} · 角色: {character_image}\n剧本: {script}\n" + "=" * 60)

    res = produce_film(registry, recipes, store, character_image, character_desc,
                       script, client, settings.model, n_shots=n_shots,
                       on_event=lambda m: print("·", m, flush=True))
    print("=" * 60)
    videos = [s["video"] for s in res["shots"] if s.get("video")]
    for s in res["shots"]:
        print(f"  shot {s['shot']}: kf={s['keyframe']} video={s['video']} {s['errors'] or ''}")

    # 拼接成片
    if videos and len(videos) >= 2:
        lst = os.path.join(store.root, "_concat.txt")
        with open(lst, "w") as f:
            for v in videos:
                f.write(f"file '{os.path.abspath(v)}'\n")
        out = os.path.join(store.root, "film.mp4")
        r = subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", lst,
                            "-c", "copy", out], capture_output=True)
        if r.returncode == 0:
            print(f"🎬 成片: {out}")
        else:
            print("(拼接失败,可手动拼;各 take 已就绪)")
    print(f"✅ {len(videos)}/{len(res['shots'])} 镜头出片")


if __name__ == "__main__":
    main()
