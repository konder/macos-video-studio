import SwiftUI
import AppKit

// SwiftPM 裸可执行(非 .app bundle)默认不是 regular 激活策略,
// `swift run` 时窗口不弹/不在前台。用 AppDelegate 设为 regular 并激活。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

@main
struct ReelForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()
    var body: some Scene {
        WindowGroup("ReelForge") {
            ContentView().environmentObject(state)
                .frame(minWidth: 980, minHeight: 640)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider()
            HSplitView {
                ChatPanel().frame(minWidth: 300, idealWidth: 340)
                DirectorBoard().frame(minWidth: 560)
            }
        }
        .task { await state.connect() }
    }
}

struct TopBar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 12) {
            Text("ReelForge").font(.headline)
            TextField("API", text: $state.baseURL).frame(width: 200).textFieldStyle(.roundedBorder)
            TextField("项目", text: $state.project).frame(width: 90).textFieldStyle(.roundedBorder)
            Button("连接") { Task { await state.connect() } }
            Text(state.status).foregroundStyle(state.status == "已连接" ? .green : .secondary)
            if !state.model.isEmpty { Text("· \(state.model)").foregroundStyle(.secondary) }
            Spacer()
            ForEach(state.backends) { b in
                Text(b.name).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            if state.busy { ProgressView().controlSize(.small) }
        }.padding(8)
    }
}

/// 导演层:制片管理面(分镜板 + 生成成片 + 选片/导出)
struct DirectorBoard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupBox("剧本 → 成片(导演 Agent)") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("角色定稿图路径", text: $state.characterImage).textFieldStyle(.roundedBorder)
                    TextField("角色描述", text: $state.characterDesc).textFieldStyle(.roundedBorder)
                    TextField("剧本/情境", text: $state.script).textFieldStyle(.roundedBorder)
                    HStack {
                        Stepper("镜头数 \(state.nShots)", value: $state.nShots, in: 1...8)
                        Spacer()
                        Button("生成成片") { Task { await state.makeFilm() } }.disabled(state.busy)
                        Button("导出工程") { Task { await state.export() } }.disabled(state.busy)
                    }
                }.padding(4)
            }
            HStack {
                Text("分镜 (\(state.shots.count))").font(.headline)
                Spacer()
                Button("刷新") { Task { await state.refreshShots() } }
            }
            List(state.shots) { shot in ShotRow(shot: shot) }
                .listStyle(.inset)
        }.padding(8)
    }
}

struct ShotRow: View {
    @EnvironmentObject var state: AppState
    let shot: Shot
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(shot.script ?? shot.id).font(.subheadline).bold()
            if let s = shot.scene_prompt, !s.isEmpty {
                Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            ForEach(shot.takes ?? []) { take in
                HStack {
                    Image(systemName: take.id == shot.selected_take ? "checkmark.circle.fill" : "circle")
                    Text(take.video ?? take.id).font(.caption2).lineLimit(1)
                    Spacer()
                    Button("选用") { Task { await state.select(shot: shot.id, take: take.id) } }
                        .buttonStyle(.borderless).font(.caption2)
                }
            }
        }.padding(.vertical, 2)
    }
}

/// Agent 对话面板(技术层/导演对话的统一入口)
struct ChatPanel: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""
    var body: some View {
        VStack(spacing: 6) {
            Text("Agent 对话").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(state.chatLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack {
                TextField("对 Agent 说…", text: $input).textFieldStyle(.roundedBorder)
                    .onSubmit { let t = input; input = ""; Task { await state.send(t) } }
                Button("发送") { let t = input; input = ""; Task { await state.send(t) } }
            }
        }.padding(8)
    }
}
