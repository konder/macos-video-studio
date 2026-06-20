# M1 / M2 Spike 执行清单

> 给**能访问 5090 / ComfyUI 的内网 agent**（云端 agent 到不了 `10.10.10.2`）。目标：最小代价验证两件事——
> M1「Agent 能不能可靠搭图出图」、M2「一致性能不能扛住」。环境见 [env-survey.md](env-survey.md)。
> 设 `COMFY=http://10.10.10.2:8188`。

---

## M1 — Agent 搭图 PoC（验证「自然语言 → 选配方 → 校验 → 出图」）

不依赖 SwiftUI；最快验证 Agent 搭图是否靠谱。

**前置**
- [ ] 在 ComfyUI UI 里**手搭一张能跑通的 `char_concept` 图**（基模用 **Z-Image Turbo**（快）或 **Flux-2 Klein**（质量）），
      确认出图——注意用该模型**对应的 EmptyLatent / VAE**（解决冒烟测试里 WAN VAE 48ch vs 16ch 的配置错）。
- [ ] 导出该图的 **API 格式（prompt json）** = `char_concept` 配方模板；记下用到的节点类名与必填项（查 `/object_info`）。

**步骤**
1. 起一个最小 Orchestrator（FastAPI 或纯脚本）+ Claude tool-use 循环，实现 4 个工具：
   - `search_recipes(intent)` → 返回 1–2 个硬编码配方（`char_concept` / `char_turnaround`）
   - `instantiate_recipe(id, params)` → 填模板占位符 → **Graph IR（prompt 格式 + pos）**
   - `validate(graph)` → 拉 `/object_info`，校验节点存在 / 必填 / 枚举 / 类型
   - `run(graph)` → `POST /prompt`，轮询 `/history/{id}`，取产物（`/view`）
2. 跑：输入「25 岁亚洲女性，齐肩黑发，红风衣，电影感打光，写实」→ 看 Agent 选配方 → 填参 → validate → 出图。

**验收**
- [ ] 端到端出一张定稿图；记录耗时。
- [ ] `validate` 能拦掉一个**人为错误**（如把 sampler 填成非法枚举）。
- [ ] IR 往返无损：导出 → 执行 → 回读不丢（prompt + pos）。

---

## M2 — 一致性 spike（**写实线**，角色 LoRA 为主线）

项目最大技术风险，尽早证伪。二次元线后置（D7）。

**数据**
- [ ] 用 M1 的角色，生成 / 收集 **12–20 张**多视角多表情图（`char_turnaround`）作训练集。

**Track A（主线 · 角色 LoRA）**
- [ ] 用 **`TrainLoraNode`** 在 Flux-2 Klein（或所选基模）训一个角色 LoRA。
- [ ] 用该 LoRA + 触发词，在 **3 个不同场景 / 姿态**各出 1 张。

**Track B（对照 · Qwen-Image-Edit）**
- [ ] 不训 LoRA，用 **Qwen-Image-Edit** 把定稿角色「编辑进」同样 3 个场景。

**Track C（对照 · 原生参考，可选）**
- [ ] 若 Flux-2 / Qwen 支持参考图条件，试同样 3 场景。

**链路验证（关键）**
- [ ] 取一致性最好的一张关键帧 → **WAN 2.2 i2v 14B** 生成 3–5s → 看视频里角色是否仍一致。

**度量与产出**
- [ ] 每张 / 每段记：身份相似度（一个 face/feature embedding 距离）、服装 & 风格漂移（主观 1–5）、耗时、显存峰值。
- [ ] 产出**一页对比** → 定 MVP 默认一致性方法（预期 LoRA 最稳）。

---

## 注意
- 必须在能访问 5090 的内网环境跑；产物 / 项目写 **NAS**；Orchestrator 经 **HTTP** 与 ComfyUI 交互（不直读其文件系统）。
- 备料（**M1/M2 写实线暂不强依赖**，到关键帧 / 补帧阶段再下）：ControlNet 模型、RIFE/FILM 补帧模型。
