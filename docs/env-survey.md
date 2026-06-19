# 5090 ComfyUI 环境调研清单（A1）

> 目的：摸清那台 RTX 5090 Linux 机器上 ComfyUI 的真实能力，作为配方库、一致性选型、视频管线的事实依据。
> **执行方式**：对有 ComfyUI 机器 SSH + HTTP 访问的 agent，按下面逐项跑，把结果回填到文末「报告」。
> 设 `COMFY=http://<5090-ip>:8188`（按实际改）。

---

## 0. 连通性
- [ ] `curl -s $COMFY/system_stats` 能返回 JSON？（确认 ComfyUI 在跑、可达）

## 1. 硬件 / 驱动
- [ ] `nvidia-smi`（GPU 型号、显存总量、驱动版本、CUDA 版本）
- [ ] `uname -a`、`cat /etc/os-release`（系统 / 内核）

## 2. ComfyUI 本体 / 运行时
- [ ] ComfyUI 版本：在其目录 `git -C <comfyui> describe --tags --always` + `git -C <comfyui> log -1 --format=%cd`
- [ ] `python --version`；`pip show torch | grep -E 'Version|Location'`（torch / CUDA 构建）
- [ ] `curl -s $COMFY/system_stats`（含显存、torch、python；存档）
- [ ] **`curl -s $COMFY/object_info > object_info.json`** ← 最关键：全部节点 schema。报告其大小与节点总数
      （`python -c "import json;print(len(json.load(open('object_info.json'))))"`）

## 3. 模型清单（列目录 + 大小）
对 `<comfyui>/models/` 下各子目录 `ls -lah`，报告文件名+大小：
- [ ] `checkpoints/`、`unet/`、`diffusion_models/`（找 **Flux** / **SDXL** / **Qwen-Image** / SD1.5 等基模）
- [ ] `vae/`、`clip/`、`clip_vision/`、`text_encoders/`
- [ ] `loras/`（已有哪些 LoRA）
- [ ] `controlnet/`
- [ ] `ipadapter/`、`instantid/`、`pulid/`（一致性相关权重）
- [ ] `upscale_models/`（超分）、`embeddings/`
- [ ] 视频相关：`diffusion_models/` 或专用目录里有无 **Wan**（2.1 / 2.2？）/ 其它 i2v 权重

## 4. 自定义节点
- [ ] `ls <comfyui>/custom_nodes/`（列全部）
- [ ] 重点确认是否安装（在 `object_info.json` 里按关键词筛节点类名）：
  - IPAdapter：`IPAdapter*`
  - InstantID：`InstantID*` / `ApplyInstantID*`
  - PuLID：`PuLID*` / `ApplyPulid*`
  - ControlNet：`ControlNet*` / `ControlNetApply*` / `*Aux*`（preprocessors）
  - 视频 / Wan：`Wan*` / `*VideoSampler*` / `*ImageToVideo*` / `AnimateDiff*`
  - 补帧 / 超分：`RIFE*` / `FILM*` / `*Upscale*`
  - LoRA 训练：有无训练用节点或外部脚本（如 kohya / ai-toolkit）

## 5. 视频能力专项
- [ ] 有无可用的**图生视频**链路（Wan 或其它）？对应节点名、所需模型是否齐。
- [ ] 支持的输出规格（分辨率 / 帧数 / 时长上限）、首尾帧（start/end frame）是否支持。

## 6. 一致性能力专项
- [ ] IPAdapter / InstantID / PuLID / ControlNet **四类是否齐**（权重 + 节点都在）。
- [ ] 能否在本机**训练角色 LoRA**（有训练链路 / 显存够）？

## 7. 冒烟测试（确认真能出图）
- [ ] 用已装基模跑一张最简 txt2img（可用 ComfyUI 自带默认 workflow / `/prompt` 提交），确认成功出图并记录耗时。
- [ ] 若有 i2v 链路，跑一段最短图生视频，记录是否成功、耗时、显存峰值。

---

## 报告（回填）

| 项 | 结果 |
|---|---|
| ComfyUI 可达 / 版本 | |
| GPU / 显存 / 驱动 / CUDA | |
| torch / python | |
| object_info 节点总数 | |
| 基础模型（checkpoints/unet/flux/sdxl/qwen…） | |
| VAE / CLIP / clip_vision | |
| 视频模型（Wan 版本 / 其它 i2v） | |
| LoRA（已有 / 能否训练） | |
| IPAdapter / InstantID / PuLID / ControlNet | |
| 超分 / 补帧 | |
| 全部 custom_nodes 列表 | |
| txt2img 冒烟（成功？耗时） | |
| i2v 冒烟（成功？耗时 / 显存） | |
| 其它发现 / 坑 | |

> 回填后，据此敲定：① 配方库初始清单（[agent-system.md](agent-system.md) §3）；② 一致性 spike 组合（A2）；
> ③ M1 用哪台 ComfyUI、出哪张定稿图。
