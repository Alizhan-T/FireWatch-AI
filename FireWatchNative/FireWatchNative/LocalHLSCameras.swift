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
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
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
            defaults.set(data, forKey: storageKey)
        }
    }
}

/// Direct AVPlayer playback. A small watchdog prevents endless loading on dead links.
/// AVPlayer can recover short buffering stalls on its own; terminal failures get
/// two bounded reconnect attempts, never an unlimited network/battery loop.
enum HLSPlaybackPhase {
    case idle
    case connecting
    case buffering
    case playing
    case reconnecting
    case failed
}

@MainActor
final class HLSPlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var phase: HLSPlaybackPhase = .idle
    @Published private(set) var message = "Готово к подключению"

    private var url: URL?
    private var session = UUID()
    private var attempts = 0
    private var itemStatusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var stalledObserver: NSObjectProtocol?
    private var watchdog: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    func start(_ url: URL) {
        guard self.url != url || player == nil else { return }
        self.url = url
        attempts = 0
        connect()
    }

    func retry() {
        guard url != nil else { return }
        attempts = 0
        connect()
    }

    func stop() {
        session = UUID() // Ignore callbacks from an old player after navigation.
        clearPlayback()
        url = nil
        attempts = 0
        phase = .idle
        message = "Воспроизведение остановлено"
    }

    private func clearPlayback() {
        watchdog?.cancel()
        watchdog = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        playerStatusObservation?.invalidate()
        playerStatusObservation = nil
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }
        stalledObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func connect() {
        clearPlayback()
        guard let url else { return }
        let token = UUID()
        session = token
        phase = .connecting
        message = "Подключение к видеопотоку…"

        let item = AVPlayerItem(url: url)
        let streamPlayer = AVPlayer(playerItem: item)
        streamPlayer.automaticallyWaitsToMinimizeStalling = true
        player = streamPlayer

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                if status == .failed {
                    self.recover(reason: "Камера отклонила подключение или поток недоступен", token: token)
                }
            }
        }
        playerStatusObservation = streamPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
            let status = observed.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                switch status {
                case .playing:
                    self.phase = .playing
                    self.message = "Видео воспроизводится"
                    self.attempts = 0
                    self.watchdog?.cancel()
                    self.watchdog = nil
                case .waitingToPlayAtSpecifiedRate:
                    if self.phase == .playing {
                        self.phase = .buffering
                        self.message = "Связь прервалась — ожидаем возобновления…"
                        self.startWatchdog(token)
                    }
                default:
                    break
                }
            }
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.session == token else { return }
                self.phase = .buffering
                self.message = "Поток завис — пробуем восстановить воспроизведение…"
                self.startWatchdog(token)
            }
        }
        streamPlayer.play()
        startWatchdog(token)
    }

    private func startWatchdog(_ token: UUID) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 20_000_000_000)
            } catch { return }
            guard let self, self.session == token, self.phase != .playing else { return }
            self.recover(reason: "Камера не передаёт видео в течение 20 секунд", token: token)
        }
    }

    private func recover(reason: String, token: UUID) {
        guard session == token, phase != .reconnecting, phase != .failed else { return }
        guard attempts < 2 else {
            clearPlayback()
            phase = .failed
            message = "\(reason). Проверьте интернет или ссылку на поток."
            return
        }
        attempts += 1
        let currentAttempt = attempts
        phase = .reconnecting
        message = "Восстанавливаем поток (\(currentAttempt)/2)…"
        watchdog?.cancel()
        watchdog = nil
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(currentAttempt * 2) * 1_000_000_000)
            } catch { return }
            guard let self, self.session == token, self.phase == .reconnecting else { return }
            self.connect()
        }
    }
}

/// AVPlayer opens HLS directly without any FireWatch API or proxy.
struct DirectHLSPlayer: View {
    let url: URL
    /// Compact embeds show *only* the 250-point video surface, not captions.
    /// The old DEMO effect mistakenly anchored to the captions' bottom edge.
    var compact: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = HLSPlaybackController()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                if let player = playback.player {
                    VideoPlayer(player: player)
                        .frame(height: 250)
                } else {
                    ContentUnavailableView(
                        playback.phase == .failed ? "Камера недоступна" : "Подключаем камеру",
                        systemImage: playback.phase == .failed ? "wifi.exclamationmark" : "video",
                        description: Text(playback.message)
                    )
                    .frame(height: 250)
                }
                if compact && playback.phase == .failed {
                    Button {
                        playback.retry()
                    } label: {
                        Label("Повторить соединение", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if !compact {
                if playback.phase != .failed {
                    Text(playback.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        playback.retry()
                    } label: {
                        Label("Повторить подключение", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("Соединение проверяется при открытии. Просмотр требует интернета; поток может быть отключён оператором.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if scenePhase == .active { playback.start(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { playback.start(url) }
            else { playback.stop() }
        }
        .onDisappear { playback.stop() }
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
