import Foundation
import Combine

/// Manifest probing is separate from playback: a valid HLS playlist is not
/// evidence that video segments arrive or that a camera stays online.
enum KazakhstanCameraReachability: Equatable {
    case unchecked
    case checking
    case playlistAvailable
    case unavailable
}

enum HLSManifestProbe {
    static func looksLikePlaylist(_ data: Data) -> Bool {
        // Reject HTML error pages and expired tokens that return HTTP 200.
        guard data.count <= 250_000 else { return false }
        let start = String(decoding: data.prefix(256), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        return start.hasPrefix("#EXTM3U")
    }

    static func check(url: String) async -> KazakhstanCameraReachability {
        guard let endpoint = URL(string: url), endpoint.scheme?.lowercased() == "https",
              endpoint.path.lowercased().hasSuffix(".m3u8"),
              endpoint.host != nil else {
            return .unavailable
        }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/vnd.apple.mpegurl, application/x-mpegURL, */*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  looksLikePlaylist(data) else {
                return .unavailable
            }
            return .playlistAvailable
        } catch {
            return .unavailable
        }
    }
}

@MainActor
final class KazakhstanCameraAvailability: ObservableObject {
    @Published private(set) var statuses: [String: KazakhstanCameraReachability] = [:]
    @Published private var pending: Set<String> = []
    private var revision = 0
    var checking: Bool { !pending.isEmpty }
    @Published private(set) var lastCheckedAt: Date?

    func status(for id: String) -> KazakhstanCameraReachability {
        pending.contains(id) ? .checking : (statuses[id] ?? .unchecked)
    }

    func refresh(
        _ candidates: [CameraCandidate],
        probe: @escaping @Sendable (String) async -> KazakhstanCameraReachability = {
            await HLSManifestProbe.check(url: $0)
        }
    ) async {
        guard !Task.isCancelled else { return }
        revision += 1
        let currentRevision = revision
        pending = Set(candidates.map(\.id))
        defer {
            if revision == currentRevision { pending.removeAll() }
        }

        // Limit to 3 requests in parallel; do not hammer third-party operators.
        for offset in stride(from: 0, to: candidates.count, by: 3) {
            if Task.isCancelled || revision != currentRevision { return }
            let batch = Array(candidates[offset..<min(offset + 3, candidates.count)])
            await withTaskGroup(of: (String, KazakhstanCameraReachability).self) { group in
                for camera in batch {
                    group.addTask {
                        (camera.id, await probe(camera.url))
                    }
                }
                for await (id, status) in group {
                    guard !Task.isCancelled, revision == currentRevision else { continue }
                    statuses[id] = status
                    pending.remove(id)
                }
            }
        }
        if !Task.isCancelled && revision == currentRevision && !candidates.isEmpty {
            lastCheckedAt = Date()
        }
    }
}
