import SwiftUI
import AppKit
import AVKit

// SwiftPM 裸可执行需手动设激活策略,否则 swift run 不弹窗。
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
            ContentView().environmentObject(state).frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)
    }
}

struct IdentURL: Identifiable { let id = UUID(); let url: URL }

// 暗色输入框(Claude Code 风)
struct DarkField: View {
    let placeholder: String
    @Binding var text: String
    var multiline = false
    var body: some View {
        Group {
            if multiline { TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...8) }
            else { TextField(placeholder, text: $text) }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false
    var body: some View {
        HStack(spacing: 0) {
            ProjectsPane(showSettings: $showSettings).frame(width: 234)
            vline
            TaskPane().frame(minWidth: 460, maxWidth: .infinity)
            vline
            AgentPane().frame(width: 364)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .task { await state.connect() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }
    var vline: some View { Rectangle().fill(Theme.border).frame(width: 1) }
}

// MARK: - 左:项目管理

struct ProjectsPane: View {
    @EnvironmentObject var state: AppState
    @Binding var showSettings: Bool
    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack.fill").foregroundStyle(Theme.accent)
                Text("ReelForge").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button { showNew = true } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft).help("新建项目")
            }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)

            HStack { SectionLabel(icon: "folder", text: "项目"); Spacer() }
                .padding(.horizontal, 12).padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(state.projects, id: \.self) { p in
                        SidebarRow(icon: "film", title: p, selected: p == state.project)
                            .onTapGesture { Task { await state.selectProject(p) } }
                    }
                    if state.projects.isEmpty {
                        Text("暂无项目").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                            .padding(.vertical, 8)
                    }
                }.padding(.horizontal, 8)
            }

            Spacer(minLength: 0)
            Rectangle().fill(Theme.border).frame(height: 1)
            Button { showSettings = true } label: {
                SidebarRow(icon: "gearshape", title: "设置 · 服务连接", selected: false)
            }.buttonStyle(.plain)
            HStack(spacing: 6) {
                Circle().fill(state.status == "已连接" ? .green : .secondary).frame(width: 7, height: 7)
                Text(state.status).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }.padding(.horizontal, 14).padding(.bottom, 10).padding(.top, 2)
        }
        .background(Theme.sidebar)
        .alert("新建项目", isPresented: $showNew) {
            TextField("项目名", text: $newName)
            Button("创建") { let n = newName; newName = ""; Task { await state.newProject(n) } }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 中:任务与画布

struct TaskPane: View {
    @EnvironmentObject var state: AppState
    @State private var preview: IdentURL?
    @State private var showCompose = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.project).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Pill(text: "\(state.shots.count) 镜", color: Theme.inkSoft)
                Spacer()
                Button { withAnimation { showCompose.toggle() } } label: {
                    Image(systemName: showCompose ? "chevron.up" : "plus.circle")
                }.buttonStyle(.plain).foregroundStyle(Theme.inkSoft).help("新建短片")
                Button { Task { await state.refreshShots() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
            }.padding(14)
            Rectangle().fill(Theme.border).frame(height: 1)

            ScrollView {
                VStack(spacing: 12) {
                    if showCompose { ComposeCard() }
                    if state.shots.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(state.shots.enumerated()), id: \.element.id) { idx, shot in
                            ShotCard(index: idx + 1, shot: shot, preview: $preview)
                        }
                    }
                }.padding(14)
            }
        }
        .background(Theme.bg)
        .sheet(item: $preview) { item in
            VStack(spacing: 0) {
                VideoPlayer(player: AVPlayer(url: item.url)).frame(width: 720, height: 420)
                HStack { Spacer(); Button("关闭") { preview = nil }.keyboardShortcut(.defaultAction) }.padding(10)
            }.background(Theme.bg)
        }
    }

    var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "film").font(.system(size: 40)).foregroundStyle(Theme.inkSoft.opacity(0.5))
            Text("还没有分镜").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
            Text("填角色与剧本,点「生成短片」,导演会自动拆镜并出片。")
                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, minHeight: 280).padding(30)
    }
}

struct ComposeCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(icon: "wand.and.stars", text: "新建短片(导演 Agent)")
            DarkField(placeholder: "角色定稿图路径", text: $state.characterImage)
            DarkField(placeholder: "角色描述", text: $state.characterDesc)
            DarkField(placeholder: "剧本 / 情境…", text: $state.script, multiline: true)
            HStack {
                Stepper("镜头数 \(state.nShots)", value: $state.nShots, in: 1...8)
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            }
            HStack(spacing: 8) {
                Button { Task { await state.makeFilm() } } label: { Label("生成短片", systemImage: "sparkles") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(state.busy)
                Button { Task { await state.export() } } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.bordered).tint(Theme.inkSoft).disabled(state.busy).help("导出 FCPXML")
            }
        }.card()
    }
}

