# 缺失模型清单（5090 做"参考图生视频"等能力，按需补）

> 现状基线见 [env-survey.md](env-survey.md) / [spike-m2-results.md](spike-m2-results.md)。
> **下载方式（已更正）**：本会话**可直接 `wget` 下载到 5090 的 ComfyUI models 目录** —— ComfyUI 容器以 `zhangnan` 运行、overlay fs 可写，经 SSH 到 `/proc/<comfyui-pid>/root/comfy/mnt/ComfyUI/models/<子目录>/` 写入即可（host 通 HuggingFace，models 盘余 ~675G）。
> （早先"无权下载"的说法**有误**：那是因为我去 `ls /opt/comfyui-toolkit/models` 被拒——那是个无关的 host 路径，并非运行中 ComfyUI 实际读取的 models 目录。）
> 由用户决定下哪些（大小 1–20GB 不等）；大小为粗估，下载前以 HF 实际为准。

## 已经能做（无需下载）
- **关键帧→视频 i2v**：WAN 2.2 `ti2v_5B` / `i2v_14B`（已装）。单张角色定稿→视频，身份从首帧保持。**已验证**（5B，704²，3.4s，32s 出片）。
- **云 reference-to-video**：ComfyUI 已带 即梦(Seedance)/可灵/Vidu/Runway/Veo partner 节点，**配 API key 即用**，零下载（计费）。

## 按能力的缺失清单

| 能力 | 节点 | 缺什么 | 粗估 | 优先级 | 说明 |
|---|---|---|---|---|---|
| i2v 14B **4 步加速** | 已装 | `wan2.2_i2v_lightx2v_4steps` high+low LoRA | ~1.2GB | ★★★ | 仅提速，14B 模型本身已装；性价比最高 |
| **角色动画**(参考+姿态/表情驱动) | `WanAnimateToVideo` | Wan2.2-Animate 权重 + 姿态/人脸检测(dwpose 等) | ~10–20GB | ★★★ | 最像可灵/即梦"让我的角色做这个动作" |
| **多参考主体→视频** | `WanPhantomSubjectToVideo` | Phantom-Wan 权重 | ~数GB | ★★ | 多张定妆照→主体一致视频 |
| WAN **Fun 控制**(姿态/深度/inpaint/相机) | Fun* | wan2.2 fun_control/inpaint/camera 模型 | 各~数GB | ★★ | 构图/运镜一致控制 |
| **图像身份锁** IPAdapter | IPAdapter* | ip-adapter 模型(clip_vision_h 已装) | ~1–2GB | ★ | 多为 SD/SDXL/Flux.1;**2026 新基模(Z-Image/Flux-2)未必适配** |
| **图像身份锁** InstantID / PuLID | InstantID*/PuLID* | InstantID/PuLID-Flux 模型 + 人脸分析(antelopev2/EVA-CLIP) | 各~2–3GB | ★ | 同上,基模适配风险高(设计因此改走 LoRA) |
| **参考编辑**(角色入场景做关键帧) | TextEncodeQwenImageEdit | `qwen_image_edit_2511_bf16` 基模 | ~20GB | ★ | 装机只有 edit LoRA,缺基模 |
| **Flux-2 Klein** 作图/训练/edit | UNETLoader(已装) | `qwen_3_8b_fp8mixed` 文本编码器 + `flux2-vae`(full_encoder_small_decoder) | ~8–10GB | ★★ | 装机缺 vae+文本编码器;补齐可换非 distilled 基模训更强 LoRA |

来源：WAN 系 → HF `Comfy-Org/Wan_2.2_ComfyUI_Repackaged` 与 `Wan-AI`；Flux-2 → `black-forest-labs` / `Comfy-Org/flux2-klein-9B`；Qwen edit → `Comfy-Org/Qwen-Image-Edit_ComfyUI`；IPAdapter/InstantID/PuLID → 各自官方 repo。

## 推荐补齐顺序（给定 5090 + DGX 120G）
1. **lightx2v 4 步 LoRA**（~1.2GB，提速 14B i2v，立竿见影）。
2. **Wan2.2-Animate**（动作驱动角色视频 = 最像云服务的能力）。
3. **云 key（即梦/Vidu）** —— 零下载，作为强一致视频的兜底/对照。
4. **Flux-2 Klein 依赖（~10GB）** —— 若要把"角色 LoRA"做强（高分辨率训练；DGX 带宽受限慢，优先**租云 GPU**）。
5. IPAdapter/InstantID/PuLID 谨慎（基模适配风险）；Qwen edit 基模(20GB)按需。
