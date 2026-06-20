import Foundation
import SwiftUI

// 中间区当前选中的项目元素。
enum Sel: Hashable {
    case overview
    case characters, assets, shotsRoot   // 分组标题(展示该类画廊)
    case character(String)
    case asset(String)
    case shot(String)
    case timeline
}

@MainActor
final class AppState: ObservableObject {
    @Published var baseURL = "http://10.10.10.2:8000"  // 已部署的 Orchestrator(systemd)
    @Published var project = "demo"
    @Published var status = "未连接"
    @Published var model = ""
    @Published var backends: [Backend] = []
    @Published var recipes: [Recipe] = []
    @Published var projects: [String] = []
    @Published var shots: [Shot] = []
    @Published var detail: ProjectDetail?           // 当前项目完整元素
    @Published var chatLog: [String] = []
    @Published var busy = false

    // 导航 / 布局
    @Published var selection: Sel = .overview
    @Published var expanded: Set<String> = []       // 树展开节点 key
    @Published var leftCollapsed = false
    @Published var rightCollapsed = false
    @Published var activity = ""                     // 全局活动栏当前动作

    // 技术层:钻进某镜头/资产/角色的节点画布(流程图)。kind: shot|asset|character
    struct GraphRef: Equatable { let kind: String; let id: String }
    @Published var graphRef: GraphRef?
    @Published var graphNodes: [NodeVM] = []
    @Published var graphLinks: [GraphLink] = []

    // 协同:省心↔掌控滑块(0 省心=自动应用 / 1 中 / 2 掌控=暂存 Proposed)
    @Published var approvalMode = 0
    struct ProposedEdit: Identifiable { let id = UUID(); let node: String; let widget: String; let oldValue: String; let newValue: Any; let newDisplay: String }
    @Published var proposed: [ProposedEdit] = []
    @Published var locks: [String: LockInfo] = [:]

    var characters: [Character] { detail?.characters ?? [] }
    var assets: [Asset] { detail?.assets ?? [] }
    var history: [Change] { (detail?.history ?? []).reversed() }   // 最新在上
    var totalCost: Double { detail?.meta?.cost_total ?? 0 }

