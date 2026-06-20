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
            ContentView().environmentObject(state).frame(minWidth: 1180, minHeight: 740)
        }
        .windowStyle(.titleBar)
    }
}

struct IdentURL: Identifiable { let id = UUID(); let url: URL }

// 资产类型 → 中文名 + 图标
func assetMeta(_ t: String) -> (String, String) {
    switch t {
    case "wardrobe": return ("服装", "tshirt")
    case "prop": return ("道具", "cube")
    case "environment": return ("场景", "mountain.2")
    case "styleframe": return ("风格", "paintpalette")
    default: return (t, "shippingbox")
    }
}

// 选参考图(NSOpenPanel)→ (字节, 文件名)
func pickImageData() -> (Data, String)? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
    panel.allowedFileTypes = ["png", "jpg", "jpeg", "webp"]
    guard panel.runModal() == .OK, let u = panel.url, let d = try? Data(contentsOf: u) else { return nil }
    return (d, u.lastPathComponent)
}

// 新建资产表单:类型 + 创建方式(上传图 / 文字生成 / 文字+参考图生成),均走 op + 历史
struct NewElementSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var kind = "character"
    @State private var mode = "upload"      // upload | text | textref
    @State private var name = ""
    @State private var prompt = ""
    @State private var picked: (Data, String)?
    let kinds = ["character", "wardrobe", "prop", "environment", "styleframe"]
    func label(_ k: String) -> String { k == "character" ? "角色" : assetMeta(k).0 }

    var needsImage: Bool { mode == "upload" || mode == "textref" }
    var needsPrompt: Bool { mode == "text" || mode == "textref" }
    var canSubmit: Bool {
        !name.isEmpty && (!needsImage || picked != nil) && (!needsPrompt || !prompt.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建资产").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Picker("类型", selection: $kind) { ForEach(kinds, id: \.self) { Text(label($0)).tag($0) } }
                    .pickerStyle(.menu).tint(Theme.accent).frame(width: 130)
                Picker("方式", selection: $mode) {
                    Text("上传图片").tag("upload"); Text("文字生成").tag("text"); Text("文字+参考图").tag("textref")
                }.pickerStyle(.segmented)
            }
            DarkField(placeholder: "名称", text: $name)
            if needsPrompt { DarkField(placeholder: kind == "character" ? "外观描述(如:全身 正/侧/背 三视角…)" : "描述 / prompt", text: $prompt, multiline: true) }
            if needsImage {
                HStack(spacing: 8) {
                    Button { picked = pickImageData() } label: { Label(mode == "upload" ? "选择图片" : "选择参考图", systemImage: "photo.badge.plus") }
                        .buttonStyle(.bordered).tint(Theme.inkSoft)
                    if let p = picked { Text(p.1).font(.system(size: 11)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                }
            }
            Text(modeHint).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(mode == "upload" ? "创建" : "生成") {
                    let k = kind, n = name, pr = prompt, img = picked, m = mode
                    Task {
                        if m == "upload" { await state.newElement(kind: k, name: n, trigger: "", prompt: "", similarity: nil, image: img) }
                        else { await state.generateAsset(kind: k, name: n, prompt: pr, image: m == "textref" ? img : nil) }
                        dismiss()
                    }
                }.buttonStyle(.borderedProminent).tint(Theme.accent).disabled(!canSubmit || state.busy)
            }
        }.padding(20).frame(width: 440).background(Theme.bg)
    }

    var modeHint: String {
        switch mode {
        case "upload": return "直接把图片存为资产产物,不跑生成流程。"
        case "text": return "用文生图预设流程产出 1 张图(技术层可改流程)。"
        default: return "用参考编辑预设流程(参考图+文字)产出 1 张图(技术层可改流程)。"
        }
    }
}

// MARK: - 通用小组件

struct DarkField: View {
    let placeholder: String
    @Binding var text: String
    var multiline = false
    var body: some View {
        Group {
            if multiline { TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...8) }
            else { TextField(placeholder, text: $text) }
        }
        .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.ink)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct Thumb: View {
    @EnvironmentObject var state: AppState
    let path: String?
    var size: CGSize = CGSize(width: 160, height: 92)
    var icon = "photo"
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25))
            if let url = state.mediaURL(path) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { ProgressView().controlSize(.small) }
            } else {
                Image(systemName: icon).font(.title2).foregroundStyle(Theme.inkSoft.opacity(0.5))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }
}

