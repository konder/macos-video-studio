#!/usr/bin/env python3
"""本地文生视频(t2v)测试 CLI —— 自由选不同本地视频模型,纯文字出视频。

直连 5090 的 ComfyUI(默认 localhost:8188;从别处跑用 --comfy http://10.10.10.2:8188)。

用法:
  python t2v.py --list                                  # 列出可选模型
  python t2v.py --model wan5b --prompt "夕阳下海边奔跑的金毛犬"
  python t2v.py --model wan14b-high --prompt "..." --length 49 --width 832 --height 480
  常用参数: --steps 20 --cfg 5 --shift 8 --fps 16 --seed 0(0=随机) --out out.mp4
"""
import argparse
import json
import os
import time
import urllib.parse
import urllib.request
import uuid

# 模型预设(WAN 全家同一图,差 unet/vae/shift)。其余家族(Hunyuan/LTXV)待加。
PRESETS = {
    "wan5b":       {"unet": "wan2.2_ti2v_5B_fp16.safetensors",            "vae": "wan2.2_vae.safetensors", "shift": 8.0, "steps": 20, "cfg": 5.0},
    "wan14b-high": {"unet": "wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors", "vae": "wan_2.1_vae.safetensors", "shift": 5.0, "steps": 20, "cfg": 5.0},
    "wan14b-low":  {"unet": "wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors",  "vae": "wan_2.1_vae.safetensors", "shift": 5.0, "steps": 20, "cfg": 5.0},
}
NEG = "色调艳丽，过曝，静态，细节模糊不清，最差质量，低质量，畸形的，毁容的，手指融合，静止不动的画面"


def build_graph(p, prompt, w, h, length, fps, steps, cfg, shift, seed):
    return {"nodes": {
        "37": {"class_type": "UNETLoader", "inputs": {"unet_name": p["unet"], "weight_dtype": "default"}, "pos": [0, 0]},
        "38": {"class_type": "CLIPLoader", "inputs": {"clip_name": "umt5_xxl_fp8_e4m3fn_scaled.safetensors", "type": "wan", "device": "default"}, "pos": [0, 0]},
        "39": {"class_type": "VAELoader", "inputs": {"vae_name": p["vae"]}, "pos": [0, 0]},
        "48": {"class_type": "ModelSamplingSD3", "inputs": {"model": ["37", 0], "shift": shift}, "pos": [0, 0]},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["38", 0], "text": prompt}, "pos": [0, 0]},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["38", 0], "text": NEG}, "pos": [0, 0]},
        "55": {"class_type": "Wan22ImageToVideoLatent", "inputs": {"vae": ["39", 0], "width": w, "height": h, "length": length, "batch_size": 1}, "pos": [0, 0]},
        "3": {"class_type": "KSampler", "inputs": {"model": ["48", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["55", 0],
              "seed": seed, "steps": steps, "cfg": cfg, "sampler_name": "uni_pc", "scheduler": "simple", "denoise": 1.0}, "pos": [0, 0]},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["39", 0]}, "pos": [0, 0]},
        "57": {"class_type": "CreateVideo", "inputs": {"images": ["8", 0], "fps": fps}, "pos": [0, 0]},
        "58": {"class_type": "SaveVideo", "inputs": {"video": ["57", 0], "filename_prefix": "t2v_test", "format": "auto", "codec": "auto"}, "pos": [0, 0]},
    }}


def to_prompt(ir):
    return {nid: {"class_type": n["class_type"], "inputs": n["inputs"]} for nid, n in ir["nodes"].items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--comfy", default=os.environ.get("COMFY_URL", "http://localhost:8188"))
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--model", default="wan5b")
    ap.add_argument("--prompt", default="")
    ap.add_argument("--width", type=int, default=832)
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--length", type=int, default=49)
    ap.add_argument("--fps", type=int, default=16)
    ap.add_argument("--steps", type=int)
    ap.add_argument("--cfg", type=float)
    ap.add_argument("--shift", type=float)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    base = a.comfy.rstrip("/")

    if a.list:
        print("可选模型(--model):")
        for k, v in PRESETS.items():
            print(f"  {k:14s} {v['unet']}")
        return
    if not a.prompt:
        print("请用 --prompt 给文字描述(--list 看模型)"); return
    if a.model not in PRESETS:
        print(f"未知模型 {a.model};可选: {', '.join(PRESETS)}"); return

    p = PRESETS[a.model]
    seed = a.seed or uuid.uuid4().int % 2_000_000_000
    ir = build_graph(p, a.prompt, a.width, a.height, a.length, a.fps,
                     a.steps or p["steps"], a.cfg or p["cfg"], a.shift or p["shift"], seed)
    cid = uuid.uuid4().hex
    body = json.dumps({"prompt": to_prompt(ir), "client_id": cid}).encode()
    req = urllib.request.Request(base + "/prompt", data=body, headers={"Content-Type": "application/json"})
    pid = json.loads(urllib.request.urlopen(req, timeout=60).read())["prompt_id"]
    print(f"[{a.model}] seed={seed} {a.width}x{a.height} {a.length}帧@{a.fps}fps  prompt_id={pid}\n生成中(WAN 视频较慢,请耐心)…")

    t0 = time.time()
    while time.time() - t0 < 1800:
        time.sleep(3)
        h = json.loads(urllib.request.urlopen(base + f"/history/{pid}", timeout=30).read())
        if pid in h:
            rec = h[pid]
            st = rec.get("status", {})
            if st.get("status_str") == "error":
                print("执行出错:", json.dumps(st, ensure_ascii=False)[:500]); return
            for out in rec.get("outputs", {}).values():
                items = out.get("videos", []) + out.get("gifs", []) + out.get("images", [])
                for item in items:
                    if not (isinstance(item, dict) and item.get("filename")):
                        continue
                    url = base + "/view?" + urllib.parse.urlencode({k: item[k] for k in ("filename", "subfolder", "type") if k in item})
                    data = urllib.request.urlopen(url, timeout=120).read()
                    out_path = a.out or os.path.expanduser(f"~/t2v_out/t2v_{a.model}_{int(time.time())}.mp4")
                    d = os.path.dirname(out_path)
                    if d:
                        os.makedirs(d, exist_ok=True)
                    with open(out_path, "wb") as f:
                        f.write(data)
                    print(f"✓ 完成({int(time.time()-t0)}s)→ {out_path}  ({len(data)//1024} KB)")
                    return
            print("完成但无视频产物:", json.dumps(rec.get("outputs", {}), ensure_ascii=False)[:300]); return
        print(f"  …{int(time.time()-t0)}s", end="\r")
    print("超时")


if __name__ == "__main__":
    main()
