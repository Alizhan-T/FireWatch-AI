import Foundation
import SwiftUI
import AVKit

/// Personal camera bookmarks stored locally on this iPhone, without FireWatch API.
struct LocalHLSCamera: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var streamURL: String
}

enum LocalHLSCameraError: LocalizedError {
    case invalid
    case duplicate

    var errorDescription: String? {
        switch self {
        case .invalid:
            return "Укажите название и прямую HTTP(S) ссылку на HLS-поток (.m3u8)."
        case .duplicate:
            return "Такая камера уже сохранена на этом iPhone."
        }
    }
}

@MainActor
final class LocalHLSCameraStore: ObservableObject {
    @Published private(set) var cameras: [LocalHLSCamera] = []
    private let storageKey = "firewatch.localHLSCameras.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([LocalHLSCamera].self, from: data) {
            cameras = saved
        }
    }

    func add(name: String, streamURL: String) throws {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let url = URL(string: address),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.path.lowercased().hasSuffix(".m3u8") else {
            throw LocalHLSCameraError.invalid
        }
        guard !cameras.contains(where: { $0.streamURL == address }) else {
            throw LocalHLSCameraError.duplicate
        }
        cameras.append(LocalHLSCamera(id: UUID(), name: title, streamURL: address))
        persist()
    }

    func remove(_ camera: LocalHLSCamera) {
        cameras.removeAll { $0.id == camera.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cameras) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

/// AVPlayer reads the remote HLS stream directly: no FireWatch backend involved.
struct DirectHLSPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var itemObserver: NSKeyValueObservation?
    @State private var playbackStatus = "Подключение к видеопотоку…"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ProgressView("Подключение…")
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
            }
            Text(playbackStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Доступность потока определяется в момент открытия. Статус плеера не гарантирует круглосуточную работу камеры.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: startPlayback)
        .onDisappear {
            itemObserver?.invalidate()
            itemObserver = nil
            player?.pause()
            player = nil
        }
    }

    private func startPlayback() {
        guard player == nil else { return }
        let item = AVPlayerItem(url: url)
        itemObserver = item.observe(\.status, options: [.initial, .new]) { observed, _ in
            let message: String
            switch observed.status {
            case .readyToPlay:
                message = "Поток открыт плеером. Воспроизведение зависит от соединения."
            case .failed:
                message = "Не удалось открыть поток. Проверьте источник и доступ к нему."
            default:
                message = "Подключение к видеопотоку…"
            }
            Task { @MainActor in
                playbackStatus = message
            }
        }
        let streamPlayer = AVPlayer(playerItem: item)
        player = streamPlayer
        streamPlayer.play()
    }
}

struct LocalHLSCameraDetailView: View {
    let camera: LocalHLSCamera

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = URL(string: camera.streamURL) {
                    DirectHLSPlayer(url: url)
                    Link("Открыть прямую ссылку HLS", destination: url)
                }
                Text(camera.name).font(.title3.bold())
                Label("Прямой просмотр без сервера FireWatch", systemImage: "iphone")
                    .foregroundStyle(.secondary)
                Text("Этот поток хранится в закладках на вашем iPhone. Нейросетевой анализ и автоматические тревоги без сервера пока не реализованы.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(camera.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddLocalHLSCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: LocalHLSCameraStore
    @State private var name = ""
    @State private var streamURL = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Новая HLS-камера") {
                    TextField("Название", text: $name)
                    TextField("https://…/index.m3u8", text: $streamURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Text("Сохраняется только на iPhone. Поддерживается прямой HLS (.m3u8). RTSP без конвертации не воспроизводится AVPlayer. Используйте лишь потоки с разрешённым просмотром.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Добавить камеру")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        do {
                            try store.add(name: name, streamURL: streamURL)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}
