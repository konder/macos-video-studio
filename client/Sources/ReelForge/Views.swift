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

struct FieldRow: View {
    let k: String, v: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft).frame(width: 92, alignment: .leading)
            Text(v.isEmpty ? "—" : v).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.ink)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 根布局(可折叠左右)

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false
    var vline: some View { Rectangle().fill(Theme.border).frame(width: 1) }

    var body: some View {
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
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .task { await state.connect() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch state.selection {
                    case .overview: OverviewView()
                    case .characters: GalleryView(kind: .characters)
                    case .assets: GalleryView(kind: .assets)
                    case .shotsRoot: GalleryView(kind: .shotsRoot)
                    case .character(let id): CharacterDetail(id: id)
                    case .asset(let id): AssetDetail(id: id)
                    case .shot(let id): ShotDetail(id: id, preview: $preview)
                    case .timeline: TimelineView(preview: $preview)
                    }
                }.padding(16)
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
            Text(breadcrumb).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer()
            if showsViewToggle { ViewModeToggle() }
            Button { state.rightCollapsed.toggle() } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(.plain).foregroundStyle(state.rightCollapsed ? Theme.inkSoft : Theme.accent).help("Agent")
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    var showsViewToggle: Bool {
        switch state.selection {
        case .character, .asset, .shot: return true
        default: return false
        }
    }

    var breadcrumb: String {
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

struct ViewModeToggle: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 2) {
            ForEach([ViewMode.director, .technical], id: \.rawValue) { m in
                Button { state.viewMode = m } label: {
                    Text(m.rawValue + "视角").font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(state.viewMode == m ? Theme.accent : .clear))
                        .foregroundStyle(state.viewMode == m ? .white : Theme.inkSoft)
                }.buttonStyle(.plain)
            }
        }
        .padding(2).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
    }
}

// ---- 概览 ----

struct OverviewView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        if let m = state.detail?.meta {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(icon: "info.circle", text: "项目概览")
                HStack(spacing: 8) {
                    Pill(text: m.aspect ?? "16:9", color: Theme.inkSoft)
                    Pill(text: m.resolution ?? "1080p", color: Theme.inkSoft)
                    Pill(text: "\(m.fps ?? 24)fps", color: Theme.inkSoft)
                    Pill(text: m.style ?? "realistic", color: Theme.accent)
                }
                HStack(spacing: 18) {
                    stat("角色", state.characters.count)
                    stat("资产", state.assets.count)
                    stat("分镜", state.shots.count)
                }.padding(.top, 4)
            }.card()
        }
        ComposeCard()
    }
    func stat(_ k: String, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
            Text(k).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
        }
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
    var body: some View {
        if let c = state.character(id) {
            if state.viewMode == .director {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(icon: "person.crop.circle", text: c.name)
                    if let f = c.finals, !f.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) { ForEach(f, id: \.self) { Thumb(path: $0, size: CGSize(width: 180, height: 240), icon: "person") } }
                        }
                    } else { Text("暂无定稿图").font(.system(size: 12)).foregroundStyle(Theme.inkSoft) }
                    HStack(spacing: 8) {
                        if let t = c.trigger, !t.isEmpty { Pill(text: "trigger: \(t)", color: Theme.accent) }
                        Pill(text: c.lora == nil ? "未训练 LoRA" : "LoRA ✓", color: c.lora == nil ? Theme.inkSoft : .green)
                    }
                }.card()
            } else {
                techCard("角色 · 技术") {
                    FieldRow(k: "id", v: c.id)
                    FieldRow(k: "source", v: c.source ?? "")
                    FieldRow(k: "trigger", v: c.trigger ?? "")
                    FieldRow(k: "lora", v: c.lora ?? "")
                    ForEach(Array((c.finals ?? []).enumerated()), id: \.offset) { i, p in FieldRow(k: "finals[\(i)]", v: p) }
                }
            }
        }
    }
}

// ---- 资产详情 ----

struct AssetDetail: View {
    @EnvironmentObject var state: AppState
    let id: String
    var body: some View {
        if let a = state.asset(id) {
            if state.viewMode == .director {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { SectionLabel(icon: assetMeta(a.type).1, text: a.name); Pill(text: assetMeta(a.type).0, color: Theme.accent) }
                    if let f = a.finals, !f.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) { ForEach(f, id: \.self) { Thumb(path: $0, size: CGSize(width: 200, height: 130)) } }
                        }
                    } else { Text("暂无参考图").font(.system(size: 12)).foregroundStyle(Theme.inkSoft) }
                    if let p = a.prompt, !p.isEmpty { Text(p).font(.system(size: 12)).foregroundStyle(Theme.inkSoft) }
                }.card()
            } else {
                techCard("资产 · 技术") {
                    FieldRow(k: "id", v: a.id)
                    FieldRow(k: "type", v: a.type)
                    FieldRow(k: "prompt", v: a.prompt ?? "")
                    ForEach(Array((a.finals ?? []).enumerated()), id: \.offset) { i, p in FieldRow(k: "finals[\(i)]", v: p) }
                }
            }
        }
    }
}

// ---- 分镜详情 ----

struct ShotDetail: View {
    @EnvironmentObject var state: AppState
    let id: String
    @Binding var preview: IdentURL?
    var body: some View {
        if let s = state.shot(id) {
            if state.viewMode == .director { director(s) } else { technical(s) }
        }
    }

    func director(_ s: Shot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
            takesCard(s)
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

    func technical(_ s: Shot) -> some View {
        let recipe = s.takes?.first?.meta?.recipe ?? "keyframe_edit + i2v_local"
        return techCard("分镜 · 技术(Graph IR)") {
            FieldRow(k: "id", v: s.id)
            FieldRow(k: "recipe", v: recipe)
            FieldRow(k: "refs", v: (s.refs ?? []).joined(separator: ", "))
            FieldRow(k: "keyframe", v: s.keyframe ?? "")
            FieldRow(k: "scene", v: s.scene_prompt ?? "")
            FieldRow(k: "motion", v: s.motion_prompt ?? "")
            ForEach(Array((s.takes ?? []).enumerated()), id: \.offset) { i, t in
                FieldRow(k: "take[\(i)]", v: "\(t.video ?? "")  seed=\(t.meta?.seed.map(String.init) ?? "-")")
            }
            Text("节点画布(可视化编辑 ComfyUI 图 + op 协议)为下一层,当前展示已落库的图参数。")
                .font(.system(size: 11)).foregroundStyle(Theme.inkSoft.opacity(0.8)).padding(.top, 4)
        }
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

@ViewBuilder
func techCard<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        SectionLabel(icon: "chevron.left.forwardslash.chevron.right", text: title)
        content()
    }.card()
}

// MARK: - 右:Agent

struct AgentPane: View {
    @EnvironmentObject var state: AppState
    @State private var input = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(icon: "sparkle", text: "Agent")
                Spacer()
                Button { state.rightCollapsed = true } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft).help("收起")
            }.padding(.horizontal, 14).padding(.vertical, 12)
            Rectangle().fill(Theme.border).frame(height: 1)

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
