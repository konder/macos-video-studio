# MVP 技术方案（实现规格）

> 把已冻结设计（[architecture](architecture.md) / [data-model](data-model.md) / [agent-system](agent-system.md) / [api-contract](api-contract.md) / [pipeline](pipeline.md)）+ 已验证 spike（[spike-summary](spike-summary.md)）收口为可编码的实现规格。开发计划见 [dev-plan.md](dev-plan.md)。

## 1. MVP 范围

资产（角色档案）→ 分镜 → 生成（关键帧→视频）→ 选片 → 导出工程。**单用户自用**；剪辑/音频/口型后置。SwiftUI 客户端为后续里程碑，MVP 先**后端 + 脚本/最小 UI 驱动**跑通整链。

## 2. 架构（落地形态）

```
CLI / (后续 SwiftUI)
   │ REST + SSE(Agent 流) + WS(进度)
Orchestrator (Python/FastAPI, 已起骨架 orchestrator/app)
   ├─ Agent 运行时(LiteLLM/OpenAI 兼容, tool-use)
   ├─ 配方库 + /object_info 校验
   ├─ 项目存储(项目文件夹 → NAS)
   └─ 后端路由器(backend registry)
        ├─ 5090 ComfyUI (10.10.10.2:8188)  ← 快速交互:图像/Qwen-edit/i2v
        ├─ DGX  ComfyUI (10.10.10.5:8188)  ← 大显存:LoRA 高分训练/大模型/批处理
        └─ 云适配器(即梦/Vidu/Qwen…)        ← reference-to-video/突发
```

**后端路由策略**：每后端 = 一个 ComfyUI HTTP 端点(或云适配器) + 能力标签(`txt2img/edit/i2v/train/...`) + 属性(`vram`, `latency`)。路由规则：
- 交互式图像 / Qwen-edit / i2v 草稿 → **5090**。
- LoRA 训练(高分) / 放不进 32G 的大模型 / 过夜批 → **DGX**。
- reference-to-video / 本地不具备 → **云**。
MVP 先实现 **5090 + DGX 两本地后端**的注册与按能力/显存路由；云适配器接口预留（M6 接通）。

## 3. 配方库（MVP 清单，贴已验证实装）

| 配方 id | 用途 | 关键实装（已验证） |
|---|---|---|
| `char_concept` | 文生图人物定稿 | Z-Image Turbo（8 步/cfg1/res_multistep）；备 Flux-2 Klein |
| `char_turnaround` | 多视角/训练集素材 | 同基模 + img2img 共享潜变量派生一致集 |
| `keyframe_edit` ★ | 把定稿角色编进场景出关键帧 | **Qwen-Image-Edit 2511**（fp8mixed + Lightning 4 步 LoRA + qwen_image_vae，CFGNorm+ModelSamplingAuraFlow shift3.1，4 步/cfg1） |
| `i2v_local` ★ | 关键帧→视频 | **WAN 2.2**：5B ti2v（草稿）/ 14B i2v + lightx2v 4 步（定稿，两段式 high→low） |
| `char_lora_train` | 角色 LoRA（主角高保真，可选） | `MakeTrainingDataset→TrainLoraNode→SaveLoRA`，**默认在 DGX 高分训练** |
| `interp_upscale` | 超分（+补帧后置） | 4x-UltraSharp（补帧 RIFE/FILM 待下） |

每配方 = `graph_template`(prompt 格式 + pos) + `params_schema` + 元数据；占位符 `{{name}}`，按 `params_schema` 填默认/类型；`validate` 对照 `/object_info`。配方文件落 `orchestrator/app/recipes/*.json`（`char_concept` 已就位，其余按本表补）。

## 4. 一致性管线（核心，已验证）

**角色档案（Character Bible 条目）** = 定稿图集 + 触发词 +（可选）角色 LoRA + 元数据。来源两种最终收敛为同一档案：文本→先文生图定稿；上传→直接为定稿图。

**每个镜头生成流程（默认路径）**：
1. 取镜头 refs（角色档案 + 场景/服装描述）。
2. **`keyframe_edit`**：定稿角色 → Qwen-edit 编进本镜头场景 → 关键帧（强身份保持）。
3. **`i2v_local`**：关键帧 → WAN i2v → 视频 take。
4.（主角可选）若该角色有 LoRA，则关键帧改由 LoRA+触发词生成，再 i2v。

导演 Agent 自动注入档案，用户不手设。e2e 已验证此路径跨镜头一致。

## 5. 数据模型 / 持久化（收口）

项目文件夹（[data-model §4](data-model.md)）：`project.json`（meta + Character Bible + Shots + 每镜头 Graph IR(prompt+pos)）+ `assets/` + `shots/<id>/{keyframes,takes,previews}` + `thumbnails/` + `exports/`。存 NAS。`project.json` schema 在 M3 定稿（角色/镜头/take 字段 + 后端/耗时/参数元数据）。

## 6. API 契约（收口，[api-contract](api-contract.md) 草案 → 实现）

- REST：projects / assets / character-bible / shots / graphs(validate/estimate/run) / recipes / object_info / backends(新增,后端注册表)。
- SSE `/chat`：Agent 流（thinking/tool_call/tool_result/graph_patch/message/ask/done）。
- WS `/events`：进度/预览/产物/成本/错误。
- op 协议：人/Agent 同构改 IR（M4 协同时收口）。

## 7. B 类规格收口（随实现）

op/graph_patch 线路协议、`validate` 规则细化（类型/枚举/插口兼容）、`estimate`（本地按配方/分辨率/步数历史计时；云按价目）、资产命名/缩略图、Agent 运行时（system prompt / ask-vs-proceed / 错误翻人话 / 重试）、镜头锁租约。

## 8. 模型清单冻结（MVP）

图像：Z-Image Turbo、Flux-2 Klein 9B、**Qwen-Image-Edit 2511 fp8mixed**。视频：**WAN 2.2 5B ti2v / 14B i2v + lightx2v**。文本编码/VAE：qwen_3_4b、qwen_2.5_vl_7b、qwen_3_8b、umt5_xxl、ae、qwen_image_vae、flux2-vae、wan2.2_vae。超分：4x-UltraSharp。训练：TrainLoraNode（DGX）。**不纳入 MVP**：Animate、Phantom、IPAdapter/InstantID/PuLID。
