# 本地开发起步（M1 编码 kickoff）

> 给在**能访问 5090 的内网机器**上新开的 Claude Code 会话。本仓库是完整设计文档；先读文档，
> 再按 [spike-plan.md](spike-plan.md) 实现 **M1**。注意：云端环境到不了 5090，编码/联调必须在内网做。

## 0. 开工前确认（前置）
- [ ] 网络：`curl http://10.10.10.2:8188/system_stats` 能返回 JSON（ComfyUI 可达）
- [ ] `ANTHROPIC_API_KEY` 已配（Orchestrator 的 Agent 调 Claude 用；与 Claude Code 自身的登录无关）
- [ ] Python 3.12 环境（Orchestrator 可跑在 5090 host，或任一能 HTTP 到 ComfyUI 的 LAN 机）
- [ ] 项目存储路径：NAS `/mnt/nas`（PoC 也可先用本地路径）
- [ ] 云 key（即梦 / Qwen / partner）——**M1 不需要**，M6 才用

## 1. 读文档（顺序）
README → [open-questions](open-questions.md)（就绪度结论 + 全部已定决策）→ [architecture](architecture.md)
→ [data-model](data-model.md) → [agent-system](agent-system.md) → [api-contract](api-contract.md)
→ **[spike-plan](spike-plan.md)（任务）** → [env-survey](env-survey.md)（环境实况）→ [native-ui](native-ui.md)（后续里程碑 UI）

## 2. 任务：M1（详见 spike-plan.md）
自然语言 → 选配方 → `validate` → 出一张人物定稿图。四个工具：
`search_recipes` / `instantiate_recipe` / `validate` / `run`。不依赖 SwiftUI。

## 3. 不要推翻的既定决策（已对齐，照做；要改先记进 open-questions）
- **技术栈**：Python + FastAPI Orchestrator（部署在 5090 旁）；Agent = Claude tool-use（用**最新 Claude 模型**）；
  SwiftUI 客户端是后续 M4，不在 M1。
- **Graph IR** = ComfyUI **`prompt` 格式 + 每节点 `pos`**；无损往返；节点用稳定 id（命中缓存）。
- **持久化** = **项目文件夹**（`project.json` + 媒体 + 缩略图），存 NAS；目录树见 data-model §4。
- **Orchestrator ↔ ComfyUI 只走 HTTP**（容器隔离，不读其文件系统）；ComfyUI `http://10.10.10.2:8188`。
- **配方贴实装模型**（agent-system §3）：`char_concept` = Z-Image Turbo / Flux-2 Klein；`i2v` = WAN 2.2；
  超分 4x-UltraSharp。
- **一致性 = 角色 LoRA 为主**（M2）；IPAdapter / InstantID / PuLID 未装，别依赖。
- **validate** 对照 `/object_info`（节点存在 / 必填 / 枚举 / 类型）；**run** = `POST /prompt` + 轮询 `/history`，
  产物经 `/view` 取回。

## 4. 第一步动作
先在 ComfyUI UI 手搭一张**能出图**的 `char_concept`（用该模型**对应的 EmptyLatent / VAE**，避免冒烟测试里
WAN VAE 48ch vs 16ch 那类通道不匹配），**导出 API 格式 json** 作配方模板；再写 Orchestrator + 四工具，跑通端到端。

## 5. 规矩
- 在 feature 分支开发；设计已冻结——发现设计缺口先记进 [open-questions.md](open-questions.md) 再动，别闷头偏离。
- 唯一已知后置：D7（二次元基模），M1/M2 写实线不涉及。
