# ReelForge macOS 客户端(阶段5)

SwiftUI macOS 原生客户端,接 Orchestrator REST API([../docs/api-contract.md](../docs/api-contract.md))。
**导演层**(分镜板 + 剧本→成片 + 选片 + 导出工程)+ **Agent 对话面板**。后端无状态、状态持久化在服务端,客户端纯前端。

## 跑

先起 Orchestrator(`cd ../orchestrator && uvicorn app.main:app --port 8000`,设好 `LITELLM_API_KEY`/`AGENT_MODEL`),再:

```bash
cd client
swift build          # 验证编译(已通过)
swift run            # 启动 GUI 窗口
```

或用 Xcode 打开(`File > Open` 选 `client/Package.swift`)运行/调试。

顶栏填 Orchestrator 地址(默认 `http://localhost:8000`)与项目名 → 连接。

## 结构

| 文件 | 作用 |
|---|---|
| `Sources/ReelForge/Models.swift` | 与 API 对应的 Codable 模型 |
| `Sources/ReelForge/API.swift` | URLSession async REST 客户端(films/projects/shots/recipes/backends/ops/select/export/chat) |
| `Sources/ReelForge/AppState.swift` | `@MainActor` 视图模型(连接/生成成片/选片/导出/对话) |
| `Sources/ReelForge/Views.swift` | `@main` App + 导演层分镜板 + Agent 对话面板 |

## 现状

- ✅ `swift build` 编译通过(Swift 6 工具链 / 5.9 语言模式)。
- ✅ 导演层:剧本→成片(调 `/films`)、分镜列表、选片(`/select`)、导出(`/export`)。
- ✅ Agent 对话(`/chat`)。
- 待续:技术层节点画布(op/graph_patch 可视化,后端 `/ops` 已就绪)、视频内联预览(AVKit)、SSE 流式。
