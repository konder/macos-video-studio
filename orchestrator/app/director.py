"""导演 Agent（阶段3）：拆剧本 → 镜头清单 → 逐镜头注入角色档案 → 批量出片。

对应 agent-system §1 的「导演/制片 Agent」。拆镜用 LLM(经 LiteLLM)；每镜头复用阶段1
一致性管线(Qwen-edit 关键帧 → WAN i2v),角色档案自动注入,后端经 registry 路由(交互→5090)。
"""
from __future__ import annotations

import json
import os

from .pipeline import shot_to_video


SHOTLIST_SYS = """你是一位影视导演 + 分镜师。给定【角色描述】和一段【剧本/情境】,把它拆成有序的镜头清单。
每个镜头需要两段英文提示:
- scene: 给图像编辑模型的指令 —— 把这个角色放进该镜头的场景/动作姿态,**务必强调保持其面部、发型、服装与参考完全一致(keep face/hairstyle/outfit identical and unchanged)**,补足场景、构图、光线、景别。
- motion: 给图生视频模型的镜头动作/运镜英文描述(自然、电影感,3-5 秒能表现)。
只输出 JSON,格式: {"shots":[{"script":"该镜头中文简述","scene":"...","motion":"..."}]}。不要多余文字。"""


def plan_shotlist(
    script: str, character_desc: str, n_shots: int, client, model: str
) -> list[dict]:
    """LLM 拆剧本 → 镜头清单。返回 [{script, scene, motion}]。"""
    user = (
        f"【角色描述】{character_desc}\n【剧本/情境】{script}\n"
        f"拆成 {n_shots} 个镜头。记住 scene 要强调身份/服装一致。"
    )
    resp = client.chat.completions.create(
        model=model,
        messages=[{"role": "system", "content": SHOTLIST_SYS},
                  {"role": "user", "content": user}],
        max_tokens=2000,
        response_format={"type": "json_object"},
    )
    data = json.loads(resp.choices[0].message.content)
    shots = data.get("shots", [])
    if not shots:
        raise RuntimeError(f"导演未产出镜头清单: {data}")
    return shots


def produce_film(
    registry,
    recipes,
    store,
    character_image: str,
    character_desc: str,
    script: str,
    client,
    model: str,
    n_shots: int = 3,
    on_event=None,
) -> dict:
    """一段剧本 → 多镜头一致成片。返回 {character, shots:[{shot,keyframe,video}], errors}。"""
    def emit(msg):
        if on_event:
            on_event(msg)

    shots_plan = plan_shotlist(script, character_desc, n_shots, client, model)
    emit(f"导演拆出 {len(shots_plan)} 个镜头")

    # 角色档案(Character Bible):此定稿作为身份锚点,后续镜头自动注入
    char = store.add_character(
        name=character_desc[:20], source="text",
        finals=[character_image], trigger="",
    )

    comfy = registry.route("edit").client  # 交互式 → 5090(edit/i2v 同后端)
    results = []
    for i, sp in enumerate(shots_plan):
        shot = store.add_shot(
            script=sp.get("script", ""), refs=[char["id"]],
            scene_prompt=sp.get("scene", ""), motion_prompt=sp.get("motion", ""),
        )
        emit(f"镜头 {i+1}/{len(shots_plan)}: {sp.get('script','')[:40]}")
        res = shot_to_video(
            comfy, recipes, store, character_image,
            sp.get("scene", ""), sp.get("motion"),
            seed=42 + i, shot_id=shot["id"],
        )
        if res.get("keyframe"):
            store.set_keyframe(shot["id"], res["keyframe"])
        if res.get("video"):
            store.add_take(shot["id"], res["video"],
                           meta={"backend": "local-5090", "seed": 42 + i,
                                 "recipe": "keyframe_edit+i2v_local"})
        results.append({"shot": shot["id"], "keyframe": res.get("keyframe"),
                        "video": res.get("video"), "errors": res.get("errors", [])})
    return {"character": char["id"], "shots": results}