// MARK: - 根布局(可折叠左右)

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false
    var vline: some View { Rectangle().fill(Theme.border).frame(width: 1) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if state.leftCollapsed {
                    CollapsedBar(icon: "sidebar.left", tip: "展开项目") { state.leftCollapsed = false }
                    vline
                } else {
                    LeftPane(showSettings: $showSettings).frame(width: 252)
                    vline
                }
                MiddlePane().frame(minWidth: 440, maxWidth: .infinity)
                if state.rightCollapsed {
                    vline
                    CollapsedBar(icon: "bubble.left.and.bubble.right", tip: "展开 Agent") { state.rightCollapsed = false }
                } else {
                    vline
                    AgentPane().frame(width: 360)
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            GlobalActivityBar()
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .task { await state.connect() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(item: $state.cloudConfirm) { c in CloudConfirmSheet(confirm: c) }
    }
}

// 费用闸:云调用前先确认估算
struct CloudConfirmSheet: View {
    @EnvironmentObject var state: AppState
    let confirm: AppState.CloudConfirm
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("云生成 · 费用确认").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
            HStack(spacing: 16) {
                VStack(alignment: .leading) { Text("预估时长").font(.system(size: 11)).foregroundStyle(Theme.inkSoft); Text("\(confirm.est.seconds ?? 0)s").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink) }
                VStack(alignment: .leading) { Text("预估费用").font(.system(size: 11)).foregroundStyle(Theme.inkSoft); Text("¥\(String(format: "%.2f", confirm.est.cost ?? 0))").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.accent) }
            }
            if let n = confirm.est.note { Text(n).font(.system(size: 11)).foregroundStyle(Theme.inkSoft) }
            HStack {
                Spacer()
                Button("取消") { state.cloudConfirm = nil }
                Button("确认并生成") { Task { await state.confirmCloud() } }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }.padding(20).frame(width: 380).background(Theme.bg)
    }
}

// 全局活动栏(常驻):连接 / 模型 / 当前任务 / 项目。任务队列与费用预估为后续。
struct GlobalActivityBar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(state.status == "已连接" ? .green : .secondary).frame(width: 7, height: 7)
            Text(state.status).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            if !state.model.isEmpty { Text("·").foregroundStyle(Theme.inkSoft); Text(state.model).font(.system(size: 11)).foregroundStyle(Theme.inkSoft) }
            Spacer()
            if state.busy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(state.activity.isEmpty ? "处理中…" : state.activity).font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
            Spacer()
            if state.totalCost > 0 {
                Text("累计 ¥\(String(format: "%.2f", state.totalCost))").font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
            Text(state.project).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 14).frame(height: 26).background(Theme.sidebar)
    }
}

struct CollapsedBar: View {
    let icon: String, tip: String, action: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Button(action: action) { Image(systemName: icon).font(.system(size: 15)) }
                .buttonStyle(.plain).foregroundStyle(Theme.inkSoft).help(tip)
            Spacer()
        }
        .padding(.top, 14).frame(width: 40).frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }
}

// MARK: - 左:项目 → 元素树

