import Foundation

@MainActor
final class API: ObservableObject {
    @Published var baseURL = UserDefaults.standard.string(forKey: "firewatch.server") ?? "http://127.0.0.1:8000"
    @Published var incidents: [Incident] = []
    @Published var cameras: [Camera] = []
    @Published var stats: Stats?
    @Published var error: String?
    @Published var loading = false

    func saveURL() { UserDefaults.standard.set(baseURL, forKey: "firewatch.server") }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let base = URL(string: baseURL), let url = URL(string: path, relativeTo: base) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }


    private func send<T: Decodable>(_ path: String, method: String, body: Data? = nil) async throws -> T {
        guard let base = URL(string: baseURL), let url = URL(string: path, relativeTo: base) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func addCamera(name: String, streamURL: String, lat: Double, lon: Double) async throws {
        struct Payload: Encodable { let name: String; let url: String; let lat: Double; let lon: Double }
        let payload = Payload(name: name, url: streamURL, lat: lat, lon: lon)
        let _: Camera = try await send("/cameras", method: "POST", body: JSONEncoder().encode(payload))
        await refresh()
    }

    func checkCamera(_ camera: Camera) async throws {
        let _: Camera = try await send("/cameras/\\(camera.id)/check", method: "POST")
        await refresh()
    }

    func deleteCamera(_ camera: Camera) async throws {
        struct Result: Decodable { let ok: Bool }
        let _: Result = try await send("/cameras/\\(camera.id)", method: "DELETE")
        await refresh()
    }


    func detect(jpeg: Data) async throws -> DetectionSummary {
        guard let base = URL(string: baseURL), let url = URL(string: "/detect", relativeTo: base) else { throw URLError(.badURL) }
        let boundary = "FireWatch-\\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\\(boundary)\\r\\nContent-Disposition: form-data; name=\\"file\\"; filename=\\"image.jpg\\"\\r\\nContent-Type: image/jpeg\\r\\n\\r\\n".utf8))
        body.append(jpeg)
        body.append(Data("\\r\\n--\\(boundary)--\\r\\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("multipart/form-data; boundary=\\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(DetectionSummary.self, from: data)
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            async let i: [Incident] = get("/incidents")
            async let c: [Camera] = get("/cameras")
            async let s: Stats = get("/stats")
            let (inc, cam, st) = try await (i, c, s)
            incidents = inc; cameras = cam; stats = st; error = nil
        } catch {
            self.error = "Не удалось подключиться: \(error.localizedDescription). На iPhone укажи IP-адрес Mac, а не localhost."
        }
    }
}
