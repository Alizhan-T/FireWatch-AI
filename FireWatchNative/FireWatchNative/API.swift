import Foundation
import Combine

enum FireWatchAPIError: LocalizedError {
    case serverNotConfigured
    case invalidServerURL
    case useMacAddress
    case http(Int, String)
    case invalidResponse
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "Сначала укажите адрес FastAPI-сервера в Настройках."
        case .invalidServerURL:
            return "Неверный адрес сервера. Пример: http://192.168.1.20:8000"
        case .useMacAddress:
            return "На физическом iPhone адрес localhost указывает на сам телефон. Укажите IP-адрес Mac в той же Wi-Fi сети."
        case let .http(code, message):
            return "Сервер ответил HTTP \(code): \(message)"
        case .invalidResponse:
            return "Сервер вернул некорректный ответ."
        case let .invalidData(message):
            return "Не удалось прочитать ответ сервера: \(message)"
        }
    }
}

@MainActor
final class API: ObservableObject {
    @Published var baseURL = UserDefaults.standard.string(forKey: "firewatch.server") ?? ""\n    @Published var apiKey = KeychainStore.load("apiKey") ?? ""
    @Published private(set) var incidents: [Incident] = []
    @Published private(set) var cameras: [Camera] = []
    @Published private(set) var stats: Stats?
    @Published private(set) var health: ServerHealth?
    @Published private(set) var isConnected = false
    @Published private(set) var loading = false
    @Published private(set) var lastSuccessfulSync: Date?
    @Published var error: String?

    func saveURL() throws {
        let cleaned = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty else { throw FireWatchAPIError.serverNotConfigured }
        guard let url = URL(string: cleaned), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else {
            throw FireWatchAPIError.invalidServerURL
        }
        baseURL = cleaned
        UserDefaults.standard.set(cleaned, forKey: "firewatch.server")\n        KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "apiKey")
    }

    func absoluteURL(for path: String?) -> URL? {
        guard let path, !path.isEmpty, let base = try? serverBaseURL() else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    private func serverBaseURL() throws -> URL {
        let cleaned = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw FireWatchAPIError.serverNotConfigured }
        guard let url = URL(string: cleaned), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host else {
            throw FireWatchAPIError.invalidServerURL
        }
        if ["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) {
            throw FireWatchAPIError.useMacAddress
        }
        return url
    }

    private func endpoint(_ path: String) throws -> URL {
        let base = try serverBaseURL()
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw FireWatchAPIError.invalidServerURL
        }
        return url
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        timeout: TimeInterval = 15,
        as type: T.Type = T.self
    ) async throws -> T {
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")\n        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FireWatchAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let serverMessage: String
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = object["detail"] {
                serverMessage = String(describing: detail)
            } else {
                serverMessage = String(data: data.prefix(600), encoding: .utf8) ?? "Неизвестная ошибка"
            }
            throw FireWatchAPIError.http(http.statusCode, serverMessage)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FireWatchAPIError.invalidData(error.localizedDescription)
        }
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let h: ServerHealth = request("/health")
            async let i: [Incident] = request("/incidents?limit=100")
            async let c: [Camera] = request("/cameras")
            async let s: Stats = request("/stats")
            let (serverHealth, serverIncidents, serverCameras, serverStats) = try await (h, i, c, s)
            health = serverHealth
            incidents = serverIncidents
            cameras = serverCameras
            stats = serverStats
            isConnected = serverHealth.status == "ok" && serverHealth.database == true
            lastSuccessfulSync = Date()
            error = isConnected ? nil : "Сервер доступен, но база данных или часть сервисов работает с ошибкой."
        } catch {
            isConnected = false
            self.error = error.localizedDescription
        }
    }

    func addCamera(name: String, streamURL: String, lat: Double, lon: Double) async throws {
        struct Payload: Encodable { let name: String; let url: String; let lat: Double; let lon: Double }
        let payload = Payload(name: name, url: streamURL, lat: lat, lon: lon)
        let _: Camera = try await request("/cameras", method: "POST",
            body: JSONEncoder().encode(payload), contentType: "application/json")
        await refresh()
    }

    func checkCamera(_ camera: Camera) async throws {
        let _: Camera = try await request("/cameras/\(camera.id)/check", method: "POST")
        await refresh()
    }

    func deleteCamera(_ camera: Camera) async throws {
        struct Result: Decodable { let ok: Bool }
        let _: Result = try await request("/cameras/\(camera.id)", method: "DELETE")
        await refresh()
    }

    func analyzeCamera(_ camera: Camera) async throws -> DetectionSummary {
        let result: DetectionSummary = try await request("/cameras/\(camera.id)/analyze", method: "POST", timeout: 150)
        await refresh()
        return result
    }

    func updateIncident(_ incident: Incident, status: String) async throws {
        struct Payload: Encodable { let status: String }
        let _: Incident = try await request("/incidents/\(incident.id)/status", method: "PATCH",
            body: JSONEncoder().encode(Payload(status: status)), contentType: "application/json")
        await refresh()
    }

    func deleteIncident(_ incident: Incident) async throws {
        struct Result: Decodable { let ok: Bool }
        let _: Result = try await request("/incidents/\(incident.id)", method: "DELETE")
        await refresh()
    }

    func registerDevice(token: String) async throws {
        struct Payload: Encodable { let token: String; let name: String; let platform: String }
        let payload = Payload(token: token, name: "iPhone", platform: "ios")
        let _: DeviceRegistration = try await request("/register_device", method: "POST",
            body: JSONEncoder().encode(payload), contentType: "application/json")
    }

    func detect(jpeg: Data, saveIncident: Bool = false) async throws -> DetectionSummary {
        let boundary = "FireWatch-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"save_incident\"\r\n\r\n\(saveIncident ? "true" : "false")\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return try await request("/detect", method: "POST", body: body,
            contentType: "multipart/form-data; boundary=\(boundary)", timeout: 120)
    }
}