struct LeftPane: View {
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
                Button { state.leftCollapsed = true } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft).help("收起")
            }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(state.projects, id: \.self) { p in ProjectTree(name: p) }
                    if state.projects.isEmpty {
                        Text("暂无项目").font(.system(size: 12)).foregroundStyle(Theme.inkSoft).padding(.vertical, 8)
                    }
                }.padding(.horizontal, 8).padding(.top, 2)
            }

            Spacer(minLength: 0)
            Rectangle().fill(Theme.border).frame(height: 1)
            Button { showSettings = true } label: {
                TreeRow(icon: "gearshape", title: "设置 · 服务连接", level: 0, selected: false)
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

struct ProjectTree: View {
    @EnvironmentObject var state: AppState
    let name: String
    var isOpen: Bool { state.expanded.contains("p:" + name) }
    var isCurrent: Bool { name == state.project }

    var body: some View {
        VStack(spacing: 1) {
            TreeRow(icon: "film", title: name, level: 0, selected: isCurrent && state.selection == .overview,
                    chevron: isOpen) {
                if isCurrent { state.toggle("p:" + name) }
                else { Task { await state.selectProject(name) } }
            }
            if isOpen && isCurrent {
                leaf("rectangle.3.group", "概览", .overview, 1)
                group("person.2", "角色", state.characters.count, "g:char", .characters) {
                    ForEach(state.characters) { c in
                        leaf("person.crop.circle", c.name, .character(c.id), 2)
                    }
                }
                group("shippingbox", "资产", state.assets.count, "g:asset", .assets) {
                    ForEach(state.assets) { a in
                        leaf(assetMeta(a.type).1, a.name, .asset(a.id), 2)
                    }
                }
                group("rectangle.stack", "分镜", state.shots.count, "g:shot", .shotsRoot) {
                    ForEach(Array(state.shots.enumerated()), id: \.element.id) { i, s in
                        leaf("rectangle", "镜 \(i+1) · \(s.script ?? s.id)", .shot(s.id), 2)
                    }
                }
                leaf("film.stack", "成片 / 导出", .timeline, 1)
            }
        }
    }

    func leaf(_ icon: String, _ title: String, _ sel: Sel, _ level: Int) -> some View {
        TreeRow(icon: icon, title: title, level: level, selected: state.selection == sel) {
            state.selection = sel
        }
    }

    @ViewBuilder
    func group<C: View>(_ icon: String, _ title: String, _ count: Int, _ key: String, _ sel: Sel,
                        @ViewBuilder _ children: () -> C) -> some View {
        let open = state.expanded.contains(key)
        TreeRow(icon: icon, title: title, level: 1, selected: state.selection == sel, count: count, chevron: open) {
            state.selection = sel; state.toggle(key)
        }
        if open { children() }
    }
}

struct TreeRow: View {
    let icon: String, title: String, level: Int, selected: Bool
    var count: Int? = nil
    var chevron: Bool? = nil          // nil=无(叶子); true=展开; false=折叠
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let c = chevron {
                    Image(systemName: c ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkSoft).frame(width: 10)
                } else { Spacer().frame(width: 10) }
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(selected ? Theme.accent : Theme.inkSoft).frame(width: 16)
                Text(title).font(.system(size: 13)).foregroundStyle(selected ? Theme.ink : Theme.inkSoft).lineLimit(1)
                Spacer(minLength: 4)
                if let n = count { Text("\(n)").font(.system(size: 11)).foregroundStyle(Theme.inkSoft.opacity(0.7)) }
            }
            .padding(.leading, CGFloat(level) * 14 + 8).padding(.trailing, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.surfaceHi : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: - 中:元素预览 / 编辑(导演 / 技术 双视角)

struct MiddlePane: View {
    @EnvironmentObject var state: AppState
    @State private var preview: IdentURL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            if state.openGraphShot != nil {
                NodeCanvasView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch state.selection {
                        case .overview, .shotsRoot: ProductionBoard(preview: $preview)
                        case .characters: GalleryView(kind: .characters)
                        case .assets: GalleryView(kind: .assets)
                        case .character(let id): CharacterDetail(id: id)
                        case .asset(let id): AssetDetail(id: id)
                        case .shot(let id): ShotDetail(id: id, preview: $preview)
                        case .timeline: TimelineView(preview: $preview)
                        }
                    }.padding(16)
                }
            }
        }
        .background(Theme.bg)
        .sheet(item: $preview) { item in
            VStack(spacing: 0) {
                VideoPlayer(player: AVPlayer(url: item.url)).frame(width: 760, height: 440)
                HStack { Spacer(); Button("关闭") { preview = nil }.keyboardShortcut(.defaultAction) }.padding(10)
            }.background(Theme.bg)
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            if state.leftCollapsed {
                Button { state.leftCollapsed = false } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
            }
            if state.openGraphShot != nil {
                Button { state.closeGraph() } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).help("返回导演层")
            }
            Text(breadcrumb).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer()
            Button { state.rightCollapsed.toggle() } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(.plain).foregroundStyle(state.rightCollapsed ? Theme.inkSoft : Theme.accent).help("Agent")
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    var breadcrumb: String {
        if let g = state.openGraphShot {
            let i = (state.shots.firstIndex { $0.id == g }).map { $0 + 1 } ?? 0
            return "镜 \(i) · 生成 · 节点图(技术层)"
        }
        switch state.selection {
        case .overview: return "\(state.project) · 概览"
        case .characters: return "\(state.project) · 角色"
        case .assets: return "\(state.project) · 资产"
        case .shotsRoot: return "\(state.project) · 分镜"
        case .character(let id): return "角色 · \(state.character(id)?.name ?? id)"
        case .asset(let id): return "资产 · \(state.asset(id)?.name ?? id)"
        case .shot(let id):
            let i = (state.shots.firstIndex { $0.id == id }).map { $0 + 1 } ?? 0
            return "镜 \(i)"
        case .timeline: return "\(state.project) · 成片"
        }
    }
}

// ---- 导演层:制片管理面(以分镜头为主轴)----

struct ProductionBoard: View {
    @EnvironmentObject var state: AppState
    @Binding var preview: IdentURL?
    @State private var showCompose = false