    // 云生成费用确认(费用闸)
    struct CloudConfirm: Identifiable { let id = UUID(); let shot: String; let est: Estimate }
    @Published var cloudConfirm: CloudConfirm?
    func character(_ id: String) -> Character? { characters.first { $0.id == id } }
    func asset(_ id: String) -> Asset? { assets.first { $0.id == id } }
    func shot(_ id: String) -> Shot? { shots.first { $0.id == id } }
    func toggle(_ key: String) { if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) } }

    // 生成成片表单
    @Published var characterImage = "projects/demo/assets/char_concept_00004_.png"
    @Published var characterDesc = "25 year old East Asian woman, red trench coat, photorealistic"
    @Published var script = "傍晚的城市:她先在咖啡馆,再走上霓虹街道,最后到天台看夜景。"
    @Published var nShots = 3

    private var api: API { API(base: baseURL) }

    /// 规范化后的 base(补 http://、去尾斜杠),用于拼媒体 URL。
    var apiBase: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// 把服务端文件路径(keyframe/take.video)转成可访问的媒体 URL。
    func mediaURL(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty,
              let enc = p.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "\(apiBase)/media?path=\(enc)")
    }

    func connect() async {
        busy = true; defer { busy = false }
        do {
            let h = try await api.health()
            status = h.ok ? "已连接" : "异常"
            model = h.model ?? ""
            backends = try await api.backends()
            recipes = try await api.recipes()
            await loadProjects()
            expanded.insert("p:" + project)
            await loadDetail()
        } catch { status = "连接失败: \(error.localizedDescription)" }
    }

    func loadProjects() async {
        do {
            projects = try await api.listProjects()
            if !projects.contains(project), let first = projects.first { project = first }
        } catch { /* ignore */ }
    }

    func selectProject(_ name: String) async {
        project = name
        selection = .overview
        expanded.insert("p:" + name)
        await loadDetail()
    }

    /// 拉取完整项目元素(meta/角色/资产/分镜)。
    func loadDetail() async {
        do {
            let d = try await api.project(project)
            detail = d
            shots = d.shots ?? []
            await loadLocks()
        } catch { /* 项目可能尚无内容 */ }
    }

    func newProject(_ name: String) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        do { try await api.createProject(n); await loadProjects(); await selectProject(n) }
        catch { chatLog.append("❌ 新建项目失败: \(error.localizedDescription)") }
    }

    func refreshShots() async { await loadDetail() }

    /// 成片:启动异步作业 → 轮询 /jobs 显示进度(契约的断线拉回机制)。
    func makeFilm() async {
        busy = true; activity = "生成成片中…"; defer { busy = false; activity = "" }
        chatLog.append("🎬 生成成片: \(script)")
        do {
            let jid = try await api.startFilm(FilmRequest(
                project: project, character_image: characterImage,
                character_desc: characterDesc, script: script, n_shots: nShots))
            while true {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let j = try await api.job(jid)
                if let p = j.progress, let t = p.total, t > 0 {
                    activity = "\(j.message ?? "处理中…") (\(p.step ?? 0)/\(t))"
                } else { activity = j.message ?? "处理中…" }
                if j.status == "done" { chatLog.append("✅ 成片完成"); break }
                if j.status == "error" { chatLog.append("❌ \(j.error ?? "失败")"); break }
            }
            await loadDetail()
        } catch { chatLog.append("❌ \(error.localizedDescription)") }
    }

    /// 与搭图 Agent 对话 → SSE 流式(tool_call 实时上屏,message 收尾)。
    func send(_ text: String) async {
        guard !text.isEmpty else { return }
        busy = true; activity = "Agent 思考中…"; defer { busy = false; activity = "" }
        chatLog.append("🧑 \(text)")
        do {
            let req = try api.chatRequest(message: text, project: project)
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            var event = "message"
            var finalMsg = ""
            for try await line in bytes.lines {
                if line.hasPrefix("event:") {
                    event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let raw = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    guard let d = raw.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                    switch event {
                    case "tool_call": chatLog.append("🔧 " + (obj["tool"] as? String ?? "工具"))
                    case "tool_result": await loadDetail()   // Agent 改了模型 → 实时刷新左侧树/预览
                    case "message": finalMsg = obj["text"] as? String ?? finalMsg
                    case "error": finalMsg = "❌ " + (obj["error"] as? String ?? "出错")
                    default: break
                    }
                }
            }
            chatLog.append("🤖 " + (finalMsg.isEmpty ? "(无输出)" : finalMsg))
            await loadDetail()
        } catch { chatLog.append("❌ \(error.localizedDescription)") }
    }

    /// 选用 take —— 走 op API,进统一历史(人/Agent 同构,无特权写路径)。
    func select(shot: String, take: String) async {
        do {
            try await api.submitChange(project: project,
                ops: [["op": "select_take", "shot": shot, "take": take]],
                author: "human", rationale: "选用 take")
            await loadDetail()
        } catch { chatLog.append("❌ 选片失败: \(error.localizedDescription)") }
    }

    private func shortID(_ prefix: String) -> String { prefix + "_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased() }

    /// 新建角色或资产(经 op + 历史)。kind="character" 或资产类型(wardrobe/prop/environment/styleframe)。
    func newElement(kind: String, name: String, trigger: String, prompt: String,
                    similarity: Double?, image: (Data, String)?) async {
        busy = true; activity = "新建\(kind=="character" ? "角色" : "资产")…"; defer { busy = false; activity = "" }
        do {
            var finals: [String] = []
            if let (data, fn) = image {
                let p = try await api.uploadImage(project: project, data: data, filename: fn)
                if !p.isEmpty { finals = [p] }
            }
            var op: [String: Any]
            if kind == "character" {
                op = ["op": "create_character", "id": shortID("char"), "name": name,
                      "source": "text", "finals": finals, "trigger": trigger]
                if let s = similarity { op["similarity"] = s }
            } else {
                op = ["op": "create_asset", "id": shortID(String(kind.prefix(4))), "type": kind,
                      "name": name, "prompt": prompt, "finals": finals]
            }
            try await api.submitChange(project: project, ops: [op], author: "human",
                                       rationale: "新建\(kind=="character" ? "角色" : "资产") \(name)")
            await loadDetail()
        } catch { chatLog.append("❌ 新建失败: \(error.localizedDescription)") }
    }

    /// 生成资产(文字 / 文字+参考图 → 预设流程出图)。有图先上传为参考。轮询作业。
    func generateAsset(kind: String, name: String, prompt: String, image: (Data, String)?) async {
        busy = true; activity = "生成资产…"; defer { busy = false; activity = "" }
        do {
            var ref: String? = nil
            if let (data, fn) = image {
                let p = try await api.uploadImage(project: project, data: data, filename: fn)
                if !p.isEmpty { ref = p }
            }
            let jid = try await api.generateAsset(project: project, atype: kind, name: name, prompt: prompt, refPath: ref)
            await loadDetail()      // 资产已建出(finals 空)→ 立刻出现在左侧树
            while true {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let j = try await api.job(jid)
                activity = j.message ?? "处理中…"
                if j.status == "done" { break }
                if j.status == "error" { chatLog.append("❌ \(j.error ?? "生成失败")"); break }
            }
            await loadDetail()      // 产物回填 → 预览图更新
        } catch { chatLog.append("❌ 生成资产失败: \(error.localizedDescription)") }
    }

    /// 编辑角色身份档案(trigger/相似度阈值/LoRA),经 op + 历史。
    func updateCharacter(_ id: String, trigger: String, similarity: Double?) async {
        var ops: [[String: Any]] = [["op": "set_character_field", "id": id, "field": "trigger", "value": trigger]]
        if let s = similarity { ops.append(["op": "set_character_field", "id": id, "field": "similarity", "value": s]) }
        do { try await api.submitChange(project: project, ops: ops, author: "human", rationale: "更新角色档案"); await loadDetail() }
        catch { chatLog.append("❌ 更新失败: \(error.localizedDescription)") }
    }

    /// 从关键帧生成视频 take(本地或云)。云未确认→弹费用确认;确认后跑作业并轮询。
    func generate(shot: String, backend: String = "local", confirm: Bool = false) async {
        busy = true; activity = "生成视频…"; defer { busy = false; activity = "" }
        do {
            let r = try await api.generate(project: project, shot: shot, backend: backend, confirm: confirm)
            if r.needs_confirm == true, let e = r.estimate {
                cloudConfirm = CloudConfirm(shot: shot, est: e); return
            }
            guard let jid = r.job_id else { return }
            while true {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let j = try await api.job(jid)
                activity = j.message ?? "处理中…"
                if j.status == "done" { break }
                if j.status == "error" { chatLog.append("❌ \(j.error ?? "生成失败")"); break }
            }
            await loadDetail()
        } catch { chatLog.append("❌ 生成失败: \(error.localizedDescription)") }
    }
    func confirmCloud() async {
        guard let c = cloudConfirm else { return }
        cloudConfirm = nil
        await generate(shot: c.shot, backend: "cloud", confirm: true)
    }

    /// 钻进镜头的「生成」任务 → 节点画布(技术层)。
    func openGraph(_ shot: String, task: String = "keyframe_edit") async {
        busy = true; activity = "构建节点图…"; defer { busy = false; activity = "" }
        do {
            let g = try await api.buildGraph(project: project, shot: shot, task: task)
            let (n, l) = parseGraph(g)
            graphNodes = n; graphLinks = l; graphRef = GraphRef(kind: "shot", id: shot)
        } catch { chatLog.append("❌ 构建节点图失败: \(error.localizedDescription)") }
    }

    /// 打开资产/角色的生成流程(技术层)。kind: asset|character。
    func openAssetGraph(_ id: String, kind: String = "asset") async {
        busy = true; activity = "载入流程…"; defer { busy = false; activity = "" }
        do {
            let g = try await api.assetGraph(project: project, id: id)
            let (n, l) = parseGraph(g)
            graphNodes = n; graphLinks = l; graphRef = GraphRef(kind: kind, id: id)
        } catch { chatLog.append("❌ 载入流程失败: \(error.localizedDescription)") }
    }

    /// 按资产当前流程重新生成,更新 finals(经 op + 历史)。
    func regenerateAsset(_ id: String) async {
        busy = true; activity = "重新生成…"; defer { busy = false; activity = "" }
        do {
            let jid = try await api.regenerateAsset(project: project, id: id)
            while true {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let j = try await api.job(jid)
                activity = j.message ?? "处理中…"
                if j.status == "done" { break }
                if j.status == "error" { chatLog.append("❌ \(j.error ?? "重生成失败")"); break }
            }
            await loadDetail()
        } catch { chatLog.append("❌ 重新生成失败: \(error.localizedDescription)") }
    }
    func closeGraph() { graphRef = nil; graphNodes = []; graphLinks = []; proposed = [] }

    private func coerce(_ s: String) -> Any {
        if let i = Int(s) { return i }
        if let d = Double(s) { return d }
        if s == "true" { return true }; if s == "false" { return false }
        return s
    }
    /// 给图级 op 注入当前目标(shot/asset/character)。
    private func targetOp(_ base: [String: Any]) -> [String: Any] {
        guard let r = graphRef else { return base }
        var op = base; op[r.kind] = r.id; return op
    }

    /// 改节点参数:省心模式直接发 op(自动应用+可撤销);掌控模式暂存为 Proposed。
    func editParam(node: String, widget: String, old: String, text: String) async {
        guard graphRef != nil, text != old else { return }
        let val = coerce(text)
        if approvalMode == 0 {
            do {
                try await api.submitChange(project: project,
                    ops: [targetOp(["op": "set_param", "node": node, "widget": widget, "value": val])],
                    author: "human", rationale: "改参 \(widget): \(old)→\(text)")
                await reopenGraph()
            } catch { chatLog.append("❌ 改参失败: \(error.localizedDescription)") }
        } else {
            proposed.removeAll { $0.node == node && $0.widget == widget }
            proposed.append(ProposedEdit(node: node, widget: widget, oldValue: old, newValue: val, newDisplay: text))
        }
    }

    /// 接受全部 Proposed:作为一个变更提交,入历史。
    func acceptProposed() async {
        guard graphRef != nil, !proposed.isEmpty else { return }
        let ops = proposed.map { targetOp(["op": "set_param", "node": $0.node, "widget": $0.widget, "value": $0.newValue]) }
        do {
            try await api.submitChange(project: project, ops: ops, author: "human", rationale: "接受 \(ops.count) 处改参")
            proposed = []
            await reopenGraph()
        } catch { chatLog.append("❌ 应用失败: \(error.localizedDescription)") }
    }
    func discardProposed() { proposed = [] }

    func deleteNode(_ node: String) async {
        guard graphRef != nil else { return }
        do {
            try await api.submitChange(project: project,
                ops: [targetOp(["op": "delete_node", "node": node])], author: "human", rationale: "删除节点 \(node)")
            await reopenGraph()
        } catch { chatLog.append("❌ 删除失败: \(error.localizedDescription)") }
    }

    private func reopenGraph() async {
        guard let r = graphRef else { return }
        do {
            let g = r.kind == "shot" ? try await api.buildGraph(project: project, shot: r.id)
                                     : try await api.assetGraph(project: project, id: r.id)
            let (n, l) = parseGraph(g); graphNodes = n; graphLinks = l
        } catch { }
    }

    /// 撤销最近一个可撤销变更。
    func undoLast() async {
        do { try await api.undo(project: project); await loadDetail(); await reopenGraph() }
        catch { chatLog.append("❌ 撤销失败: \(error.localizedDescription)") }
    }

    func loadLocks() async { do { locks = try await api.locks(project: project) } catch { } }
    func lockShot(_ shot: String, actor: String = "human") async {
        do { try await api.lock(project: project, shot: shot, actor: actor); await loadLocks() } catch { }
    }
    func unlockShot(_ shot: String) async {
        do { try await api.unlock(project: project, shot: shot); await loadLocks() } catch { }
    }

    /// 钻进镜头的「生成」任务 → 节点画布(技术层)。

    func export() async {
        busy = true; defer { busy = false }
        do { let r = try await api.export(project: project); chatLog.append("📦 导出: \(r["fcpxml"] ?? "")") }
        catch { chatLog.append("❌ 导出失败: \(error.localizedDescription)") }
    }
}
