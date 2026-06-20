# 实现 vs 方案:偏离审计与纠偏计划

> 2026-06 自审。对照 docs/native-ui.md / api-contract.md / data-model.md / agent-system.md /
> pipeline.md / mvp-tech-plan.md / roadmap.md。结论:经 UI 三栏 + 两层 + op 端点纠偏后,
> **形态对了,但最深的不变量(无特权写路径)尚未真正成立**;反馈/异步/费用整条线与资产-角色
> CRUD 未做。本文记录偏离清单 + 纠偏顺序,逐项消除。

## 🔴 架构不变量级偏离

1. **无特权写路径被破坏(违反头号原则)**:`/films`、导演 Agent、关键帧、take、镜头创建全部
   直写 store,不经 op、不进历史、不增 seq。统一历史目前几乎为空(只有 select_take)。Agent 并非
   "对称操作端",而是有特权直写。→ **纠偏①**
2. **op 动词全集不完整(Day1 必须完整,不能后补)**:缺 create_shot/delete_shot/assign_asset/
   set_pos/create_character/create_asset;两个 op 端点语义分裂(/shots/{id}/ops 不入历史)。→ **纠偏②**
3. **资产/角色无 CRUD 端点**:契约要求 GET/POST /projects/{id}/assets、POST /assets/{id}/
   character-bible,全缺。客户端只能看不能建,身份锁定卡落不了地。→ **纠偏③**

## 🟡 契约规定但未实现

4. **异步作业模型**:无 job_id / GET /jobs/{id},/run 同步阻塞,无断线续跑、无进度。→ **纠偏④**
5. **流式/事件**:/chat 非 SSE;无 WS /events。无节点进度/latent/产物/cost 事件;反馈 IA 基本没
   落地(全局活动栏静态,无任务队列/费用)。→ **纠偏④**
6. **费用闸**:无 /graphs/estimate;云无"预估→确认→计费";CloudVideo 虚拟节点未实现;火山适配器
   写好却没接进路由(/films 永远本地)。→ **纠偏⑤**
7. **变更三态 / diff 卡 / 滑块 / 撤销**:全无。→ **纠偏⑥**
8. **镜头租约锁 / 接管**:全无。→ **纠偏⑥**

## 🟡 一致性方案部分落地

9. **自动注入透明+可控未完成**:无"已注入 X 档案"徽标(LoRA/触发词/相似度阈值可展开)、无临时
   覆盖/关闭、无"改档案→一键重生成受影响镜头";技术层无可见"角色注入"节点;无相似度阈值字段。→ **纠偏③/⑥**
10. `train_character_lora` 实现存在但孤立(无端点/Agent 调用)。A2 下 LoRA 是备选,标注即可。

## 🟢 次要 / 形态不符

11. 端点命名与契约不符:/graphs/validate(无 id)、/films(契约是 /graphs/{id}/run)、/recipes
    忽略 stage/q、ChangeIn.check 声明未用。
12. 客户端未用 /object_info、/state?since=(无增量/断线重连,每次全量 loadDetail)、/graphs/validate。
13. 存储未落 NAS(dev 环境,暂可接受)。

## 🟢 已记录的有意偏离(确认成立,非问题)

