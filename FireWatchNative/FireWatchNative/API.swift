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
