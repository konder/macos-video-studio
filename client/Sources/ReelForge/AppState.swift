import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var baseURL = "http://10.10.10.2:8000"  // 已部署的 Orchestrator(systemd)
    @Published var project = "demo"
    @Published var status = "未连接"
    @Published var model = ""
    @Published var backends: [Backend] = []
    @Published var recipes: [Recipe] = []
    @Published var shots: [Shot] = []
    @Published var chatLog: [String] = []
    @Published var busy = false

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
            await refreshShots()
        } catch { status = "连接失败: \(error.localizedDescription)" }
    }

    func refreshShots() async {
        do { shots = try await api.shots(project: project) } catch { /* 项目可能尚无分镜 */ }
    }

    func makeFilm() async {
        busy = true; defer { busy = false }
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

    func select(shot: String, take: String) async {
        do { try await api.selectTake(project: project, shot: shot, take: take); await refreshShots() }
        catch { chatLog.append("❌ 选片失败: \(error.localizedDescription)") }
    }

    func export() async {
        busy = true; defer { busy = false }
        do { let r = try await api.export(project: project); chatLog.append("📦 导出: \(r["fcpxml"] ?? "")") }
        catch { chatLog.append("❌ 导出失败: \(error.localizedDescription)") }
    }
}
