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
    func backends() async throws -> [Backend] { (try await get("backends") as BackendsResponse).backends }
    func recipes() async throws -> [Recipe] { (try await get("recipes") as RecipesResponse).recipes }
    func shots(project: String) async throws -> [Shot] {
        (try await get("projects/\(project)/shots") as ShotsResponse).shots
    }
    func makeFilm(_ req: FilmRequest) async throws -> FilmResponse { try await post("films", req) }
    func selectTake(project: String, shot: String, take: String) async throws {
        struct Sel: Encodable { let take_id: String }
        struct Ok: Decodable { let ok: Bool }
        let _: Ok = try await post("projects/\(project)/shots/\(shot)/select", Sel(take_id: take))
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
