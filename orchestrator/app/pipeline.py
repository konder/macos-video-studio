"""一致性管线(阶段1):角色定稿 → 关键帧(Qwen-edit 编进场景) → 视频(WAN i2v) → take。

这是 MVP 一致性默认路径(spike-summary 决策表),已 e2e 验证跨镜头一致。
人/Agent 都可调用;每步经 validate(对照 /object_info)再 run,产物落项目文件夹。
"""
from __future__ import annotations

import os
from pathlib import Path

from .tools import run_ir, validate_ir


def _upload(comfy, store_path: str) -> str:
    """把本地图(项目内路径)上传到 ComfyUI input,返回 input 内文件名。"""
    data = Path(store_path).read_bytes()
    return comfy.upload_image(data, os.path.basename(store_path))


def shot_to_video(
    comfy,
    recipes,
    store,
    character_image: str,
    scene_prompt: str,
    motion_prompt: str | None = None,
    seed: int = 42,
    shot_id: str = "shot",
) -> dict:
    """一个镜头:定稿角色 + 场景描述 → 关键帧 → 视频 take。

    character_image: 角色定稿图的本地路径(项目内)。
    scene_prompt:    编辑指令,如 "把这个人放进黄昏海边,保持面部/发型/服装不变"。
    motion_prompt:   视频动作描述(可省,用配方默认)。
    返回 {"keyframe": path, "video": path, "errors": [...]}.
    """
    oi = comfy.object_info()

    # 1) 关键帧:Qwen-edit 把定稿角色编进场景
    kf_name = _upload(comfy, character_image)
    ir_kf = recipes.instantiate(
        "keyframe_edit",
        {"input_image": kf_name, "prompt": scene_prompt, "seed": seed,
         "filename_prefix": f"{shot_id}_keyframe"},
    )
    errs = validate_ir(ir_kf, oi)
    if errs:
        return {"keyframe": None, "video": None, "errors": errs}
    res_kf = run_ir(ir_kf, comfy, store)
    if res_kf.get("error") or not res_kf["assets"]:
        return {"keyframe": None, "video": None, "errors": [res_kf.get("error", "keyframe 无产物")]}
    keyframe = res_kf["assets"][0]

    # 2) 视频:关键帧 → WAN i2v
    iv_name = _upload(comfy, keyframe)
    params = {"input_image": iv_name, "seed": seed, "filename_prefix": f"{shot_id}_take"}
    if motion_prompt:
        params["motion_prompt"] = motion_prompt
    ir_iv = recipes.instantiate("i2v_local", params)
    errs = validate_ir(ir_iv, oi)
    if errs:
        return {"keyframe": keyframe, "video": None, "errors": errs}
    res_iv = run_ir(ir_iv, comfy, store)
    if res_iv.get("error") or not res_iv["assets"]:
        return {"keyframe": keyframe, "video": None, "errors": [res_iv.get("error", "video 无产物")]}
    return {"keyframe": keyframe, "video": res_iv["assets"][0], "errors": []}
