"""导演 Agent（阶段3）：拆剧本 → 镜头清单 → 逐镜头注入角色档案 → 批量出片。

对应 agent-system §1 的「导演/制片 Agent」。拆镜用 LLM(经 LiteLLM)；每镜头复用阶段1
一致性管线(Qwen-edit 关键帧 → WAN i2v),角色档案自动注入,后端经 registry 路由(交互→5090)。
"""
from __future__ import annotations

import json
import os

from .pipeline import keyframe_compose, shot_to_video


SHOTLIST_SYS = """你是一位影视导演 + 分镜师。给定【角色描述】、可选【资产库】(服装/背景/道具等,每个有 id)和一段【剧本/情境】,把它拆成有序的镜头清单。
每个镜头输出:
- script: 该镜头中文简述。
- scene: 给图像编辑模型的英文指令。镜头会以"图1=角色"为主参考;若该镜头用到资产库里的资产,
  它们按顺序是"图2、图3…"。指令里用 image 1 / image 2 指代,**务必强调保持角色面部/发型/身份一致
  (keep the character's face, hairstyle and identity identical and unchanged)**,补足场景/构图/光线/景别。
- motion: 给图生视频模型的镜头动作/运镜英文描述(自然、电影感,3-5 秒)。
- use_assets: 该镜头要用到的资产 id 列表(从【资产库】里选,最多 2 个;没有则空数组)。
只输出 JSON: {"shots":[{"script":"...","scene":"...","motion":"...","use_assets":["id",...]}]}。不要多余文字。"""


def plan_shotlist(
    script: str, character_desc: str, n_shots: int, client, model: str,
    assets: list[dict] | None = None,
) -> list[dict]:
    """LLM 拆剧本 → 镜头清单(可关联资产)。返回 [{script, scene, motion, use_assets}]。"""
    lib = ""
    if assets:
        lib = "【资产库】\n" + "\n".join(
            f"- {a['id']} ({a.get('type')}): {a.get('name')}" for a in assets
        ) + "\n"
    user = (
        f"【角色描述】{character_desc}\n{lib}【剧本/情境】{script}\n"
        f"拆成 {n_shots} 个镜头。scene 要强调角色身份一致;合适时为镜头选用资产(use_assets)。"
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
    assets: list[dict] | None = None,
    on_event=None,
) -> dict:
    """一段剧本 → 多镜头一致成片(导演可自动为镜头编排资产)。

    assets: 可选资产库 [{id,type,name,image}](服装/背景/道具)。导演按镜头从中选用,
            选中则用 keyframe_compose 把 角色+资产 组合注入;否则单角色 shot_to_video。
    返回 {character, shots:[{shot,keyframe,video,use_assets}], errors}。
    """
    def emit(msg):
        if on_event:
            on_event(msg)

    assets = assets or []
    asset_by_id = {a["id"]: a for a in assets}
    shots_plan = plan_shotlist(script, character_desc, n_shots, client, model, assets=assets)
    emit(f"导演拆出 {len(shots_plan)} 个镜头" + (f"(资产库 {len(assets)} 项)" if assets else ""))

    char = store.add_character(
        name=character_desc[:20], source="text", finals=[character_image], trigger="",
    )
    comfy = registry.route("edit").client  # 交互式 → 5090

    from .pipeline import shot_to_video as _s2v
    results = []
    for i, sp in enumerate(shots_plan):
        use_ids = [aid for aid in sp.get("use_assets", []) if aid in asset_by_id]
        shot = store.add_shot(
            script=sp.get("script", ""), refs=[char["id"], *use_ids],
            scene_prompt=sp.get("scene", ""), motion_prompt=sp.get("motion", ""),
        )
        emit(f"镜头 {i+1}/{len(shots_plan)}: {sp.get('script','')[:36]}"
             + (f" +资产{use_ids}" if use_ids else ""))

        if use_ids:
            # 多资产组合:角色 + 选中资产 → keyframe_compose
            refs = [character_image] + [asset_by_id[a]["image"] for a in use_ids]
            kf = keyframe_compose(comfy, store, refs, sp.get("scene", ""),
                                  seed=42 + i, prefix=f"{shot['id']}_keyframe")
            if kf.get("keyframe"):
                store.set_keyframe(shot["id"], kf["keyframe"])
                # 关键帧 → i2v
                from .pipeline import _upload
                from .tools import run_ir, validate_ir
                iv_name = _upload(comfy, kf["keyframe"])
                ir = recipes.instantiate("i2v_local", {
                    "input_image": iv_name, "seed": 42 + i,
                    "motion_prompt": sp.get("motion") or
                    "the subject moves naturally with subtle expression and gentle camera motion",
                    "filename_prefix": f"{shot['id']}_take"})
                errs = validate_ir(ir, comfy.object_info())
                res = run_ir(ir, comfy, store) if not errs else {"assets": [], "error": errs}
                video = res["assets"][0] if res.get("assets") else None
                errors = [] if video else [res.get("error", "i2v 无产物")]
            else:
                video, errors = None, kf.get("errors", [])
            res_kf = kf.get("keyframe")
        else:
            r = _s2v(comfy, recipes, store, character_image, sp.get("scene", ""),
                     sp.get("motion"), seed=42 + i, shot_id=shot["id"])
            res_kf, video, errors = r.get("keyframe"), r.get("video"), r.get("errors", [])
            if res_kf:
                store.set_keyframe(shot["id"], res_kf)

        if video:
            store.add_take(shot["id"], video, meta={"backend": "local-5090", "seed": 42 + i,
                           "recipe": "keyframe_compose+i2v" if use_ids else "keyframe_edit+i2v"})
        results.append({"shot": shot["id"], "keyframe": res_kf, "video": video,
                        "use_assets": use_ids, "errors": errors})
    return {"character": char["id"], "shots": results}
