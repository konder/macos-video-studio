import Foundation

// 与 Orchestrator API 对应的数据模型(api-contract / mvp-tech-plan)。

struct Backend: Codable, Identifiable, Hashable {
    let name: String
    let kind: String?
    let url: String?
    var id: String { name }
}

struct Recipe: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let stage: String?
}

struct Take: Codable, Identifiable, Hashable {
    let id: String
    let video: String?
}

struct Shot: Codable, Identifiable, Hashable {
    let id: String
    let script: String?
    let scene_prompt: String?
    let motion_prompt: String?
    let keyframe: String?
    let selected_take: String?
    let takes: [Take]?
}

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
