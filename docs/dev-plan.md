# 开发计划（MVP build plan）

> 基于 [mvp-tech-plan.md](mvp-tech-plan.md) 的可执行切片计划。原则：**后端优先、垂直切片、每片可跑通可验收**；SwiftUI 后置（[roadmap](roadmap.md) M4）。已验证基线见 [spike-summary](spike-summary.md)。

## 已完成

**spike 阶段**
- ✅ M1 Orchestrator 骨架：FastAPI + Agent tool-use（LiteLLM）+ 四工具 + `char_concept` 配方 + 项目存储骨架。
- ✅ 一致性方法验证：Qwen-edit 关键帧 + WAN i2v，e2e 跨镜头成立；模型已下齐。
- ✅ 算力/路由决策：5090 快速层 + DGX 大显存层 + 云。

**build 阶段 1（一致性管线打通）** ✅ `9805d29`
- 配方 `keyframe_edit`/`i2v_local`/`char_turnaround`；`pipeline.shot_to_video`(定稿→关键帧→视频 take)；
  `comfy.upload_image`+视频产物收集；validate 修(动态文件枚举)。实测海边镜头 take 跑通。

**build 阶段 2（多后端路由 + 持久化 + LoRA→DGX）** ✅ `723830d`
- `backends.py` 注册表+路由(edit/i2v→5090,train→DGX,两后端可达);`pipeline.train_character_lora`→DGX;
  `project.json` schema(Character Bible/Shots/takes)。
- **DGX 512² 训练实测成功**(`sks_woman_dgx512`,86MB)——5090 在 512² OOM,**break-256² 经验证**;
  Z-Image 基模经千兆 LAN 拷至 DGX。

## 切片里程碑

### 阶段 1 — 一致性管线打通（后端，脚本驱动）
把验证过的链路固化进 Orchestrator。
- 补配方：`char_turnaround` / **`keyframe_edit`(Qwen-edit)** / **`i2v_local`(WAN 5B+14B/lightx2v)** / `interp_upscale`，落 `app/recipes/*.json` + 注册到 RecipeRegistry。
- 管线服务：`角色档案 → keyframe_edit → i2v_local → take`，封装为可调用的 pipeline 函数 + 工具。
- 资产 I/O：keyframe/视频在 ComfyUI input/output 间的上传/取回封装（解决 LoadImage 读 input 问题）。
- **DoD**：脚本输入"一个角色定稿 + 一个镜头场景描述" → 自动出该镜头的视频 take，落项目文件夹。

### 阶段 2 — 多后端路由 + 项目持久化定稿
- 后端注册表：5090/DGX 两本地后端（能力标签 + vram + latency）；按能力/显存路由；`GET /backends`。
- `char_lora_train` 配方 → 路由到 **DGX** 高分训练；产出 LoRA 挂回角色档案。
- `project.json` schema 定稿（meta/Character Bible/Shots/takes/每镜头 Graph IR）；存 NAS；断点续跑。
- **DoD**：同一项目里，普通镜头走 5090 出片、主角 LoRA 训练自动落 DGX；项目可关闭重开续作。

### 阶段 3 — 导演 Agent + 分镜（产品化 e2e） ✅ `b0d52ec`+`0a8b9dd`
- `director.plan_shotlist`(LLM 拆镜,可关联资产)+ `produce_film`(角色档案注入、批量出片)。
- **导演自动编排资产**:按镜头 `use_assets` 选用,选中走 `keyframe_compose` 组合(实测雪天自动换装)。
- DoD ✅:一段剧本 → 多镜头一致小样片(`film.mp4`)。

### 阶段 3.5 — 资产体系 ✅ `0b187fd`
- `store` 通用 Asset Library;`pipeline.keyframe_compose` 多图参考组合(角色+服装+背景)。实测换装成功。

### 阶段 4 — API 收口 + op 协同 + 导出工程 ✅ `0a8b9dd`(选片/SSE 待续)
- `main.py` REST 收口:backends/recipes/object_info/projects/shots/graphs(validate+run)/films/ops/export/chat。
- `ops.py` op 协议(set_param/add_node/connect/delete_node)= 人介入 workflow 的写入面(无特权写路径)。
- `export.py` 有序片段 + **FCPXML**(实测 well-formed,Final Cut/DaVinci 可导)。
- 待续:选片端点(takes 选定/回滚)、`/chat` 改 SSE 流式、镜头锁、op 序列号/历史。
- DoD(部分达成):整链「资产→分镜→生成→导出」后端跑通;选片/SSE/锁 留作收尾。

### 阶段 5 — SwiftUI 客户端（[roadmap](roadmap.md) M4）
导演层（制片管理面）+ 技术层（节点画布）+ Agent×画布协同（[native-ui](native-ui.md) 已对齐 v0.1）。后端无状态化 + 持久化已就位，客户端为纯前端。

### 阶段 6 — 云接入（[open-questions A3](open-questions.md)）
即梦（火山引擎）/ Qwen（DashScope）适配器 + ComfyUI partner 节点（Kling/Runway/Luma/Vidu/Veo）；reference-to-video 作云端一致性对照与突发产能。`submit→poll→download` 异步模型。

## 顺序与并行

- 关键路径：**阶段 1 → 2 → 3 → 4**（后端整链）。阶段 5（UI）可在阶段 3 后并行启动；阶段 6（云）可在阶段 2 后按需穿插。
- 收尾性可行性（不阻塞）：定量身份距离（insightface）、Flux-2 作更优 LoRA 基模实测——可在阶段 2 顺带做。

## 进入编码判据（已满足）

① 一致性决策表定稿 ✅ ② 配方/一致性管线/后端路由规格落地（本文 + mvp-tech-plan）✅ ③ MVP backlog/里程碑排定（本文）✅ → **可全速进入阶段 1 编码**。
