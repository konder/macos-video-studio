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
            ContentView().environmentObject(state).frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.titleBar)
    }
}

struct IdentURL: Identifiable { let id = UUID(); let url: URL }

struct ContentView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 290, ideal: 310, max: 360)
        } detail: {
            Detail()
        }
        .task { await state.connect() }
    }
}

// MARK: - 侧栏:品牌 + 连接 + 新建短片

struct Sidebar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "film.stack.fill")
                        .font(.title2).foregroundStyle(Theme.brand)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ReelForge").font(.system(.title3, design: .rounded).weight(.bold))
                        Text("AI 角色叙事视频工作台").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 4)

                connectionCard
                composeCard
                Spacer(minLength: 0)
            }.padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(icon: "server.rack", text: "服务连接")
            TextField("API 地址", text: $state.baseURL).textFieldStyle(.roundedBorder)
            HStack {
                TextField("项目", text: $state.project).textFieldStyle(.roundedBorder).frame(width: 110)
                Button { Task { await state.connect() } } label: {
                    Label("连接", systemImage: "bolt.fill")
                }.buttonStyle(.borderedProminent).tint(Theme.brand)
                if state.busy { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 6) {
                let ok = state.status == "已连接"
                Circle().fill(ok ? .green : .secondary).frame(width: 7, height: 7)
                Text(state.status).font(.caption).foregroundStyle(ok ? .primary : .secondary)
                if !state.model.isEmpty { Pill(text: state.model, color: Theme.brand2) }
            }
            if !state.backends.isEmpty {
                HStack(spacing: 6) {
                    ForEach(state.backends) { b in
                        Pill(text: b.name.replacingOccurrences(of: "local-", with: ""),
                             color: b.latency == "fast" ? .green : .orange)
                    }
                }
            }
        }.card()
    }

    var composeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(icon: "wand.and.stars", text: "新建短片(导演 Agent)")
            field("角色定稿图", $state.characterImage)
            field("角色描述", $state.characterDesc)
            VStack(alignment: .leading, spacing: 4) {
                Text("剧本 / 情境").font(.caption).foregroundStyle(.secondary)
                TextField("一段剧本…", text: $state.script, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...6)
            }
            Stepper("镜头数  \(state.nShots)", value: $state.nShots, in: 1...8)
            Button { Task { await state.makeFilm() } } label: {
                Label("生成短片", systemImage: "sparkles")
            }.buttonStyle(PrimaryButtonStyle()).disabled(state.busy)
            Button { Task { await state.export() } } label: {
                Label("导出工程 (FCPXML)", systemImage: "square.and.arrow.up")
            }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(state.busy)
        }.card()
    }

    func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - 主区:分镜板 + 对话

struct Detail: View {
    @EnvironmentObject var state: AppState
    @State private var showChat = true
    var body: some View {
        HSplitView {
            ShotBoard().frame(minWidth: 520)
            if showChat { ChatColumn().frame(minWidth: 300, idealWidth: 340) }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("分镜 · Storyboard").font(.system(.headline, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await state.refreshShots() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation { showChat.toggle() } } label: {
                    Image(systemName: showChat ? "sidebar.right" : "bubble.left.and.bubble.right")
                }
            }
        }
    }
}

struct ShotBoard: View {
    @EnvironmentObject var state: AppState
    @State private var preview: IdentURL?
    var body: some View {
        ScrollView {
            if state.shots.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(state.shots.enumerated()), id: \.element.id) { idx, shot in
                        ShotCard(index: idx + 1, shot: shot, preview: $preview)
                    }
                }.padding(16)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .sheet(item: $preview) { item in
            VStack(spacing: 0) {
                VideoPlayer(player: AVPlayer(url: item.url)).frame(width: 720, height: 420)
                HStack { Spacer(); Button("关闭") { preview = nil }.keyboardShortcut(.defaultAction) }.padding(10)
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film").font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("还没有分镜").font(.headline)
            Text("在左侧填角色与剧本,点「生成短片」,导演会自动拆镜并出片。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, minHeight: 420).padding(40)
    }
}

struct ShotCard: View {
    @EnvironmentObject var state: AppState
    let index: Int
    let shot: Shot
    @Binding var preview: IdentURL?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("镜 \(index)").font(.caption.weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.brand.opacity(0.15), in: Capsule()).foregroundStyle(Theme.brand)
                    Text(shot.script ?? shot.id).font(.headline).lineLimit(1)
                }
                if let s = shot.scene_prompt, !s.isEmpty {
                    Text(s).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Divider().padding(.vertical, 2)
                takesRow
            }
            Spacer(minLength: 0)
        }.card()
    }

    var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.15))
            if let url = state.mediaURL(shot.keyframe) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { ProgressView().controlSize(.small) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo").font(.title).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 168, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var takesRow: some View {
        HStack(spacing: 8) {
            if let takes = shot.takes, !takes.isEmpty {
                ForEach(takes) { take in
                    let sel = take.id == shot.selected_take
                    Button {
                        if let u = state.mediaURL(take.video) { preview = IdentURL(url: u) }
                    } label: {
                        Label("Take", systemImage: "play.circle.fill")
                            .font(.caption)
                    }.buttonStyle(.borderless)
                    Button {
                        Task { await state.select(shot: shot.id, take: take.id) }
                    } label: {
                        Image(systemName: sel ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(sel ? .green : .secondary)
                    }.buttonStyle(.borderless).help(sel ? "已选用" : "选用此 take")
                }
            } else {
                Text("无 take").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Agent 对话

struct ChatColumn: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack { SectionLabel(icon: "bubble.left.and.bubble.right.fill", text: "Agent 对话"); Spacer() }
                .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(state.chatLog.enumerated()), id: \.offset) { i, line in
                            Bubble(line: line).id(i)
                        }
                    }.padding(12)
                }
                .onChange(of: state.chatLog.count) { _ in
                    if let last = state.chatLog.indices.last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("对 Agent 说…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .buttonStyle(.borderedProminent).tint(Theme.brand).disabled(input.isEmpty)
            }.padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    func send() { let t = input; input = ""; Task { await state.send(t) } }
}

struct Bubble: View {
    let line: String
    var isUser: Bool { line.hasPrefix("🧑") }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 24) }
            Text(line)
                .font(.callout).textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(isUser ? Theme.brand.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 24) }
        }
    }
}