    var body: some View {
        // 顶部:Character Bible / 资产(一致性锚点,共享一等区)
        BibleStrip()

        // 项目元信息
        if let m = state.detail?.meta {
            HStack(spacing: 8) {
                Pill(text: m.aspect ?? "16:9", color: Theme.inkSoft)
                Pill(text: m.resolution ?? "1080p", color: Theme.inkSoft)
                Pill(text: "\(m.fps ?? 24)fps", color: Theme.inkSoft)
                Pill(text: m.style ?? "realistic", color: Theme.accent)
                Spacer()
            }
        }

        // 分镜任务区
        HStack {
            SectionLabel(icon: "rectangle.stack", text: "分镜 · 制片(\(state.shots.count))")
            Spacer()
            Button { withAnimation { showCompose.toggle() } } label: {
                Label(showCompose ? "收起" : "新建短片", systemImage: showCompose ? "chevron.up" : "plus")
                    .font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(Theme.accent)
        }
        if showCompose { ComposeCard() }

        if state.shots.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack").font(.system(size: 36)).foregroundStyle(Theme.inkSoft.opacity(0.5))
                Text("还没有分镜").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                Text("点「新建短片」让导演 Agent 拆镜出片,或在右侧对话。")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            }.frame(maxWidth: .infinity, minHeight: 220).padding(20)
        } else {
            ForEach(Array(state.shots.enumerated()), id: \.element.id) { i, s in
                ShotRow(index: i + 1, shot: s, preview: $preview)
            }
        }
    }
}

// Character Bible + 资产 横向条
struct BibleStrip: View {
    @EnvironmentObject var state: AppState
    @State private var showNew = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(icon: "person.2.crop.square.stack", text: "Character Bible / 资产")
                Spacer()
                Button { showNew = true } label: { Label("新建", systemImage: "plus").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            if state.characters.isEmpty && state.assets.isEmpty {
                Text("暂无角色/资产。生成短片或让 Agent 备齐后,会自动进入档案。")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(state.characters) { c in
                            chip(c.finals?.first, c.name, "角色", "person.crop.circle") { state.selection = .character(c.id) }
                        }
                        ForEach(state.assets) { a in
                            chip(a.finals?.first, a.name, assetMeta(a.type).0, assetMeta(a.type).1) { state.selection = .asset(a.id) }
                        }
                    }.padding(.vertical, 2)
                }
            }
        }.card()
        .sheet(isPresented: $showNew) { NewElementSheet() }
    }
    func chip(_ path: String?, _ name: String, _ tag: String, _ icon: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 4) {
                Thumb(path: path, size: CGSize(width: 84, height: 84), icon: icon)
                Text(name).font(.system(size: 11)).foregroundStyle(Theme.ink).lineLimit(1).frame(width: 84)
                Text(tag).font(.system(size: 9)).foregroundStyle(Theme.inkSoft)
            }
        }.buttonStyle(.plain)
    }
}

// 镜头行:任务流水线(分镜·生成·选片)+ 预览 + 资产依赖
struct ShotRow: View {
    @EnvironmentObject var state: AppState
    let index: Int
    let shot: Shot
    @Binding var preview: IdentURL?

    // 流水线状态:0=未,1=进行/部分,2=完成
    var stStoryboard: Int { (shot.scene_prompt?.isEmpty == false || shot.script?.isEmpty == false) ? 2 : 0 }
    var stGenerate: Int {
        if let t = shot.takes, !t.isEmpty { return 2 }
        if shot.keyframe != nil { return 1 }
        return 0
    }
    var stSelect: Int { shot.selected_take != nil ? 2 : (shot.takes?.isEmpty == false ? 1 : 0) }
    var selectedTake: Take? { shot.takes?.first { $0.id == shot.selected_take } }

    var body: some View {
        Button { state.selection = .shot(shot.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                Thumb(path: shot.keyframe, size: CGSize(width: 150, height: 86))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("镜 \(index)").font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.18), in: Capsule()).foregroundStyle(Theme.accent)
                        Text(shot.script ?? shot.id).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        stage("分镜", stStoryboard)
                        stage("生成", stGenerate)
                        stage("选片", stSelect)
                    }
                    if let r = shot.refs, !r.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "link").font(.system(size: 9)).foregroundStyle(Theme.inkSoft)
                            ForEach(r, id: \.self) { id in
                                Text(state.character(id)?.name ?? id).font(.system(size: 10))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Theme.surfaceHi, in: Capsule()).foregroundStyle(Theme.inkSoft)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if let t = selectedTake, let u = state.mediaURL(t.video) {
                    Button { preview = IdentURL(url: u) } label: { Image(systemName: "play.circle.fill").font(.system(size: 24)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }.card()
        }.buttonStyle(.plain)
    }

    func stage(_ name: String, _ st: Int) -> some View {
        let color: Color = st == 2 ? .green : (st == 1 ? Theme.accent : Theme.inkSoft.opacity(0.6))
        let icon = st == 2 ? "checkmark.circle.fill" : (st == 1 ? "circle.dotted" : "circle")
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(name).font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule()).foregroundStyle(color)
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
            Stepper("镜头数 \(state.nShots)", value: $state.nShots, in: 1...8)
                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                Button { Task { await state.makeFilm() } } label: { Label("生成短片", systemImage: "sparkles") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(state.busy)
                Button { Task { await state.export() } } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.bordered).tint(Theme.inkSoft).disabled(state.busy).help("导出 FCPXML")
            }
        }.card()
    }
}

