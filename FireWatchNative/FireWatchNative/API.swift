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
    @Published var baseURL = UserDefaults.standard.string(forKey: "firewatch.server") ?? ""
    @Published var apiKey = KeychainStore.load("apiKey") ?? ""
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
        UserDefaults.standard.set(cleaned, forKey: "firewatch.server")
        KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "apiKey")
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

    private func mediaRequest(_ path: String) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(path))
        request.timeoutInterval = 60
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }
        return request
    }

    func mediaData(for path: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: mediaRequest(path))
        guard let http = response as? HTTPURLResponse else { throw FireWatchAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw FireWatchAPIError.http(http.statusCode, "Не удалось загрузить файл доказательства.")
        }
        return data
    }

    func downloadMedia(for path: String) async throws -> URL {
        let request = try mediaRequest(path)
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw FireWatchAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw FireWatchAPIError.http(http.statusCode, "Не удалось загрузить видео.")
        }
        let ext = URL(string: path, relativeTo: try serverBaseURL())?.pathExtension
        let fileExtension = ext.flatMap { $0.isEmpty ? nil : $0 } ?? "mp4"
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("firewatch-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
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
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-Key") }

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

    private func upsertCamera(_ camera: Camera) {
        if let index = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[index] = camera
        } else {
            cameras.insert(camera, at: 0)
        }
    }

    private func upsertIncident(_ incident: Incident) {
        if let index = incidents.firstIndex(where: { $0.id == incident.id }) {
            incidents[index] = incident
        } else {
            incidents.insert(incident, at: 0)
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

    func setMonitoring(enabled: Bool) async throws -> MonitoringStatus {
        let route = enabled ? "/monitoring/start" : "/monitoring/stop"
        let result: MonitoringStatus = try await request(route, method: "POST", timeout: 30)
        await refresh()
        return result
    }

    func addCamera(name: String, streamURL: String, lat: Double, lon: Double) async throws -> Camera {
        struct Payload: Encodable { let name: String; let url: String; let lat: Double; let lon: Double }
        let payload = Payload(name: name, url: streamURL, lat: lat, lon: lon)
        let created: Camera = try await request("/cameras", method: "POST",
            body: JSONEncoder().encode(payload), contentType: "application/json")
        upsertCamera(created)
        await refresh()
        return cameras.first(where: { $0.id == created.id }) ?? created
    }

    func checkCamera(_ camera: Camera) async throws -> Camera {
        let checked: Camera = try await request("/cameras/\(camera.id)/check", method: "POST")
        upsertCamera(checked)
        await refresh()
        return cameras.first(where: { $0.id == camera.id }) ?? checked
    }

    func fetchCameraCandidates() async throws -> [CameraCandidate] {
        try await request("/camera-candidates")
    }

    func deleteCamera(_ camera: Camera) async throws {
        struct Result: Decodable { let ok: Bool }
        let _: Result = try await request("/cameras/\(camera.id)", method: "DELETE")
        cameras.removeAll { $0.id == camera.id }
        await refresh()
    }

    func analyzeCamera(_ camera: Camera) async throws -> DetectionSummary {
        let result: DetectionSummary = try await request("/cameras/\(camera.id)/analyze", method: "POST", timeout: 150)
        if let incidentID = result.incident_id, let incident = try? await fetchIncident(id: incidentID) {
            upsertIncident(incident)
        }
        await refresh()
        return result
    }

    func fetchIncident(id: String) async throws -> Incident {
        try await request("/incidents/\(id)")
    }

    func updateIncident(_ incident: Incident, status: String) async throws {
        struct Payload: Encodable { let status: String }
        let updated: Incident = try await request("/incidents/\(incident.id)/status", method: "PATCH",
            body: JSONEncoder().encode(Payload(status: status)), contentType: "application/json")
        upsertIncident(updated)
        await refresh()
    }

    func deleteIncident(_ incident: Incident) async throws {
        struct Result: Decodable { let ok: Bool }
        let _: Result = try await request("/incidents/\(incident.id)", method: "DELETE")
        incidents.removeAll { $0.id == incident.id }
        await refresh()
    }

    func registerDevice(token: String) async throws {
        struct Payload: Encodable { let token: String; let name: String; let platform: String }
        let payload = Payload(token: token, name: "iPhone", platform: "ios")
        let _: DeviceRegistration = try await request("/register_device", method: "POST",
            body: JSONEncoder().encode(payload), contentType: "application/json")
    }

    func detect(
        jpeg: Data,
        saveIncident: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil
    ) async throws -> DetectionSummary {
        let boundary = "FireWatch-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n".utf8))
        appendField("save_incident", saveIncident ? "true" : "false")
        if let latitude { appendField("lat", String(latitude)) }
        if let longitude { appendField("lon", String(longitude)) }
        if let locationName, !locationName.isEmpty {
            appendField("location_name", locationName)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        let result: DetectionSummary = try await request(
            "/detect", method: "POST", body: body,
            contentType: "multipart/form-data; boundary=\(boundary)", timeout: 120
        )
        if let incidentID = result.incident_id, let incident = try? await fetchIncident(id: incidentID) {
            upsertIncident(incident)
            await refresh()
        }
        return result
    }
}
