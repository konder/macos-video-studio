import Foundation

/// Orchestrator REST 客户端(async/await,URLSession)。
struct APIError: LocalizedError { let msg: String; var errorDescription: String? { msg } }

struct API {
    let baseString: String

    init(base: String) {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "http://" + s }   // 容错:没写 scheme 自动补
        while s.hasSuffix("/") { s.removeLast() }
        self.baseString = s
    }

    private func url(_ path: String) throws -> URL {
        guard let u = URL(string: baseString + "/" + path) else {
            throw APIError(msg: "无效地址: \(baseString)")
        }
        return u
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: try url(path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, _ body: B) async throws -> T {
        var req = URLRequest(url: try url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func health() async throws -> HealthResponse { try await get("healthz") }
    func listProjects() async throws -> [String] { (try await get("projects") as ProjectsList).projects }
    func createProject(_ name: String) async throws {
        struct In: Encodable { let name: String }
        struct Ok: Decodable { let ok: Bool? }
        let _: Ok = try await post("projects", In(name: name))
    }
    func backends() async throws -> [Backend] { (try await get("backends") as BackendsResponse).backends }
    func recipes() async throws -> [Recipe] { (try await get("recipes") as RecipesResponse).recipes }
    func shots(project: String) async throws -> [Shot] {
        (try await get("projects/\(project)/shots") as ShotsResponse).shots
    }
    func project(_ name: String) async throws -> ProjectDetail { try await get("projects/\(name)") }

    /// 技术层:为镜头某任务实例化 Graph IR(落库 shot.graph)并返回原始图。
    func buildGraph(project: String, shot: String, task: String = "keyframe_edit") async throws -> [String: Any] {
        var req = URLRequest(url: try url("projects/\(project)/shots/\(shot)/graph/build?task=\(task)"))
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return obj["graph"] as? [String: Any] ?? [:]
    }
    func makeFilm(_ req: FilmRequest) async throws -> FilmResponse { try await post("films", req) }

    /// 提交一段 ops 作为一个变更(人/Agent 同构,进统一历史)。返回新 seq。
    /// ops 取值异构,用 JSONSerialization 编码。
    @discardableResult
    func submitChange(project: String, ops: [[String: Any]], author: String = "human",
                      rationale: String = "") async throws -> Int {
        var req = URLRequest(url: try url("projects/\(project)/ops"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["ops": ops, "author": author, "rationale": rationale]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        struct R: Decodable { let ok: Bool?; let seq: Int? }
        return (try JSONDecoder().decode(R.self, from: data)).seq ?? 0
    }
    func chat(message: String, project: String) async throws -> String {
        struct In: Encodable { let message: String; let project: String }
        let r: ChatResponse = try await post("chat", In(message: message, project: project))
        return r.message ?? ""
    }
    func export(project: String) async throws -> [String: String] {
        struct Empty: Encodable {}
        struct R: Decodable { let fcpxml: String?; let clips_dir: String? }
        let r: R = try await post("projects/\(project)/export", Empty())
        return ["fcpxml": r.fcpxml ?? "", "clips_dir": r.clips_dir ?? ""]
    }
}
