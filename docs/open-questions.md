# 编码就绪度 / 待定问题

完整方案（架构 / 数据模型 / Agent / 管线 / API / UI）已成形，但有些点还**太模糊、无法直接展开编码**。
本文按「是否阻塞、谁来定」分类，并给出建议解锁顺序。结论确定后回填到对应文档。

---

## 就绪度结论（2026-06）

**✅ 可以开始 M1 编码。** 阻塞设计已全部拍板：概念（单模型·多操作端）/ 两层 UI（导演层·技术层）/
数据模型 + 持久化（文件夹）/ IR 保真（prompt + pos）/ API 契约（REST·SSE·WS + op·镜头锁）/ 管线 + 路由 /
配方库（贴 5090 实装）/ 环境（A1 已摸清）/ 一致性方向（角色 LoRA 为主）/ 产品参数（D3–D6）。
原生 UI ①–⑥ 均对齐 v0.1。

- ⏳ **编码中再细化的 B 类规格（非阻塞）**：op 具体 schema、配方模板格式、validate 规则、estimate、
  Agent system prompt——随 M1 落地即可。
- ⚠️ **两点提醒**：
  1. **运行位置**：M1/M2 必须在能访问 5090 的内网跑（云端到不了 `10.10.10.2`），见 [spike-plan.md](spike-plan.md)。
  2. **真实风险在 M2 一致性**，靠 spike 证伪；M1 先证「Agent 搭图」可靠。
- ⏸ **唯一后置**：D7 二次元基模（不挡写实 MVP）。

---

## A. 需要你拍板 / 需要外部事实（阻塞，优先）

### A1. 5090 的 ComfyUI 环境清单 —— ✅ 已回填（2026-06）
报告 + 解读见 [env-survey.md](env-survey.md)。要点：RTX 5090 32G · ComfyUI 0.24 · 图像 Flux-2 Klein /
Qwen-Image / Z-Image · 视频 **WAN 2.2** 主力 · **可本机训 LoRA** · **IPAdapter/InstantID/PuLID 未装** ·
ControlNet/补帧无模型需下载 · 已带 Kling/Runway/Luma/Veo 等云 partner 节点 · 项目存 NAS(37T)。
据此已落地配方库（[agent-system.md](agent-system.md) §3）并改向 A2。

### A2. 一致性技术栈选型（项目最大技术风险）—— 方向已定，待 spike 验证
A1 显示 IPAdapter/InstantID/PuLID 未装、且对本机 2026 新基模未必适配，故**改向**（详见
[agent-system.md](agent-system.md) §5 / [env-survey.md](env-survey.md) 解读）：
- **主线：角色 LoRA**（本机 `TrainLoraNode` 训练，两风格通用、不挑基模）。
- **对照：** Qwen-Image-Edit 参考编辑 / Flux-2·Qwen 原生参考条件。
- **M2 spike**：以上方案 × 写实/二次元两风格，验「定稿 → 关键帧 → WAN i2v」整条链的漂移。
- **依赖 D7**（二次元基模）；这仍是**最该尽早做实验**的点。

### A3. 云接入方式 —— ✅ 已定（2026-06）
即梦**走火山引擎官方 API**；Qwen 走 DashScope。**新发现**：ComfyUI 已带 Kling/Runway/Luma/Veo/Sora/Vidu
partner 节点（配 key 即用）→ 国际厂商优先**直接作为图节点**调用，省自研适配器；即梦无 partner 节点，仍走
Orchestrator 适配器。M6 收口细节（B 类）。

### A4. 项目持久化形态 —— ✅ 已定（2026-06）
**项目 = 一个文件夹**：`project.json`（Shots / 资产元数据 / Graph IR）+ 媒体文件 + 缩略图。
可移植、易备份、对 Git 友好、便于「导出工程」。详见 [data-model.md](data-model.md) §4。

