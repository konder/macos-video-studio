# 数据模型

产品不是「一张 ComfyUI 图」，而是「一个项目」。一支片子横跨几十个生成任务、要管资产复用与一致性，
因此核心模型是项目结构，下面再嵌套与 ComfyUI 一一映射的 Graph IR。

## 1. 项目结构

```
Project（一支片子）
├─ meta: 标题 / 美术风格(写实·二次元) / 宽高比(16:9 主·9:16 可选) / 分辨率(生成720p→超分1080p)
│         / 帧率(24fps) / 默认后端偏好 ...   ← MVP 规格默认见 open-questions D3
├─ AssetLibrary / Character Bible        ← 一致性的锚点
│   ├─ Character[]   来源(文本/参考图) + 风格(写实/二次元) + 定稿图集 +
│   │                身份锁定(按风格: InstantID·PuLID 或 IPAdapter+角色LoRA) + 触发词
│   ├─ Wardrobe[]    服装
│   ├─ Prop[]        道具
│   ├─ Environment[] 场景背景设定图
│   └─ StyleFrame[]  美术风格 / lookdev
├─ Shots[]                                 ← 分镜
│   └─ Shot
│       ├─ script: 谁 / 干什么 / 景别 / 运镜 / 时长 / 对白
│       ├─ refs: 引用的 Character / Wardrobe / Environment / Prop ...
│       ├─ keyframes: 起始帧 (±尾帧)
│       ├─ takes[]: 多条生成结果 (本地或云) + 元数据(seed/参数/后端/耗时/花费)
│       ├─ selectedTake
│       └─ graph: 该镜头背后的 ComfyUI 工作流 (Graph IR)
└─ Timeline（后置，剪辑 Agent 阶段）
```

要点：
- **资产是可复用、可锁定的一等公民**。角色档案（Character）是一致性的核心载体，详见
  [agent-system.md](agent-system.md) 的一致性方案。
- **每个 Shot 自带一张 Graph IR**，既是它的「生成配方实例」，也是从导演层钻进**技术层**画布时的编辑对象。
- **takes 保留完整元数据**，支撑选片对比、复现、回滚、「基于这次再改」。

## 2. Graph IR

与 ComfyUI 的 `prompt` / `workflow` JSON **一一映射**的中立数据结构（节点、inputs、links、widget 值）。
画布只是 IR 的可视编辑器；Agent 改的也是同一份 IR；导出时序列化成 ComfyUI API 格式。

```jsonc
// Graph IR 概要
{
  "nodes": [
    {
      "id": "n1",
      "type": "KSampler",
      "widgets": { "seed": 123, "steps": 25, "cfg": 7.0, "sampler_name": "euler" },
      "inputs":  { "model": {"node":"n0","slot":0}, "positive": {"node":"n2","slot":0} },
      "pos": [120, 80]
    }
  ]
  // links 可由 inputs 推导，或显式冗余存储以便画布渲染
}
```

设计约束：
- **保真范围（已定）**：以 ComfyUI 执行用的 `prompt` 格式为事实来源，能**无损往返**（导出→执行→回读不
  丢信息）；另存每个节点的 `pos` 供画布布局。`workflow` 的 reroute / group / note 暂不支持（后置）。
- IR 节点的合法性由 ComfyUI `/object_info` 的真实 schema 校验（见 agent-system.md）。
- 云生成任务在 IR / 项目级用**虚拟节点**表示（如 `CloudVideo(provider=jimeng, ...)`），由 Orchestrator
  的云适配器解释执行，不进 ComfyUI 图。

## 3. 版本与产物

- 每次运行的产物（图/视频/中间预览）留档并挂在对应 Shot/take 上，可对比、回滚。
- ComfyUI 的缓存机制天然支持「改了下游参数只重算受影响节点」，IR 设计需保留节点稳定 id 以命中缓存。

## 4. 持久化形态（已定）

一个项目 = **一个文件夹**：`project.json`（meta + Character Bible / 资产元数据 + Shots + 每镜头 Graph IR）
+ 媒体文件（图 / 视频 / 中间预览）+ 缩略图。理由：可移植、易备份、对 Git 友好、天然支撑「导出工程」。
大媒体单独落盘、元数据走 JSON；`asset_id` 与节点 `id` 用稳定标识，以命中缓存并支撑跨版本引用。

```
<project>/
├─ project.json                 # meta + 资产元数据 + Shots + 每镜头 Graph IR(prompt 格式 + pos)
├─ assets/
│   ├─ characters/<id>/         # 定稿图集、identity 文件、(可选)LoRA、触发词
│   └─ wardrobe|props|environments|styleframes/<id>/
├─ shots/<shot_id>/
│   ├─ keyframes/               # 起始 / 尾帧
│   ├─ takes/<take_id>.mp4      # 各 take 产物（+ 同名 .json 元数据：seed/参数/后端/耗时/花费）
│   └─ previews/                # 中间预览
├─ thumbnails/                  # 缩略图 / 低码率预览缓存
└─ exports/                     # 导出工程（有序片段 + FCPXML，见 pipeline §1 / open-questions D4）
```
