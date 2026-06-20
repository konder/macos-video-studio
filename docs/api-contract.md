# Orchestrator API 契约（草案）

Mac 客户端 ↔ Orchestrator（5090 机器）之间的接口。REST + SSE（Agent 流式）+ WebSocket（事件）。
本文是草案，实现时细化。

## REST

| 方法 / 路径 | 作用 |
|---|---|
| `POST /projects` / `GET /projects/{id}` / `PATCH /projects/{id}` | 项目 CRUD |
| `GET /projects/{id}/assets` / `POST /projects/{id}/assets` | 资产库读写（角色/服装/道具/背景/风格） |
| `POST /assets/{id}/character-bible` | 把资产固化为角色档案（identity/LoRA/触发词） |
| `GET /projects/{id}/shots` / `POST .../shots` / `PATCH .../shots/{sid}` | 分镜 CRUD |
| `POST /graphs/{id}/validate` | 对照 `/object_info` 校验 Graph IR |
| `POST /graphs/{id}/estimate` | 预估耗时 / 显存 / 云费用 |
| `POST /graphs/{id}/run` | 提交执行（返回 job_id） |
| `POST /cloud/{provider}/submit` / `GET /cloud/tasks/{task_id}` | 云作业提交 / 轮询 |
| `GET /recipes?stage=&q=` | 检索配方库 |
| `GET /object_info` | 透传/缓存 ComfyUI 节点 schema（供客户端与校验用） |
| `GET /assets/{id}` / `GET /assets/{id}/thumbnail` | 资产 / 缩略图下载 |

## Agent（SSE 流式）

`POST /chat` — 驱动 Agent，SSE 流式返回：
```
event: thinking     // 可选，过程说明
event: tool_call    // {tool, args}
event: tool_result  // {tool, result}
event: graph_patch  // 对 Graph IR / 项目的增量改动（客户端据此更新画布）
event: message      // 给用户的自然语言（含「为什么这么搭」）
event: ask          // 需要用户澄清时的提问
event: done
```

## 事件流（WebSocket）

`WS /events?project={id}` — 进度 / 中间产物 / 产物：
```jsonc
{ "type": "progress",  "job": "...", "node": "n1", "step": 12, "total": 25 }
{ "type": "executing", "job": "...", "node": "n1" }
{ "type": "preview",   "job": "...", "node": "n1", "thumb_url": "..." }   // 中间预览
{ "type": "executed",  "job": "...", "node": "n9", "asset_id": "...", "kind": "video" }
{ "type": "error",     "job": "...", "node": "n5", "human_message": "..." }
{ "type": "cost",      "job": "...", "provider": "jimeng", "amount": 0.12 }
{ "type": "done",      "job": "..." }
```

设计约束：
- 断线重连后客户端可用 `GET /jobs/{job_id}` 拉回当前状态与已产出资产。
- 预览/产物事件只带 URL，大文件按需拉取；缩略图优先。

## op / 协同（编辑同一份 IR）

人和 Agent 都通过同一套 **op** 改 IR（无特权写路径，见 [native-ui.md](native-ui.md)）。服务器持有权威 IR，
客户端持本地副本 + 应用增量。

| 方法 / 路径 | 作用 |
|---|---|
| `POST /projects/{id}/ops` | 提交一段 ops（有序）；服务器校验+应用，返回新 `seq` 与规范化 patch |
| `GET /projects/{id}/state?since={seq}` | 拉全量 / 增量（断线重连用） |
| `POST /shots/{sid}/lock` | 取得镜头编辑租约（body：`actor=human|agent`，带 TTL；用于「单镜头单 actor 持笔」） |
| `DELETE /shots/{sid}/lock` | 释放租约（接管 = 在 op 边界转移租约） |

```jsonc
// op（人 / Agent 同构）
{ "op": "set_param", "node": "n1", "widget": "steps", "value": 28 }
{ "op": "add_node",  "node": "n9", "type": "VAEDecode", "pos": [820, 300] }
{ "op": "connect",   "from": {"node":"n1","slot":0}, "to": {"node":"n9","slot":0} }
// 一个「变更」= ops[] + {author, ts, rationale?, tool_call?}；带 seq，进统一历史，可整组撤销
```

- 服务器按 `seq` 单调递增定序；客户端据 `graph_patch` / `ops` 结果更新画布。
- 镜头租约保证单镜头任意时刻只有一个 actor 持笔；跨镜头可并行。