// ---- 画廊(角色/资产/分镜 分组)----

struct GalleryView: View {
    @EnvironmentObject var state: AppState
    let kind: Sel
    let cols = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            switch kind {
            case .characters:
                ForEach(state.characters) { c in
                    card(c.finals?.first, c.name, "person", "person.crop.circle") { state.selection = .character(c.id) }
                }
            case .assets:
                ForEach(state.assets) { a in
                    card(a.finals?.first, a.name, assetMeta(a.type).0, assetMeta(a.type).1) { state.selection = .asset(a.id) }
                }
            case .shotsRoot:
                ForEach(Array(state.shots.enumerated()), id: \.element.id) { i, s in
                    card(s.keyframe, "镜 \(i+1)", s.script ?? "", "rectangle") { state.selection = .shot(s.id) }
                }
            default: EmptyView()
            }
        }
        if isEmpty {
            Text("此分类暂无内容。在右侧让 Agent 帮你生成,或「生成短片」自动补齐。")
                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft).padding(.top, 6)
        }
    }
    var isEmpty: Bool {
        switch kind {
        case .characters: return state.characters.isEmpty
        case .assets: return state.assets.isEmpty
        case .shotsRoot: return state.shots.isEmpty
        default: return true
        }
    }
    func card(_ path: String?, _ title: String, _ sub: String, _ icon: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 6) {
                Thumb(path: path, size: CGSize(width: 168, height: 100), icon: icon)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
            }
        }.buttonStyle(.plain)
    }
}

// ---- 角色详情 ----

struct CharacterDetail: View {
    @EnvironmentObject var state: AppState
    let id: String
    var refs: [Int] {
        state.shots.enumerated().compactMap { i, s in (s.refs ?? []).contains(id) ? i + 1 : nil }
    }
    var body: some View {
        if let c = state.character(id) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(icon: "person.crop.circle", text: c.name)
                if let f = c.finals, !f.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) { ForEach(f, id: \.self) { Thumb(path: $0, size: CGSize(width: 180, height: 240), icon: "person") } }
                    }
                } else { Text("暂无定稿图").font(.system(size: 12)).foregroundStyle(Theme.inkSoft) }
            }.card()
            IdentityLockCard(c: c).id(c.id)
            // 一致性:被哪些镜头引用 + 一键重生成
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(icon: "link", text: "一致性 · 被引用")
                if refs.isEmpty {
                    Text("尚无镜头引用此角色。").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                } else {
                    HStack(spacing: 5) {
                        ForEach(refs, id: \.self) { Text("镜 \($0)").font(.system(size: 11)).padding(.horizontal, 7).padding(.vertical, 2).background(Theme.surfaceHi, in: Capsule()).foregroundStyle(Theme.inkSoft) }
                        Spacer()
                        Button { } label: { Label("重生成受影响镜头", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 11)) }
                            .buttonStyle(.plain).foregroundStyle(Theme.inkSoft).disabled(true).help("待接入(⑤/⑥)")
                    }
                }
            }.card()
        }
    }
}

// 身份锁定卡(可编辑:触发词 / 相似度阈值 / LoRA),改动经 op 入历史
struct IdentityLockCard: View {
    @EnvironmentObject var state: AppState
    let c: Character
    @State private var trigger: String
    @State private var sim: Double
    @State private var useSim: Bool
    init(c: Character) {
        self.c = c
        _trigger = State(initialValue: c.trigger ?? "")
        _sim = State(initialValue: c.similarity ?? 0.85)
        _useSim = State(initialValue: c.similarity != nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(icon: "lock.shield", text: "身份锁定卡")
            DarkField(placeholder: "触发词", text: $trigger)
            Toggle(isOn: $useSim) { Text("一致性相似度阈值 \(useSim ? String(format: "%.2f", sim) : "—")").font(.system(size: 12)).foregroundStyle(Theme.inkSoft) }
            if useSim { Slider(value: $sim, in: 0.5...0.99).tint(Theme.accent) }
            HStack {
                Pill(text: c.lora == nil ? "未训练 LoRA" : "LoRA ✓", color: c.lora == nil ? Theme.inkSoft : .green)
                Text(c.source == "image" ? "来源:参考图" : "来源:文本").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Button { Task { await state.updateCharacter(c.id, trigger: trigger, similarity: useSim ? sim : nil) } } label: {
                    Text("保存").font(.system(size: 12, weight: .semibold))
                }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }.card()
    }
}

// ---- 资产详情 ----

struct AssetDetail: View {
    @EnvironmentObject var state: AppState
    let id: String
    var body: some View {
        if let a = state.asset(id) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { SectionLabel(icon: assetMeta(a.type).1, text: a.name); Pill(text: assetMeta(a.type).0, color: Theme.accent) }
                if let f = a.finals, !f.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) { ForEach(f, id: \.self) { Thumb(path: $0, size: CGSize(width: 200, height: 130)) } }
                    }
                } else { Text("暂无参考图").font(.system(size: 12)).foregroundStyle(Theme.inkSoft) }
                if let p = a.prompt, !p.isEmpty { Text(p).font(.system(size: 12)).foregroundStyle(Theme.inkSoft) }
            }.card()
        }
    }
}

