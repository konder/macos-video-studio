# Orchestrator (M1 骨架)

ReelForge 的编排服务最小可跑骨架:**自然语言 → 选配方 → validate(对照 ComfyUI `/object_info`)→ 出一张定稿图**。
对应 [`../docs/spike-plan.md`](../docs/spike-plan.md) 的 M1,与 [`../docs/dev-kickoff.md`](../docs/dev-kickoff.md) 的既定决策。

> ⚠️ **必须在能访问 5090 的内网运行**(云端到不了 `10.10.10.2`)。这里是可 clone 下去接着填的起点。

## 结构
```
orchestrator/
├─ app/
│  ├─ config.py     # 环境配置(COMFY_URL / PROJECTS_DIR / AGENT_MODEL)
│  ├─ comfy.py      # ComfyUI HTTP 客户端(/object_info /prompt /history /view)
│  ├─ ir.py         # Graph IR ↔ ComfyUI prompt(+pos)
│  ├─ recipes.py    # 配方库:检索 + 实例化(占位符填参)
│  ├─ recipes/char_concept.json  # ← 占位配方模板,M1 第一步替换它
│  ├─ tools.py      # 四个工具:search_recipes / instantiate_recipe / validate / run
│  ├─ agent.py      # tool-use 手动循环(OpenAI SDK → LiteLLM 网关;显式传 base_url/key,不碰全局 ANTHROPIC_*)
│  ├─ store.py      # 项目文件夹持久化(project.json + 媒体)
│  └─ main.py       # FastAPI:/healthz、/chat
└─ scripts/run_m1.py  # 命令行一键自检
```

## 跑起来
```bash
cd orchestrator
pip install -r requirements.txt
cp .env.example .env   # 填 LITELLM_API_KEY + AGENT_MODEL，确认 COMFY_URL
export $(grep -v '^#' .env | xargs)   # 或用 direnv / python-dotenv

# 命令行自检
python -m scripts.run_m1 --list-models   # 先看 LiteLLM 上有哪些模型
python -m scripts.run_m1 "25岁亚洲女性,齐肩黑发,红色风衣,电影感打光,写实定稿图"

# 或起服务
uvicorn app.main:app --port 8000
curl localhost:8000/healthz
curl -X POST localhost:8000/chat -H 'content-type: application/json' \
  -d '{"message":"画一张写实女性定稿图"}'
```

## M1 第一步(最重要)
`app/recipes/char_concept.json` 是**占位模板**(核心节点 txt2img 结构)。先在 ComfyUI UI 用 5090 实装基模
(**Z-Image Turbo / Flux-2 Klein**)手搭一张**能出图**的图(注意用该模型对应的 EmptyLatent/VAE,避免冒烟测试里
WAN VAE 48ch vs 16ch 那类不匹配),**导出 API 格式 json** 覆盖 `graph_template`,并据 `/object_info` 调好
`class_type` 与 `inputs`。`validate` 会对照真实 schema 报错,照着改即可。

## 已遵循的既定决策
- IR = `prompt` 格式 + 每节点 `pos`(data-model §2);持久化 = 项目文件夹(data-model §4)。
- Orchestrator ↔ ComfyUI **只走 HTTP**(architecture §3)。
- Agent = tool-use;四工具与 native-ui 的「op / 无特权写路径」一致。
  （模型经 LiteLLM 网关调用,可选非 Claude 模型 —— 对「Agent=最新 Claude」决策的偏离已记入
  [docs/open-questions.md](../docs/open-questions.md) B 类。）

## 待办(B 类规格,随实现细化)
- `/chat` 改 SSE 流式(api-contract.md);op/graph_patch 线路 + 镜头锁;estimate;配方检索改向量/关键词混合。
