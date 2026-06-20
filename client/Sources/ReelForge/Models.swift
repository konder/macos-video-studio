import Foundation

// 与 Orchestrator API 对应的数据模型(api-contract / mvp-tech-plan)。

struct Backend: Codable, Identifiable, Hashable {
    let name: String
    let kind: String?
    let url: String?
    let latency: String?
    let vram_gb: Int?
    let caps: [String]?
    var id: String { name }
}

struct Recipe: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let stage: String?
}

struct TakeMeta: Codable, Hashable {
    let backend: String?
    let recipe: String?
    let seed: Int?
}

struct Take: Codable, Identifiable, Hashable {
    let id: String
    let video: String?
    let meta: TakeMeta?
}

struct Shot: Codable, Identifiable, Hashable {
    let id: String
    let script: String?
    let refs: [String]?
    let scene_prompt: String?
    let motion_prompt: String?
    let keyframe: String?
    let selected_take: String?
    let takes: [Take]?
}

// ---- 项目元素(构成视频的全部)----
struct Meta: Codable, Hashable {
    let title: String?
    let aspect: String?
    let resolution: String?
    let fps: Int?
    let style: String?
}

struct Character: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let source: String?
    let finals: [String]?
    let trigger: String?
    let lora: String?
}

struct Asset: Codable, Identifiable, Hashable {
    let id: String
    let type: String       // wardrobe / prop / environment / styleframe
    let name: String
    let prompt: String?
    let finals: [String]?
}

// 统一历史里的一个变更(api-contract:ops[] + author/ts/rationale,带 seq)
struct Change: Codable, Identifiable, Hashable {
    let seq: Int
    let author: String
    let rationale: String?
    let ts: Double?
    var id: Int { seq }
}

struct ProjectDetail: Codable {
    let meta: Meta?
    let characters: [Character]?
    let assets: [Asset]?
    let shots: [Shot]?
    let history: [Change]?
    let seq: Int?
}

struct ProjectsList: Codable { let projects: [String] }
struct ShotsResponse: Codable { let shots: [Shot] }
struct RecipesResponse: Codable { let recipes: [Recipe] }
struct BackendsResponse: Codable { let backends: [Backend] }
struct HealthResponse: Codable { let ok: Bool; let model: String?; let recipes: [String]? }

struct ChatResponse: Codable { let message: String? }

// 生成成片请求
struct FilmRequest: Codable {
    let project: String
    let character_image: String
    let character_desc: String
    let script: String
    let n_shots: Int
}

struct FilmShotResult: Codable, Identifiable, Hashable {
    let shot: String
    let keyframe: String?
    let video: String?
    var id: String { shot }
}
struct FilmResponse: Codable { let character: String?; let shots: [FilmShotResult] }
