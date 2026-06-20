# M2 一致性 spike 结果（写实线）

> 对应 [spike-plan.md](spike-plan.md) M2。目标：验证「定稿 → 一致性方法 → 跨场景」的角色身份保持。
> 环境：RTX 5090 32G · ComfyUI 0.24 · 见 [env-survey.md](env-survey.md)。

## 关键环境约束（本次新发现，影响方法选型）

| 一致性路线 | 装机现状 | 结论 |
|---|---|---|
| **Track A · 角色 LoRA** | `TrainLoraNode` 全套 + Z-Image Turbo 基模已装 | ✅ 可跑，但受显存约束（见下） |
| **Track B · Qwen-Image-Edit**（参考编辑对照） | 只有 Edit **LoRA** + Qwen-Image **layered**；缺 edit 基模 `qwen_image_edit_2511_bf16`（~20GB） | ⛔ 缺基模 |
| **Track C · Flux-2 原生参考/KV 编辑** | diffusion 已装；缺 `qwen_3_8b` 文本编码器 + `flux2-vae`（~8–10GB） | ⛔ 缺依赖 |
| **WAN i2v 链路验证** | i2v 14B + vae + clip_vision 已装 | ✅ 可跑（本轮未跑，见待办） |

- **显存瓶颈（重要）**：32GB 下 `TrainLoraNode` 训 Z-Image **只在 256² 跑得动，512² OOM**（bf16 ~6B 模型 + 训练激活峰值超 32G，offloading/quantized_backward 仍不够）。256² 训练分辨率会损失人脸细节，限制 LoRA 上限。
- **基模非理想**：装机唯一完整可训的 Z-Image Turbo 是 **distilled turbo**（8 步 / cfg=1），并非理想训练基模；理想的 Flux-2 Klein 还缺 ~8–10GB 依赖。

## Track A 实测（角色 LoRA）

1. **训练集 bootstrap**（无 IPAdapter/edit 模型下）：用 **Z-Image img2img 共享潜变量** 从 1 张定稿派生 9 张身份一致的多视角/表情图（denoise 0.50–0.58）。身份保持良好。→ `spike-m2-assets/trainset.png`
2. **训练**：`MakeTrainingDataset → TrainLoraNode(Z-Image, 256², rank=8, lr=2e-4, AdamW, 500 步) → SaveLoRA`，耗时 **445s（~7.4 min）**，显存峰值 ~31.3G。
3. **评测**：LoRA+触发词 在 3 个新场景（咖啡馆 / 霓虹街道 / 办公室）出图，对照「同提示同种子但**无 LoRA**」的基线。→ `spike-m2-assets/lora-vs-baseline.png`、`face-compare.png`

**结果（主观 1–5）**：

| 指标 | LoRA | 基线(无 LoRA) |
|---|---|---|
| 身份与 anchor 相似 | **3 / 5**（脸型/眼型/肤质拉向 anchor） | 2 / 5（泛化年轻东亚女性，漂移明显） |
| 跨场景自一致 | **3.5 / 5** | 2 / 5 |
| 服装/风格保持 | 受提示控制，未锁定 | — |
| 训练成本 | 256² / 500 步 / 7.4 min | 0 |

**判读**：即便在 256² 的显存约束下，LoRA 也产生了**可见的中等身份迁移**——LoRA 行的脸明显比基线更像 anchor、彼此也更一致。但**不是硬锁定**；要更强一致需更高训练分辨率（需更多显存或外部训练器）、更多步数、以及非 distilled 基模。

> 定量身份相似度（face embedding 距离）本轮未做——Mac 端未装 arcface/insightface。属待办。

## 另一条路：参考条件（tuning-free，无需 LoRA）

公网服务（即梦/通义万相/可灵/Vidu）从几张定妆照+场景图出强一致视频，靠的**不是 per-角色 LoRA**，而是**参考图当条件**的免训练主体驱动生成（IP-Adapter / ReferenceNet / DiT in-context KV 注入；脸用 ArcFace 类 embedding）。一次性大规模预训练把"保身份"内化进基模，推理零训练、秒级。

这正是设计 A2 原想用的 IPAdapter/InstantID/PuLID 那一类（A1 摸机发现本机没装才改走 LoRA）。但**我们手上有等价能力未用**：
- **本地**：WAN 2.2 `WanPhantomSubjectToVideo` / `WanAnimateToVideo`（主体参考→视频）、Flux-2 KV 编辑——需补对应权重。
- **云端**：ComfyUI 已带 即梦/可灵/Vidu/Runway partner 节点，**配 key 即用**，直接就是"定妆照+场景图→强一致视频"。

## 结论与 MVP 建议

- **本机 LoRA 受这块卡的显存严重限制**（256² 天花板），写实线 LoRA 一致性目前只到"中等"。要把 LoRA 做强，需 ① 补 Flux-2 Klein 依赖换非 distilled 基模，且 ② 上外部训练器/更高显存以突破 256²。
- **更省力的 MVP 一致性路径很可能是「参考条件」而非本地 LoRA**：视频侧用 **云端 reference-to-video（即梦/Vidu）** 或 **本地 WAN Phantom/Animate**；LoRA 留给需要高保真的主角。
- 建议把"参考条件路线"提为 LoRA 的**并列候选**（已记入 [open-questions.md](open-questions.md) A2）。

## 待办（完成 M2 需要）

- [ ] **链路验证**：取最佳 LoRA 关键帧 → **WAN 2.2 i2v 14B** 出 3–5s，看身份是否在视频里保持（spike-plan「关键」项，本轮未跑）。
- [ ] 定量身份相似度（装 insightface 算 embedding 距离）。
- [ ] 若决定走参考条件：补 WAN Phantom/Animate 权重（本地）或接通即梦/Vidu 云节点（M6）。
- [ ] 若坚持 LoRA 主线：补 Flux-2 Klein 依赖（~8–10GB）+ 评估外部训练器突破 256²。
