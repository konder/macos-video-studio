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
- [ ] `checkpoints/`、`unet/`、`diffusion_models/`（**写实 + 二次元都要**：写实基模 **Flux** / **SDXL** /
      **Qwen-Image** / SD1.5；二次元基模 **Pony** / **Illustrious** / **NoobAI** / 动漫向 SDXL·Flux）
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

## 6. 一致性能力专项（**写实 + 二次元都要**，方法按风格分）
- [ ] **写实 / 真人脸**：InstantID / PuLID / IPAdapter-FaceID（人脸识别）—— 权重 + 节点是否齐。
- [ ] **二次元 / 风格化**：IPAdapter（通用参考）+ **角色 LoRA**（强一致）—— 人脸识别类对二次元多不适用。
- [ ] **通用**：ControlNet（构图 / 姿态控制），两风格都用。
- [ ] 能否在本机**训练角色 LoRA**（训练链路如 kohya / ai-toolkit、显存够）？—— 二次元一致性常依赖它。

## 7. 冒烟测试（确认真能出图）
- [ ] 用已装基模跑一张最简 txt2img（可用 ComfyUI 自带默认 workflow / `/prompt` 提交），确认成功出图并记录耗时。
- [ ] 若有 i2v 链路，跑一段最短图生视频，记录是否成功、耗时、显存峰值。

---

## 报告（回填）

| 项 | 结果（2026-06 回填） |
|---|---|
| ComfyUI 可达 / 版本 | ✅ `http://10.10.10.2:8188` · v0.24.0 · 前端 1.44.19 |
| GPU / 显存 / 驱动 / CUDA | RTX 5090 · 32 GB（~32.4 GB 空闲）· 驱动 595.71.05 · CUDA 13.2 · RAM 48 GB |
| torch / python | Python 3.12.3 · PyTorch 2.12.0+cu130 |
| object_info 节点总数 | 762 |
| 基础模型（图像） | **Flux-2 Klein 9B** fp8 · **Qwen-Image**(layered) · **Z-Image Turbo** bf16 ｜ ⚠️ 无专用二次元基模 |
| 基础模型（视频） | **WAN 2.2**（i2v + t2v 14B high/low + ti2v 5B）· HunyuanVideo 1.5（1080p SR + 720p t2v）· LTXV 13B 0.9.8 |
| VAE / CLIP | Flux ae · WAN 2.1/2.2 vae · Hunyuan/LTXV/Qwen vae ｜ clip_l · t5xxl · umt5_xxl · qwen2.5-vl-7b · qwen3-4b · byt5 · **clip_vision_h** |
| LoRA | 有 Qwen-Image-Edit Lightning LoRA；**有 TrainLoraNode / SaveLoRA → 可本机训练** |
| IPAdapter / InstantID / PuLID | ❌ **节点和模型均未安装** |
| ControlNet | 节点在，但 `controlnet/` **无模型文件**（需下载） |
| 超分 / 补帧 | 超分 4x-UltraSharp ✓；补帧节点在但 **无 RIFE/FILM 模型**（需下载） |
| custom_nodes | Easy-Use · Manager · TextureAlchemy · WJNodes · NVIDIA-GenAI-Creator-Toolkit |
| 云 partner 节点 | **Kling · Runway · Luma · Sora · Vidu · Veo 等**（需配 API key）|
| txt2img 冒烟 | ⚠️ 链路正常（WAN T2V 加载+4 步采样 OK）；VAEDecode 因用错 latent 节点报错（配置问题，非环境问题）|
| i2v 冒烟 | 未跑（节点齐：WanImageToVideo / HunyuanVideo15ImageToVideo / LTXVImgToVideo）|
| 存储 / 其它 | ComfyUI 跑在**容器 namespace**（`/basedir` host 不可见）· 系统盘 1.8T(62%) · **NAS 37T 挂 `/mnt/nas`** · 启动含 `--use-sage-attention --fast --bf16-vae --bf16-text-enc` |

## 解读（对方案的影响）

1. **一致性方案要改向**（A2）：IPAdapter / InstantID / PuLID **都没装**，且它们多为 SDXL/Flux.1 时代产物，
   对这台机的 2026 新基模（Flux-2 / Qwen-Image / Z-Image）未必有适配。本机最稳的一致性杠杆其实是
   **① 本机训练角色 LoRA（TrainLoraNode 在）② Qwen-Image-Edit（参考编辑，适合把角色摆进场景）
   ③ 基模原生参考条件（Flux-2 / Qwen 待 spike 验证）**。A2 spike 改测这三条，而非 InstantID/PuLID。
2. **二次元缺专用基模**：图像基模偏写实/通用，没有 Pony/Illustrious 等动漫基模。要做好二次元，
   需下载一个动漫基模（或先用 Flux/Qwen 的动漫能力 + 角色 LoRA 顶着）。→ 待定 D7。
3. **云比预想的多**：除即梦/Qwen 外，ComfyUI 已带 Kling/Runway/Luma/Veo/Sora/Vidu partner 节点 →
   云视频可**直接作为 ComfyUI 节点**调用（配 key 即用），可能省掉大部分自研云适配器。→ 影响 A3/架构。
4. **视频主力 = WAN 2.2**（i2v 14B 定稿 / ti2v 5B 轻量草稿）；备选 Hunyuan 1.5 / LTXV。32G 显存够跑 14B fp8。
5. **存储**：项目文件夹放 **NAS（37T）**；Orchestrator 与 ComfyUI **走 HTTP 交互**（容器隔离、无共享盘），
   产物经 ComfyUI 输出口取回——印证「Orchestrator 不直接读 ComfyUI 文件系统」的设计。
6. **要补的料**：ControlNet 模型、补帧 RIFE/FILM 模型；按需再装 LoRA 训练所需依赖。