### A5. Graph IR ↔ ComfyUI 往返保真范围 —— ✅ 已定（2026-06）
**以 `prompt` 格式为事实来源 + 额外存 `pos` 给画布布局**；`workflow` 的 reroute / group / note 暂不支持
（后置）。详见 [data-model.md](data-model.md) §2。

---

## D. 产品方案待澄清（非技术，需你定）

技术阻塞之外，产品层面还有几点没敲定；其中 **D1 / D2 会反过来决定 A1 该找什么模型、A2 怎么选**，建议优先。

- **D1 美术风格定位** —— ✅ 已定：**写实 + 二次元都要**。→ 含义：一致性方法**按风格分两套**（见 A2 / 
  [agent-style](agent-system.md) §5），基模也要两个家族；[env-survey.md](env-survey.md) 两类模型都查。
- **D2 角色来源** —— ✅ 已定：**文本描述 + 上传参考图都要**。→ 含义：两种来源最终**收敛成同一份角色档案**
  （文本来源 = 先文生图定稿，再把定稿图当参考），之后注入路径相同。
- **D3 视频交付规格** —— ✅ 已定：生成 **720p → 超分 1080p**；**16:9 为主、9:16 可选**；单镜头 **3–5s**；**24fps**。
- **D4 导出工程格式** —— ✅ 已定：**有序片段文件夹 + FCPXML**（FCPXML 同时被 Final Cut 与 DaVinci Resolve 导入）。
- **D5 MVP 音频范围** —— ✅ 已定：**完全无音频**（对白 / 配音 / 音轨 / 口型全归后置剪辑 Agent）。
- **D6 使用范围** —— ✅ 已定：**MVP 自用（单用户）**，不做多租户；后端保留多客户端接口（iPad / Web 不返工）。
- **D7 二次元基模** —— ⏸ 后置（稍后再定）。MVP 一致性 spike 先做**写实线**；二次元待下载动漫基模后再补。

## B. 我可以先出规格（非阻塞，我来定，你可后审）

- **op / `graph_patch` 线路协议**：op schema、序列号 / 版本、应用顺序、客户端如何据此更新画布。
- **客户端 ↔ 服务器同步 + 镜头锁 / 租约**：协同的并发控制（「单镜头单 actor 持笔」需要锁端点，
  当前 [api-contract.md](api-contract.md) 还没有）。
- **配方模板格式**：占位符语法、`params_schema`（用 JSON Schema）、`instantiate_recipe` 填充规则。
- **validate 规则**：对照 `/object_info` 校验节点存在 / 类型 / 必填 / 枚举 / 插口类型兼容。
- **estimate 策略**：云 = 价目表换算；本地 = 按配方 / 分辨率 / 步数的历史计时估算。
- **资产 / 产物存储与命名**：`asset_id` 方案、缩略图 / 低码率预览生成、take ↔ 产物挂接。
- **Agent 运行时**：M1 先**单 Agent + 工具循环**（导演 / 搭图后续再拆）；system prompt、ask-vs-proceed 策略、
  重试 / 错误翻译成人话。

## C. 已经足够清楚、可直接编码

- M1 主链路骨架（FastAPI + Claude tool-use + 接 ComfyUI run）。
- REST / SSE / WS 契约草案（[api-contract.md](api-contract.md)，细节实现时收口）。
- 数据模型的项目结构（[data-model.md](data-model.md)）、管线阶段、本地 / 云路由原则。
- UI 已对齐：单模型多操作端、Agent×画布协同、导演层 / 技术层两层视图（[native-ui.md](native-ui.md)）。

---

## 建议的最快解锁顺序

1. **盘点 5090 环境**（A1）——一切下游的前提。
2. ~~定持久化 + IR 保真范围（A4 / A5）~~ —— ✅ 已定。
3. **M1 PoC**：单 Agent → 选配方 → validate → 出一张人物定稿图（用 A1 的真实 ComfyUI）。
4. **一致性 spike**（A2）：验证 1 套 identity + 基模组合的跨链一致性——最大风险尽早证伪。
5. 之后按 roadmap M2→M6 推进；A3（即梦）在 M6 前定。
