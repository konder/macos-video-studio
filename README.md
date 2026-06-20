# ReelForge

> 一个「会自己搭流程」的 macOS AI 视频制作工作台。用户用自然语言描述意图，Agent 负责把繁琐的
> ComfyUI 工作流搭好、调好参数、跑起来，并全程把进度 / 中间产物 / 预览喂回给用户；用户随时可钻进
> 技术层画布手动微调。面向「AI 视频入门」与「生产力工具」双场景，专注**有剧情的角色叙事视频**。

> 名字 `ReelForge` 只是占位，随时可改。

状态：**设计基线 v0.1**（2026-06）。本仓库目前是完整方案文档，尚无代码。

---

## 这是什么

做一支有剧情的 AI 短片，最痛、最繁琐的是这条链路：**保持角色/服装/风格在所有镜头里一致 → 拆分镜
→ 给每个镜头搭一张复杂的 ComfyUI 工作流并反复调参 → 生成多条 take → 选片**。ReelForge 把这条
链路交给 Agent 编排，用户用对话驱动、用技术层画布微调，全程有进度、中间产物和预览反馈。

核心理念：**单模型，多操作端，对称写入。** 项目/图是唯一事实来源（single source of truth）；
Agent、画布直接操作、对话都只是同一份数据的「操作端」，走同一套 op API、落同一条历史。执行引擎
（本地 ComfyUI / 云）被抽象成「能消费这份数据的后端」。这样「Agent 搭 ↔ 人手调」天然互通、可互相接管。

## 关键设定（已与需求方对齐）

- **形态**：macOS 原生客户端（SwiftUI：导演层制片管理面 + 技术层节点画布）+ 局域网 5090 Linux 服务器，client/server 架构。
- **双场景单引擎**：对话优先（入门）↔ 画布优先（生产力）为**连续滑块**（非开关）；视图分**导演层**（制片管理，围绕分镜头）与**技术层**（任务执行 flow），共享同一数据模型。
- **算力**：本地千兆局域网的 Linux + RTX 5090 跑 ComfyUI；云用即梦（火山引擎）/ Qwen 通义万相补充。
- **MVP 范围**：资产 → 分镜 → 生成 → 选片 → 导出工程。**剪辑/后期/口型同步后置**，由后续独立的
  「剪辑 Agent」单独做。
- **开源**：站在 ComfyUI（GPL-3.0）上；SwiftUI 客户端为独立程序，可自选许可。

## 文档导航

| 文档 | 内容 |
|---|---|
| [docs/architecture.md](docs/architecture.md) | 总体架构、技术栈、client/server 工程要点、许可与分发 |
| [docs/data-model.md](docs/data-model.md) | 项目数据模型（Character Bible / Shots / takes）+ Graph IR |
| [docs/agent-system.md](docs/agent-system.md) | 导演/搭图 Agent、工具集、配方库、schema 校验、一致性方案 |
| [docs/pipeline.md](docs/pipeline.md) | 制作管线全景、本地/云路由、反馈系统 |
| [docs/api-contract.md](docs/api-contract.md) | Orchestrator API 与 WebSocket 事件契约 |
| [docs/diagrams.md](docs/diagrams.md) | 流程图（架构 / 管线 / Agent 循环 / 路由 / 数据模型 / 时序） |
| [docs/mockups.md](docs/mockups.md) | 关键界面视觉稿（对话/导演层/技术层/Agent 协同/角色创建/选片/导出 等 9 屏） |
| [docs/walkthrough.md](docs/walkthrough.md) | **从 0 到 1 交互用例**：空项目 → 角色 → 分镜 → 生成 → 选片 → 导出（含时序图） |
| [docs/roadmap.md](docs/roadmap.md) | 里程碑、MVP 垂直切片、未决问题 |
| [docs/native-ui.md](docs/native-ui.md) | macOS 原生 UI 核心问题；**①–⑥ 全部对齐 v0.1** |
| [docs/open-questions.md](docs/open-questions.md) | **编码就绪度**：就绪度结论 + 待定问题（A 类全清、D 仅剩 D7 后置）|
| [docs/env-survey.md](docs/env-survey.md) | 5090 ComfyUI 环境调研清单 + **回填报告 / 解读**（A1 已完成）|
| [docs/spike-plan.md](docs/spike-plan.md) | **M1 / M2 spike 执行清单**（给内网 agent：搭图 PoC + 一致性验证）|

## 下一步

1. 完整方案已成形（本仓库）。
2. 原生 UI：**①–⑥ 全部对齐 v0.1**（Agent×画布协同 / 双层视图 / 反馈 IA / 一致性呈现，见 [docs/native-ui.md](docs/native-ui.md)）。
3. **就绪度：可以开始 M1 编码**（[docs/open-questions.md](docs/open-questions.md) 就绪度结论）。
   spike 执行清单见 [docs/spike-plan.md](docs/spike-plan.md)，须在能访问 5090 的内网跑；唯一后置 D7（二次元基模）。
