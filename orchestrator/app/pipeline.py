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


def train_character_lora(
    registry,
    image_paths: list[str],
    trigger: str,
    prefix: str = "char_lora",
    resolution: int = 512,
    steps: int = 400,
    rank: int = 16,
    lr: float = 2e-4,
    backend_name: str | None = None,
) -> dict:
    """角色 LoRA 训练，默认路由到 DGX(大显存,破 5090 的 256² 上限)。

    image_paths: 训练集(本地路径,一致角色的多视角/表情图)。
    trigger:     触发词(如 'sks woman')。
    返回 {"backend": name, "lora": 保存文件名前缀, "prompt_id": ...}.
    动态按图数量建训练图:LoadImage×N → ImageBatch 链 → ImageScale → MakeTrainingDataset → TrainLoraNode → SaveLoRA。
    """
    backend = registry.get(backend_name) if backend_name else registry.route(
        "train", prefer_latency="slow"
    )
    comfy = backend.client
    names = [comfy.upload_image(Path(p).read_bytes(), os.path.basename(p)) for p in image_paths]
    caption = f"{trigger}, character portrait"

    g: dict = {
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "clip": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b_fp8_mixed.safetensors", "type": "lumina2", "device": "default"}},
        "unet": {"class_type": "UNETLoader", "inputs": {"unet_name": "z_image_turbo_bf16.safetensors", "weight_dtype": "default"}},
    }
    load_ids = []
    for i, nm in enumerate(names):
        nid = f"img{i}"
        g[nid] = {"class_type": "LoadImage", "inputs": {"image": nm}}
        load_ids.append(nid)
    batch = load_ids[0]
    for i in range(1, len(load_ids)):
        nid = f"batch{i}"
        g[nid] = {"class_type": "ImageBatch", "inputs": {"image1": [batch, 0], "image2": [load_ids[i], 0]}}
        batch = nid
    g["scale"] = {"class_type": "ImageScale", "inputs": {"image": [batch, 0], "upscale_method": "lanczos", "width": resolution, "height": resolution, "crop": "disabled"}}
    g["ds"] = {"class_type": "MakeTrainingDataset", "inputs": {"images": ["scale", 0], "vae": ["vae", 0], "clip": ["clip", 0], "texts": "\n".join([caption] * len(names))}}
    g["train"] = {"class_type": "TrainLoraNode", "inputs": {
        "model": ["unet", 0], "latents": ["ds", 0], "positive": ["ds", 1],
        "batch_size": 1, "grad_accumulation_steps": 1, "steps": steps, "learning_rate": lr,
        "rank": rank, "optimizer": "AdamW", "loss_function": "MSE", "seed": 42,
        "training_dtype": "bf16", "lora_dtype": "bf16", "quantized_backward": False,
        "algorithm": "LoRA", "gradient_checkpointing": True, "checkpoint_depth": 1,
        "offloading": False, "existing_lora": "[None]", "bucket_mode": False, "bypass_mode": False}}
    g["save"] = {"class_type": "SaveLoRA", "inputs": {"lora": ["train", 0], "prefix": f"loras/{prefix}"}}

    pid = comfy.submit(g)
    history = comfy.wait(pid, timeout=3600.0)
    status = history.get("status", {})
    ok = status.get("completed") or status.get("status_str") == "success"
    return {"backend": backend.name, "resolution": resolution, "steps": steps,
            "prompt_id": pid, "ok": bool(ok), "lora_prefix": prefix}


def keyframe_compose(
    comfy, store, ref_paths: list[str], prompt: str,
    seed: int = 42, prefix: str = "keyframe",
) -> dict:
    """多资产组合关键帧:用 Qwen-Image-Edit 多图参考(image1/2/3)把 角色+服装+背景 等
    组合进一张关键帧。ref_paths[0]=主参考(通常角色,提供 latent),其余为服装/背景/道具。

    prompt 里用 "image 1 / image 2 / ..." 指代各参考,并强调保持角色身份/服装一致。
    返回 {"keyframe": path, "errors": [...]}.
    """
    refs = ref_paths[:3]  # Qwen-edit Plus 支持至多 3 图
    names = [comfy.upload_image(Path(p).read_bytes(), os.path.basename(p)) for p in refs]

    g: dict = {
        "unet": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_edit_2511_fp8mixed.safetensors", "weight_dtype": "default"}},
        "lora": {"class_type": "LoraLoaderModelOnly", "inputs": {"model": ["unet", 0], "lora_name": "qwen/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors", "strength_model": 1.0}},
        "msa": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["lora", 0], "shift": 3.1}},
        "cfgn": {"class_type": "CFGNorm", "inputs": {"model": ["msa", 0], "strength": 1.0}},
        "clip": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors", "type": "qwen_image", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_vae.safetensors"}},
    }
    img_inputs: dict = {}
    for i, nm in enumerate(names):
        g[f"load{i}"] = {"class_type": "LoadImage", "inputs": {"image": nm}}
        g[f"scale{i}"] = {"class_type": "FluxKontextImageScale", "inputs": {"image": [f"load{i}", 0]}}
        img_inputs[f"image{i+1}"] = [f"scale{i}", 0]

    pos_enc = {"clip": ["clip", 0], "prompt": prompt, "vae": ["vae", 0], **img_inputs}
    g["pos_enc"] = {"class_type": "TextEncodeQwenImageEditPlus", "inputs": pos_enc}
    g["pos"] = {"class_type": "FluxKontextMultiReferenceLatentMethod", "inputs": {"conditioning": ["pos_enc", 0], "reference_latents_method": "index_timestep_zero"}}
    g["neg_enc"] = {"class_type": "TextEncodeQwenImageEditPlus", "inputs": {"clip": ["clip", 0], "prompt": "", "vae": ["vae", 0], "image1": ["scale0", 0]}}
    g["neg"] = {"class_type": "FluxKontextMultiReferenceLatentMethod", "inputs": {"conditioning": ["neg_enc", 0], "reference_latents_method": "index_timestep_zero"}}
    g["enc"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["scale0", 0], "vae": ["vae", 0]}}
    g["k"] = {"class_type": "KSampler", "inputs": {"model": ["cfgn", 0], "positive": ["pos", 0], "negative": ["neg", 0], "latent_image": ["enc", 0], "seed": seed, "steps": 4, "cfg": 1.0, "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}}
    g["dec"] = {"class_type": "VAEDecode", "inputs": {"samples": ["k", 0], "vae": ["vae", 0]}}
    g["save"] = {"class_type": "SaveImage", "inputs": {"images": ["dec", 0], "filename_prefix": prefix}}

    res = run_ir({"nodes": {k: {"class_type": v["class_type"], "inputs": v["inputs"], "pos": [0, 0]} for k, v in g.items()}}, comfy, store)
    if res.get("error") or not res["assets"]:
        return {"keyframe": None, "errors": [res.get("error", "compose 无产物")]}
    return {"keyframe": res["assets"][0], "errors": []}


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
