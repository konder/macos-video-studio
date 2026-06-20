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
    /// 按预设流程生成资产(文字 / 文字+参考图),返回 job_id。
    func generateAsset(project: String, atype: String, name: String, prompt: String, refPath: String?) async throws -> String {
        struct In: Encodable { let atype: String; let name: String; let prompt: String; let ref_path: String? }
        struct R: Decodable { let job_id: String? }
        let r: R = try await post("projects/\(project)/assets/generate", In(atype: atype, name: name, prompt: prompt, ref_path: refPath))
        return r.job_id ?? ""
    }

    /// 上传参考图(原始字节),返回项目内相对路径。
    func uploadImage(project: String, data: Data, filename: String) async throws -> String {
        let fn = filename.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "asset.png"
        var req = URLRequest(url: try url("projects/\(project)/upload?filename=\(fn)"))
        req.httpMethod = "POST"
        req.httpBody = data
        let (d, _) = try await URLSession.shared.data(for: req)
        struct R: Decodable { let path: String? }
        return (try JSONDecoder().decode(R.self, from: d)).path ?? ""
    }

    /// 镜头级图 op(set_param/delete_node/...)→ 校验后入历史。
    @discardableResult
    func shotOps(project: String, shot: String, ops: [[String: Any]], rationale: String) async throws -> Int {
        var req = URLRequest(url: try url("projects/\(project)/shots/\(shot)/ops"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["project": project, "shot_id": shot, "ops": ops,
                                   "author": "human", "rationale": rationale, "check": false]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        struct R: Decodable { let ok: Bool?; let seq: Int? }
        return (try JSONDecoder().decode(R.self, from: data)).seq ?? 0
    }
    func undo(project: String) async throws {
        struct E: Encodable {}
        struct R: Decodable { let ok: Bool? }
        let _: R = try await post("projects/\(project)/undo", E())
    }
    func lock(project: String, shot: String, actor: String) async throws {
        struct In: Encodable { let actor: String }
        struct R: Decodable { let ok: Bool? }
        let _: R = try await post("projects/\(project)/shots/\(shot)/lock", In(actor: actor))
    }
    func unlock(project: String, shot: String) async throws {
        var req = URLRequest(url: try url("projects/\(project)/shots/\(shot)/lock"))
        req.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: req)
    }
    func locks(project: String) async throws -> [String: LockInfo] {
        (try await get("projects/\(project)/locks") as LocksResponse).locks
    }

    func buildGraph(project: String, shot: String, task: String = "keyframe_edit") async throws -> [String: Any] {
        var req = URLRequest(url: try url("projects/\(project)/shots/\(shot)/graph/build?task=\(task)"))
        req.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return obj["graph"] as? [String: Any] ?? [:]
    }
    /// 启动成片异步作业,返回 job_id。
    func startFilm(_ req: FilmRequest) async throws -> String {
        struct R: Decodable { let job_id: String? }
        let r: R = try await post("films", req)
        return r.job_id ?? ""
    }
    func job(_ id: String) async throws -> Job { try await get("jobs/\(id)") }

    func estimate(task: String, backend: String, duration: Int = 5) async throws -> Estimate {
        struct In: Encodable { let task: String; let backend: String; let duration: Int }
        return try await post("graphs/estimate", In(task: task, backend: backend, duration: duration))
    }
    /// 生成镜头视频(local/cloud);云未确认时返回 needs_confirm+estimate(费用闸)。
    func generate(project: String, shot: String, backend: String, confirm: Bool) async throws -> GenerateResult {
        struct In: Encodable { let backend: String; let confirm: Bool }
        return try await post("projects/\(project)/shots/\(shot)/generate", In(backend: backend, confirm: confirm))
    }

    /// 构建 SSE 对话请求(调用方用 URLSession.bytes 读流)。
    func chatRequest(message: String, project: String) throws -> URLRequest {
        var req = URLRequest(url: try url("chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct In: Encodable { let message: String; let project: String }
        req.httpBody = try JSONEncoder().encode(In(message: message, project: project))
        return req
    }

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
    func export(project: String) async throws -> [String: String] {
        struct Empty: Encodable {}
        struct R: Decodable { let fcpxml: String?; let clips_dir: String? }
        let r: R = try await post("projects/\(project)/export", Empty())
        return ["fcpxml": r.fcpxml ?? "", "clips_dir": r.clips_dir ?? ""]
    }
}
