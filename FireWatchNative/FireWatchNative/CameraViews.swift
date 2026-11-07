import SwiftUI
import AVKit

struct CameraLibraryView: View {
    @ObservedObject var api: API
    @State private var showingAdd = false
    @State private var busyID: String?
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Подключайте только собственные камеры или публичные потоки с разрешённым доступом. RTSP проверяется на сервере через FFmpeg; iPhone напрямую воспроизводит HLS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(api.cameras) { camera in
                    NavigationLink {
                        CameraDetailView(api: api, camera: camera)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "video.fill")
                                .foregroundStyle(camera.status == "online" ? .green : camera.status == "offline" ? .red : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(camera.name).font(.headline)
                                Text(camera.status == "online" ? "Последняя проверка: онлайн" : camera.status == "offline" ? "Последняя проверка: недоступна" : "Ещё не проверена")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let feedback { Text(feedback).font(.footnote).foregroundStyle(.orange) }
            }
            .overlay { if api.cameras.isEmpty { ContentUnavailableView("Камеры не добавлены", systemImage: "video.slash", description: Text("Добавьте разрешённую HLS/RTSP-камеру")) } }
            .navigationTitle("Камеры")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showingAdd) { AddCameraView(api: api) }
            .refreshable { await api.refresh() }
        }
    }
}

private struct AddCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var api: API
    @State private var name = ""
    @State private var url = ""
    @State private var lat = "51.1694"
    @State private var lon = "71.4491"
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Источник") {
                    TextField("Название камеры", text: $name)
                    TextField("https://.../index.m3u8 или rtsp://...", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                Section("Местоположение") {
                    TextField("Широта", text: $lat).keyboardType(.numbersAndPunctuation)
                    TextField("Долгота", text: $lon).keyboardType(.numbersAndPunctuation)
                }
                Section {
                    Text("Добавление не подтверждает работоспособность потока. После сохранения нажмите «Проверить поток». Для RTSP нужен запущенный FFmpeg на сервере.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Новая камера")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Сохранение..." : "Добавить") {
                        guard let latitude = Double(lat.replacingOccurrences(of: ",", with: ".")),
                              let longitude = Double(lon.replacingOccurrences(of: ",", with: ".")),
                              (-90...90).contains(latitude), (-180...180).contains(longitude),
                              let scheme = URL(string: url)?.scheme?.lowercased(),
                              ["http", "https", "rtsp", "rtsps"].contains(scheme),
                              !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                            error = "Проверьте название, URL и координаты"; return
                        }
                        saving = true
                        Task {
                            do { try await api.addCamera(name: name, streamURL: url, lat: latitude, lon: longitude); dismiss() }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(saving)
                }
            }
        }
    }
}

private struct CameraDetailView: View {
    @ObservedObject var api: API
    let camera: Camera
    @State private var checking = false
    @State private var error: String?
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    private var isHLS: Bool {
        guard let url = URL(string: camera.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return url.path.lowercased().hasSuffix(".m3u8")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isHLS, let player {
                    VideoPlayer(player: player).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("Прямой эфир HLS. Воспроизведение зависит от доступности потока и правил его оператора.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Встроенное видео недоступно", systemImage: "video.slash",
                        description: Text("Для RTSP используйте серверную проверку кадра или предоставьте HLS-ссылку."))
                }
                LabeledContent("Статус", value: camera.status ?? "unchecked")
                LabeledContent("Координаты", value: "\(camera.lat), \(camera.lon)")
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Button {
                    checking = true
                    Task {
                        do { try await api.checkCamera(camera) }
                        catch { self.error = error.localizedDescription }
                        checking = false
                    }
                } label: { Label(checking ? "Проверяем..." : "Проверить поток через FFmpeg", systemImage: "checkmark.circle") }
                    .buttonStyle(.borderedProminent).disabled(checking)
                if let url = URL(string: camera.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link("Открыть у оператора", destination: url)
                }
                Button("Удалить камеру", role: .destructive) {
                    Task {
                        do { try await api.deleteCamera(camera); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(camera.name)
        .onAppear {
            if isHLS, let url = URL(string: camera.url) {
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            }
        }
        .onDisappear { player?.pause(); player = nil }
    }
}