- Agent 走 LiteLLM(OpenAI 兼容)而非 Claude SDK(open-questions 已记)。
- 导演/搭图已是两套实现(director.py 固定流水线 / agent.py 工具循环)。
- 无音频 / FCPXML / project.json M3 定稿 — 对齐。
- 两层视图(#14)— 已对齐。

---

## 纠偏顺序(地基 → 外延)

- **① op 动词补全 + 两端点合一**(消 🔴2):ops.py 补 create_shot/delete_shot/set_keyframe/
  add_take/create_character/create_asset/set_pos;id 由调用方生成放进 op(可重放);/select、
  /shots/{id}/ops 统一走 record_change。
- **② 成片/导演走 op+历史**(消 🔴1):director/pipeline 不再直写 store,改为产出 ops 经
  record_change(author="agent", rationale)。Agent 成为非特权操作端。
- **③ 资产/角色 CRUD + 身份档案**(消 🔴3 + 部分 9):create_character/create_asset op +
  参考图上传端点;客户端"新建角色/资产"表单 + 身份锁定卡(触发词/相似度阈值/LoRA)。
- **④ 异步作业 + 流式反馈**(消 🟡4/5):job 模型 + GET /jobs/{id};/chat 改 SSE;WS /events
  转发 ComfyUI progress/executing/preview/executed;客户端实时进度/中间预览/全局活动栏接通。
- **⑤ estimate + 云费用闸**(消 🟡6):/graphs/estimate;云调用 预估→确认→计费;CloudVideo
  虚拟节点;火山适配器接进 i2v 路由(本地↔云)。
- **⑥ 三态 + diff 卡 + 滑块 + 撤销 + 镜头锁**(消 🟡7/8):节点画布改参/增删发 op;Proposed/
  Applied/Settled;diff 卡;省心↔掌控滑块;按镜头租约 + 接管;撤销改 IR 不删 take。

每阶段 backend+client 跑通、部署 5090、提交。

## 纠偏完成情况(2026-06)

全部 6 阶段已实现、部署 5090、验证、提交:

- ✅ **①** op 动词补全(create_shot/delete_shot/set_keyframe/add_take/create_character/
  create_asset/set_pos/delete_*)+ 两写端点合一入历史。验证:经 op→seq 历史。
- ✅ **②** director/pipeline 不再直写 store,全走 record_change(author=agent)。**无特权写
  路径成立**。
- ✅ **③** set_character_field/set_asset_field op + /upload 上传端点;客户端新建角色/资产表单 +
  可编辑身份锁定卡(触发词/相似度阈值)。
- ✅ **④** jobs 登记表 + /films·/graphs/run 后台异步 + GET /jobs/{id} + WS /events +
  /chat 改 SSE。客户端 job 轮询 + SSE 流式上屏。缺口:ComfyUI 节点级 latent 预览(需订阅
  ComfyUI WS)未接。
- ✅ **⑤** estimate.py + POST /graphs/estimate;/shots/{id}/generate 本地/云,云走
  needs_confirm 费用闸 + set_meta cost_total 累计计费。验证:估算 + 费用闸。云实跑需
  PUBLIC_MEDIA_BASE + ARK key(运行时)。
- ✅ **⑥** invert_ops + /undo(逆操作入历史,不删 take)+ 镜头租约锁;客户端节点检查器可改参
  (set_param op)/删节点、省心↔掌控滑块 + Proposed 暂存、历史撤销、镜头锁/接管。验证:
  改参→保留→撤销回退;lock/locks。

**已知剩余缺口(诚实记录)**:ComfyUI 节点级进度/latent 中间预览(需 ComfyUI WS 订阅);
add_node 的 UI(需 object_info 节点选择器,当前可改参/删节点/连线靠 op 但无新增 UI);
"改档案→一键重生成受影响镜头"按钮已留位未接;存储未落 NAS(dev)。

## 复审补充(亲自通读 data-model.md / agent-system.md 后新发现)

审计 agent 当时低估、或实现夸大的偏离,补记于此:

- ✅ **搭图 Agent 工具集补全**:tools.py 加 set_param/add_node/connect/delete_node + estimate
  (共 9 工具),走同一套 apply_ops 改 ctx.graph;agent SYSTEM 提示改图带 rationale。
  **对称写入在 Agent 端闭合**(Agent 现在能改图,与人同构)。验证:TOOL_SCHEMAS 9 个。
- ✅ **云任务做成 IR 虚拟节点**:云生成成功后把 shot.graph 设为 CloudVideo 虚拟节点
  (provider/model/image/prompt/duration/task_id/video_url),由适配器解释执行、不进 ComfyUI 图。
- ✅ **RecipeRegistry.search 按意图排序**:中文子串匹配 stage 关键词/id/title(无空格也可),
  无命中回退全部。验证:视频→i2v_local、角色定妆→char_turnaround、关键帧→keyframe_edit。
- ✅ **Agent 改图带 rationale**:编辑原语含 rationale 参数 + 系统提示要求。
- 🟡 **持久化目录结构不符 data-model §4(暂缓)**:文档要 shots/<id>/{keyframes,takes,previews}、
  assets/<type>/<id>/ 嵌套 + take 同名 .json 边车;实际为扁平 assets/ 一锅端。**判定暂缓**:
  功能等价、单用户 MVP 无碍,重构会改动所有现存路径且破坏 demo,收益低;待落 NAS 时一并改。

**诚实结论**:复审发现的 🔴/🟡 大部分已修;仅持久化目录形态作为低优先暂缓项保留。地基级不变量
+ Agent 对称编辑 + 云虚拟节点 + 意图检索均已对齐。动手前必读 native-ui/data-model/agent-system/api-contract。

## 复审第二轮(亲读 architecture/pipeline/walkthrough 后新发现)

均为**功能未建全**(非地基不变量破坏),记录待办:

- 🟡 **导演 Agent 不做智能后端路由**:pipeline §2 / walkthrough 要导演 Agent 按「质量/速度/成本/
  可用性」按镜头选本地↔云(用户可固定偏好);实际 director 恒走本地(route("edit"/"i2v")→5090),
  云只能在客户端手动逐镜头点。
- 🟡 **选片自动初筛未实现**:pipeline §3 / mockups §4 / walkthrough 步骤6 要多 take 网格 + 美学评分 +
  一致性评分 + Agent 自动剔除漂移 + 两两对比;实际仅 takes 列表 + 手动选用,无评分/初筛/对比。
- 🟡 **角色定稿流程未在 GUI 串起**:walkthrough 步骤1 要「新建角色(文本/参考图)→ char_turnaround
  多视角定稿 → 一致性自检相似度 → 锁档案」;实际「新建角色」只存档/上传参考图,不触发 char_turnaround
  生成多视角,也无相似度自检。(配方与管线已具备,缺 GUI 串联与自检。)
- 🟢 已知并接受:ComfyUI 节点级 latent 预览(需 ComfyUI WS);ControlNet/补帧(RIFE/FILM)模型未下载
  (env);存储未落 NAS;客户端云密钥 Keychain(当前无客户端密钥,密钥在服务器 env,N/A)。
