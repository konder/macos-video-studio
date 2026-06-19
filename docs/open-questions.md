# 编码就绪度 / 待定问题

完整方案（架构 / 数据模型 / Agent / 管线 / API / UI）已成形，但有些点还**太模糊、无法直接展开编码**。
本文按「是否阻塞、谁来定」分类，并给出建议解锁顺序。结论确定后回填到对应文档。

---

## A. 需要你拍板 / 需要外部事实（阻塞，优先）

### A1. 5090 的 ComfyUI 环境清单 —— 最大解锁项
配方库、一致性栈、视频管线全都依赖「**5090 上实际装了哪些节点 / 模型 / 显存多少**」。
- 现在能直连那台 5090 的 ComfyUI 吗？还是 M1 先在一台普通开发机的 ComfyUI 上起骨架？
- 已安装：基础模型（Flux / SDXL / Qwen-Image？）、视频模型（Wan 2.x 哪个版本？）、一致性相关自定义节点
  （IPAdapter / InstantID / PuLID / ControlNet / 训练 LoRA 的链路？）、显存（32GB？）。
- **阻塞**：A2、配方库初始清单、M1 的「出一张定稿图」、validate 的真实 `/object_info`。

### A2. 一致性技术栈选型（项目最大技术风险）
[agent-system.md](agent-system.md) §5 只列了候选（PuLID / InstantID / IPAdapter / 可选 LoRA），未定。要编码 M2 须定：
- **identity 方法**：PuLID vs InstantID vs IPAdapter-FaceID vs 训练专属 LoRA（或组合）。
- **基模**：Flux vs SDXL vs Qwen-Image（决定上面方法的可用节点与质量）。
- **跨链一致性**：定稿图 → 关键帧 → 图生视频（Wan）整条链上角色是否扛得住漂移。
- 建议：先 spike 验证 1 套组合再定；依赖 A1。**这是最该尽早做实验的点。**

### A3. 即梦（火山引擎）云接入方式
[roadmap.md](roadmap.md) 未决 #1：走**官方 API** 还是仅网页端？仅网页端则云方案要换思路（影响 M6）。
Qwen 通义万相（DashScope）有官方 API，相对明确。需要你确认 / 我去查即梦 API 的可用性、鉴权、submit/poll、计费。

### A4. 项目持久化形态 —— ✅ 已定（2026-06）
**项目 = 一个文件夹**：`project.json`（Shots / 资产元数据 / Graph IR）+ 媒体文件 + 缩略图。
可移植、易备份、对 Git 友好、便于「导出工程」。详见 [data-model.md](data-model.md) §4。

### A5. Graph IR ↔ ComfyUI 往返保真范围 —— ✅ 已定（2026-06）
**以 `prompt` 格式为事实来源 + 额外存 `pos` 给画布布局**；`workflow` 的 reroute / group / note 暂不支持
（后置）。详见 [data-model.md](data-model.md) §2。

---

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