// ---- 分镜详情 ----

struct ShotDetail: View {
    @EnvironmentObject var state: AppState
    let id: String
    @Binding var preview: IdentURL?
    var body: some View {
        if let s = state.shot(id) { director(s) }
    }

    func director(_ s: Shot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            lockBar(s)
            Thumb(path: s.keyframe, size: CGSize(width: 480, height: 270))
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(icon: "text.alignleft", text: "剧情")
                Text(s.script ?? "—").font(.system(size: 14)).foregroundStyle(Theme.ink)
                if let r = s.refs, !r.isEmpty {
                    HStack(spacing: 6) {
                        Text("引用角色").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        ForEach(r, id: \.self) { Pill(text: state.character($0)?.name ?? $0, color: Theme.accent) }
                    }
                }
                if let sp = s.scene_prompt { labeled("画面 prompt", sp) }
                if let mp = s.motion_prompt { labeled("运动 prompt", mp) }
            }.card()
            // 生成视频(本地/云,云走费用闸)
            HStack(spacing: 8) {
                Button { Task { await state.generate(shot: s.id, backend: "local") } } label: {
                    Label("本地生成", systemImage: "bolt.fill").font(.system(size: 12))
                }.buttonStyle(.borderedProminent).tint(Theme.accent).disabled(state.busy || s.keyframe == nil)
                Button { Task { await state.generate(shot: s.id, backend: "cloud") } } label: {
                    Label("云生成", systemImage: "cloud.fill").font(.system(size: 12))
                }.buttonStyle(.bordered).tint(Theme.inkSoft).disabled(state.busy || s.keyframe == nil)
                if s.keyframe == nil { Text("需先有关键帧").font(.system(size: 11)).foregroundStyle(Theme.inkSoft) }
            }
            // 任务 → 钻进技术层(节点图)
            HStack(spacing: 8) {
                taskChip("生成", "keyframe_edit")
                taskChip("成片", "i2v_local")
                Text("点任务进入技术层 flow").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }
            takesCard(s)
        }
    }

    func taskChip(_ name: String, _ task: String) -> some View {
        Button { Task { await state.openGraph(id, task: task) } } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 11))
                Text(name + " · 节点图").font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
            .foregroundStyle(Theme.accent)
        }.buttonStyle(.plain).disabled(state.busy)
    }

    @ViewBuilder
    func lockBar(_ s: Shot) -> some View {
        let lk = state.locks[s.id]
        HStack(spacing: 8) {
            Image(systemName: lk == nil ? "lock.open" : "lock.fill").font(.system(size: 11))
                .foregroundStyle(lk == nil ? Theme.inkSoft : (lk?.actor == "agent" ? Theme.accent : .green))
            Text(lk == nil ? "未锁定 · 单镜头单 actor 持笔" : "编辑中:\(lk?.actor == "agent" ? "Agent" : "你")")
                .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            Spacer()
            if lk == nil {
                Button("锁定编辑") { Task { await state.lockShot(s.id) } }.buttonStyle(.bordered).tint(Theme.inkSoft).controlSize(.small)
            } else if lk?.actor == "agent" {
                Button("接管") { Task { await state.lockShot(s.id, actor: "human") } }.buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
            } else {
                Button("释放") { Task { await state.unlockShot(s.id) } }.buttonStyle(.bordered).tint(Theme.inkSoft).controlSize(.small)
            }
        }
    }

    func labeled(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
            Text(v).font(.system(size: 12)).foregroundStyle(Theme.ink).textSelection(.enabled)
        }.padding(.top, 2)
    }

    func takesCard(_ s: Shot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(icon: "play.rectangle", text: "镜次 takes")
            if let takes = s.takes, !takes.isEmpty {
                ForEach(takes) { t in
                    let sel = t.id == s.selected_take
                    HStack(spacing: 10) {
                        Button { if let u = state.mediaURL(t.video) { preview = IdentURL(url: u) } } label: {
                            Label("播放", systemImage: "play.circle.fill").font(.system(size: 13))
                        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                        if let m = t.meta {
                            Text("\(m.recipe ?? "")  ·  \(m.backend ?? "")").font(.system(size: 11)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                        Spacer()
                        Button { Task { await state.select(shot: s.id, take: t.id) } } label: {
                            Label(sel ? "已选用" : "选用", systemImage: sel ? "checkmark.seal.fill" : "seal")
                                .font(.system(size: 12)).foregroundStyle(sel ? .green : Theme.inkSoft)
                        }.buttonStyle(.plain)
                    }
                }
            } else { Text("尚无 take。在右侧让 Agent 出片,或「生成短片」。").font(.system(size: 12)).foregroundStyle(Theme.inkSoft) }
        }.card()
    }
}

// ---- 成片 / 导出 ----

struct TimelineView: View {
    @EnvironmentObject var state: AppState
    @Binding var preview: IdentURL?
    var ready: [(Int, Shot, Take)] {
        state.shots.enumerated().compactMap { i, s in
            guard let tid = s.selected_take, let t = s.takes?.first(where: { $0.id == tid }) else { return nil }
            return (i + 1, s, t)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(icon: "film.stack", text: "成片时间线")
                Spacer()
                Button { Task { await state.export() } } label: { Label("导出 FCPXML", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle()).frame(width: 160).disabled(state.busy)
            }
            if ready.isEmpty {
                Text("还没有选定的镜次。去各分镜里「选用」一个 take,这里会组成成片。")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ready, id: \.1.id) { idx, s, t in
                            Button { if let u = state.mediaURL(t.video) { preview = IdentURL(url: u) } } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Thumb(path: s.keyframe, size: CGSize(width: 180, height: 102))
                                    Text("镜 \(idx)").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.card()
    }
}

// MARK: - 右:Agent

struct AgentPane: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""
    @State private var tab = 0   // 0=对话 1=历史
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Array(["对话", "历史"].enumerated()), id: \.offset) { i, name in
                    Button { tab = i } label: {
                        Text(name).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(tab == i ? Theme.surfaceHi : .clear))
                            .foregroundStyle(tab == i ? Theme.ink : Theme.inkSoft)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { state.rightCollapsed = true } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft).help("收起")
            }.padding(.horizontal, 12).padding(.vertical, 10)
            Rectangle().fill(Theme.border).frame(height: 1)

            if tab == 1 { HistoryList() } else { chatBody }

            HStack(spacing: 8) {
                Pill(text: state.model.isEmpty ? "—" : state.model, color: Theme.accent)
                if let b = state.backends.first { Pill(text: b.name.replacingOccurrences(of: "local-", with: ""), color: Theme.inkSoft) }
                Text(state.project).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                Spacer()
            }.padding(.horizontal, 14).padding(.bottom, 10)
        }
        .background(Theme.bg)
    }

    var chatBody: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if state.chatLog.isEmpty {
                            Text("对 Agent 说点什么 —— 它能拆剧本、备资产、出关键帧与成片。")
                                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
                        }
                        ForEach(Array(state.chatLog.enumerated()), id: \.offset) { i, line in Bubble(line: line).id(i) }
                    }.padding(12)
                }
                .onChange(of: state.chatLog.count) { _ in
                    if let last = state.chatLog.indices.last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            VStack(spacing: 8) {
                TextField("给 Agent 发消息…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.ink)
                    .lineLimit(3...8).frame(minHeight: 64, alignment: .topLeading).onSubmit(send)
                HStack {
                    if state.busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.plain).foregroundStyle(input.isEmpty ? Theme.inkSoft : Theme.accent).disabled(input.isEmpty)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
            .padding(12)
        }
    }
    func send() { let t = input; input = ""; Task { await state.send(t) } }
}

