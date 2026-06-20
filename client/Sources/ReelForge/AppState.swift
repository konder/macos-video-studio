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

    // 技术层:钻进某镜头任务的节点画布
    @Published var openGraphShot: String?
    @Published var graphNodes: [NodeVM] = []
    @Published var graphLinks: [GraphLink] = []

    var characters: [Character] { detail?.characters ?? [] }
    var assets: [Asset] { detail?.assets ?? [] }
    var history: [Change] { (detail?.history ?? []).reversed() }   // 最新在上
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
        } catch { /* 项目可能尚无内容 */ }
    }

    func newProject(_ name: String) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        do { try await api.createProject(n); await loadProjects(); await selectProject(n) }
        catch { chatLog.append("❌ 新建项目失败: \(error.localizedDescription)") }
    }

    func refreshShots() async { await loadDetail() }

    func makeFilm() async {
        busy = true; activity = "生成成片中…"; defer { busy = false; activity = "" }
        chatLog.append("🎬 生成成片: \(script)")
        do {
            let r = try await api.makeFilm(FilmRequest(
                project: project, character_image: characterImage,
                character_desc: characterDesc, script: script, n_shots: nShots))
            chatLog.append("✅ 出片 \(r.shots.filter { $0.video != nil }.count)/\(r.shots.count) 镜头")
            await refreshShots()
        } catch { chatLog.append("❌ \(error.localizedDescription)") }
    }

    func send(_ text: String) async {
        guard !text.isEmpty else { return }
        busy = true; defer { busy = false }
        chatLog.append("🧑 \(text)")
        do { chatLog.append("🤖 " + (try await api.chat(message: text, project: project))) }
        catch { chatLog.append("❌ \(error.localizedDescription)") }
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

    /// 钻进镜头的「生成」任务 → 节点画布(技术层)。
    func openGraph(_ shot: String, task: String = "keyframe_edit") async {
        busy = true; activity = "构建节点图…"; defer { busy = false; activity = "" }
        do {
            let g = try await api.buildGraph(project: project, shot: shot, task: task)
            let (n, l) = parseGraph(g)
            graphNodes = n; graphLinks = l; openGraphShot = shot
        } catch { chatLog.append("❌ 构建节点图失败: \(error.localizedDescription)") }
    }
    func closeGraph() { openGraphShot = nil; graphNodes = []; graphLinks = [] }

    func export() async {
        busy = true; defer { busy = false }
        do { let r = try await api.export(project: project); chatLog.append("📦 导出: \(r["fcpxml"] ?? "")") }
        catch { chatLog.append("❌ 导出失败: \(error.localizedDescription)") }
    }
}