struct ShotCard: View {
    @EnvironmentObject var state: AppState
    let index: Int
    let shot: Shot
    @Binding var preview: IdentURL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("镜 \(index)").font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.18), in: Capsule()).foregroundStyle(Theme.accent)
                    Text(shot.script ?? shot.id).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                if let s = shot.scene_prompt, !s.isEmpty {
                    Text(s).font(.system(size: 12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
                takesRow
            }
            Spacer(minLength: 0)
        }.card()
    }

    var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25))
            if let url = state.mediaURL(shot.keyframe) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { ProgressView().controlSize(.small) }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo").font(.title2).foregroundStyle(Theme.inkSoft.opacity(0.5))
            }
        }.frame(width: 160, height: 92).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var takesRow: some View {
        HStack(spacing: 10) {
            if let takes = shot.takes, !takes.isEmpty {
                ForEach(takes) { take in
                    let sel = take.id == shot.selected_take
                    Button { if let u = state.mediaURL(take.video) { preview = IdentURL(url: u) } } label: {
                        Label("播放", systemImage: "play.circle.fill").font(.system(size: 12))
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    Button { Task { await state.select(shot: shot.id, take: take.id) } } label: {
                        Image(systemName: sel ? "checkmark.seal.fill" : "seal").font(.system(size: 12))
                            .foregroundStyle(sel ? .green : Theme.inkSoft)
                    }.buttonStyle(.plain).help(sel ? "已选用" : "选用")
                }
            } else {
                Text("无 take").font(.system(size: 11)).foregroundStyle(Theme.inkSoft.opacity(0.6))
            }
        }.padding(.top, 2)
    }
}

// MARK: - 右:Agent

struct AgentPane: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack { SectionLabel(icon: "sparkle", text: "Agent"); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 12)
            Rectangle().fill(Theme.border).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if state.chatLog.isEmpty {
                            Text("对 Agent 说点什么,或在中间生成短片。")
                                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
                        }
                        ForEach(Array(state.chatLog.enumerated()), id: \.offset) { i, line in
                            Bubble(line: line).id(i)
                        }
                    }.padding(12)
                }
                .onChange(of: state.chatLog.count) { _ in
                    if let last = state.chatLog.indices.last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            // 大输入框
            VStack(spacing: 8) {
                TextField("给 Agent 发消息…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.ink)
                    .lineLimit(3...8).frame(minHeight: 64, alignment: .topLeading)
                    .onSubmit(send)
                HStack {
                    if state.busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.plain).foregroundStyle(input.isEmpty ? Theme.inkSoft : Theme.accent)
                        .disabled(input.isEmpty)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
            .padding(12)

            // 会话信息底栏
            HStack(spacing: 8) {
                Pill(text: state.model.isEmpty ? "—" : state.model, color: Theme.accent)
                if let b = state.backends.first { Pill(text: b.name.replacingOccurrences(of: "local-", with: ""), color: Theme.inkSoft) }
                Text(state.project).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                Spacer()
            }.padding(.horizontal, 14).padding(.bottom, 10)
        }
        .background(Theme.bg)
    }
    func send() { let t = input; input = ""; Task { await state.send(t) } }
}

struct Bubble: View {
    let line: String
    var isUser: Bool { line.hasPrefix("🧑") }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 20) }
            Text(line).font(.system(size: 13)).foregroundStyle(Theme.ink).textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 11).fill(isUser ? Theme.accent.opacity(0.22) : Theme.surface))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 20) }
        }
    }
}

// MARK: - 设置(服务连接)

struct SettingsSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置 · 服务连接").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                Text("Orchestrator 地址").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                DarkField(placeholder: "http://10.10.10.2:8000", text: $state.baseURL)
                HStack {
                    Button { Task { await state.connect() } } label: { Label("连接", systemImage: "bolt.fill") }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    if state.busy { ProgressView().controlSize(.small) }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(state.status == "已连接" ? .green : .secondary).frame(width: 7, height: 7)
                        Text(state.status).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            if !state.backends.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("后端").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    ForEach(state.backends) { b in
                        HStack(spacing: 6) {
                            Pill(text: b.name, color: b.latency == "fast" ? .green : .orange)
                            if let v = b.vram_gb { Text("\(v)G").font(.system(size: 11)).foregroundStyle(Theme.inkSoft) }
                            Text((b.caps ?? []).joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                    }
                }
            }
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 460).background(Theme.bg)
    }
}