// 统一历史:每个变更按作者着色,可解释日志(api-contract / native-ui §5)
struct HistoryList: View {
    @EnvironmentObject var state: AppState
    func color(_ author: String) -> Color { author == "agent" ? Theme.accent : Color(red: 0.42, green: 0.66, blue: 0.86) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !state.history.isEmpty {
                    HStack {
                        Text("统一历史").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Button { Task { await state.undoLast() } } label: { Label("撤销最近", systemImage: "arrow.uturn.backward").font(.system(size: 11)) }
                            .buttonStyle(.bordered).tint(Theme.inkSoft).controlSize(.small).disabled(state.busy)
                    }
                }
                if state.history.isEmpty {
                    Text("还没有变更。选用 take、改参等写操作都会进这条统一历史。")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
                }
                ForEach(state.history) { c in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(color(c.author)).frame(width: 7, height: 7).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(c.seq) · \(c.rationale ?? "变更")").font(.system(size: 12))
                                .foregroundStyle(c.undone == true ? Theme.inkSoft : Theme.ink)
                                .strikethrough(c.undone == true)
                            Text((c.author == "agent" ? "Agent" : "你") + (c.undone == true ? " · 已撤销" : "")).font(.system(size: 10)).foregroundStyle(color(c.author))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                }
            }.padding(12)
        }
    }
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

// MARK: - 技术层:节点画布(钻进单镜任务的执行 flow)

struct NodeCanvasView: View {
    @EnvironmentObject var state: AppState
    @State private var selected: String?
    let NW: CGFloat = 178

    var nodesById: [String: NodeVM] { Dictionary(state.graphNodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    var canvasSize: CGSize {
        let mx = state.graphNodes.map { $0.pos.x }.max() ?? 0
        let my = state.graphNodes.map { $0.pos.y }.max() ?? 0
        return CGSize(width: mx + NW + 80, height: my + 300)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { ctx, _ in
                            for l in state.graphLinks {
                                guard let s = nodesById[l.from], let d = nodesById[l.to] else { continue }
                                let a = CGPoint(x: s.pos.x + NW, y: s.pos.y + 18)
                                let b = CGPoint(x: d.pos.x, y: d.pos.y + 18)
                                var p = Path()
                                p.move(to: a)
                                p.addCurve(to: b, control1: CGPoint(x: a.x + 55, y: a.y), control2: CGPoint(x: b.x - 55, y: b.y))
                                ctx.stroke(p, with: .color(Theme.inkSoft.opacity(0.55)), lineWidth: 1.5)
                            }
                        }.frame(width: canvasSize.width, height: canvasSize.height)
                        ForEach(state.graphNodes) { n in
                            NodeCardView(node: n, selected: selected == n.id, width: NW,
                                         proposed: state.proposed.contains { $0.node == n.id })
                                .offset(x: n.pos.x, y: n.pos.y)
                                .onTapGesture { selected = n.id }
                        }
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                    .padding(20)
                }
                .background(Theme.bg)

                if let sel = selected, let n = nodesById[sel] {
                    Rectangle().fill(Theme.border).frame(width: 1)
                    NodeInspector(node: n).frame(width: 240)
                }
            }
        }
    }

    var toolbar: some View {
        HStack(spacing: 10) {
            // 省心↔掌控滑块
            HStack(spacing: 2) {
                ForEach(Array(["省心", "中", "掌控"].enumerated()), id: \.offset) { i, name in
                    Button { state.approvalMode = i } label: {
                        Text(name).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(state.approvalMode == i ? Theme.accent : .clear))
                            .foregroundStyle(state.approvalMode == i ? .white : Theme.inkSoft)
                    }.buttonStyle(.plain)
                }
            }.padding(2).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
            Text(state.approvalMode == 0 ? "改参自动应用(可撤销)" : "改参暂存 Proposed").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            Spacer()
            if !state.proposed.isEmpty {
                Text("\(state.proposed.count) 处待应用").font(.system(size: 11)).foregroundStyle(Theme.accent)
                Button("接受全部") { Task { await state.acceptProposed() } }.buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                Button("放弃") { state.discardProposed() }.buttonStyle(.bordered).tint(Theme.inkSoft).controlSize(.small)
            }
            if let sel = selected {
                Button { Task { await state.deleteNode(sel); selected = nil } } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft).help("删除选中节点")
            }
        }.padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct NodeCardView: View {
    let node: NodeVM
    let selected: Bool
    let width: CGFloat
    var proposed: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(node.classType).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if proposed { Image(systemName: "pencil.circle.fill").font(.system(size: 10)).foregroundStyle(.white) }
            }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(proposed ? Color.orange.opacity(0.85) : Theme.accent.opacity(selected ? 0.95 : 0.7))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(node.params.prefix(5)), id: \.0) { k, v in
                    HStack(spacing: 4) {
                        Text(k).foregroundStyle(Theme.inkSoft)
                        Text(v).foregroundStyle(Theme.ink).lineLimit(1)
                    }.font(.system(size: 9))
                }
                if node.params.count > 5 { Text("… +\(node.params.count - 5)").font(.system(size: 9)).foregroundStyle(Theme.inkSoft) }
                if node.params.isEmpty { Text("—").font(.system(size: 9)).foregroundStyle(Theme.inkSoft) }
            }.padding(8)
        }
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct NodeInspector: View {
    @EnvironmentObject var state: AppState
    let node: NodeVM
    @State private var vals: [String: String]
    init(node: NodeVM) {
        self.node = node
        _vals = State(initialValue: Dictionary(node.params, uniquingKeysWith: { a, _ in a }))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(icon: "slider.horizontal.3", text: node.classType)
                Text("id \(node.id)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                ForEach(Array(node.params), id: \.0) { k, v in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        TextField("", text: Binding(get: { vals[k] ?? v }, set: { vals[k] = $0 }))
                            .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
                            .onSubmit { Task { await state.editParam(node: node.id, widget: k, old: v, text: vals[k] ?? v) } }
                    }
                }
                Text(state.approvalMode == 0 ? "回车即应用 op(可在历史撤销)" : "回车暂存为 Proposed,顶栏「接受全部」入历史")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkSoft.opacity(0.8)).padding(.top, 6)
            }.padding(12)
        }.background(Theme.sidebar)
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
