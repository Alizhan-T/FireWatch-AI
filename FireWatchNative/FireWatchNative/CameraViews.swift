import SwiftUI
import AVKit

struct CameraLibraryView: View {
    @ObservedObject var api: API
    @State private var showingAdd = false
    @State private var candidates: [CameraCandidate] = []
    @State private var candidateLoading = false
    @State private var candidateError: String?
    @State private var candidateProgressID: String?
    @State private var candidateResults: [String: String] = [:]

    private func loadCandidates() async {
        candidateLoading = true
        do {
            candidates = try await api.fetchCameraCandidates()
            candidateError = nil
        } catch {
            candidateError = error.localizedDescription
        }
        candidateLoading = false
    }

    private func addAndCheck(_ candidate: CameraCandidate) {
        guard !api.cameras.contains(where: { $0.url == candidate.url }) else { return }
        candidateProgressID = candidate.id
        Task {
            do {
                let camera = try await api.addCamera(
                    name: candidate.name,
                    streamURL: candidate.url,
                    lat: candidate.lat,
                    lon: candidate.lon
                )
                let checked = try await api.checkCamera(camera)
                candidateResults[candidate.id] = checked.status == "online"
                    ? "Поток доступен — камера добавлена."
                    : "Камера добавлена, но поток не отвечает: \(checked.last_error ?? "причина не указана")."
            } catch {
                candidateResults[candidate.id] = error.localizedDescription
            }
            candidateProgressID = nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Подключайте только собственные камеры или публичные потоки, доступ к которым разрешён оператором. RTSP проверяется на сервере через FFmpeg; iPhone воспроизводит HLS.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://pocketworld.org/ru/webcams/country/kz")!) {
                        Label("Каталог открытых веб-камер Казахстана", systemImage: "globe.europe.africa")
                    }
                    Text("Каталог содержит публичные ссылки и метаданные, но не гарантирует, что каждый поток доступен сейчас или разрешён для автоматического AI-анализа.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Открытые камеры Казахстана") {
                    Text("Это кандидаты из публичного каталога Актау, а не подтверждённые рабочие потоки. При добавлении FireWatch сразу проверит URL через FFmpeg. Это городские и прибрежные камеры, не специализированные лесные посты.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if candidateLoading {
                        ProgressView("Загружаем каталог…")
                    }
                    if let candidateError {
                        Text(candidateError).font(.footnote).foregroundStyle(.red)
                    }
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(candidate.name).font(.subheadline.bold())
                            Text("HLS · \(candidate.lat), \(candidate.lon)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(candidate.verification_note)
                                .font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                if let sourceURL = URL(string: candidate.source_url) {
                                    Link("Оператор", destination: sourceURL)
                                }
                                if let catalogURL = URL(string: candidate.catalog_url) {
                                    Link("Каталог", destination: catalogURL)
                                }
                                Spacer()
                                if api.cameras.contains(where: { $0.url == candidate.url }) {
                                    Label("Добавлена", systemImage: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(.green)
                                } else if candidateProgressID == candidate.id {
                                    ProgressView()
                                } else {
                                    Button("Добавить и проверить") {
                                        addAndCheck(candidate)
                                    }
                                    .font(.caption.bold())
                                }
                            }
                            if let result = candidateResults[candidate.id] {
                                Text(result).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    if !candidateLoading && candidates.isEmpty && candidateError == nil {
                        Text("Публичные кандидаты не найдены.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if api.cameras.isEmpty {
                    Section {
                        ContentUnavailableView("Камеры не добавлены", systemImage: "video.slash",
                            description: Text("Добавьте разрешённый HLS/RTSP-поток или выберите публичный кандидат выше."))
                            .frame(minHeight: 100)
                    }
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
                                Text(camera.status == "online" ? "Онлайн при последней проверке" : camera.status == "offline" ? "Недоступна при последней проверке" : "Ещё не проверена")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            .navigationTitle("Камеры")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) { AddCameraView(api: api) }
            .task { await loadCandidates() }
            .refreshable {
                await api.refresh()
                await loadCandidates()
            }
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
                    Text("Добавление не подтверждает работоспособность потока. После сохранения проверьте его через FFmpeg. Для RTSP нужен запущенный FFmpeg на сервере.")
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
                              let parsedURL = URL(string: url),
                              let scheme = parsedURL.scheme?.lowercased(),
                              ["http", "https", "rtsp", "rtsps"].contains(scheme),
                              parsedURL.host != nil,
                              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            error = "Проверьте название, полный URL и координаты."
                            return
                        }
                        saving = true
                        Task {
                            do {
                                _ = try await api.addCamera(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                        streamURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                                        lat: latitude, lon: longitude)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}

private struct CameraDetailView: View {
    @ObservedObject var api: API
    let camera: Camera
    @State private var checking = false
    @State private var analyzing = false
    @State private var error: String?
    @State private var player: AVPlayer?
    @State private var analysis: DetectionSummary?
    @Environment(\.dismiss) private var dismiss

    private var currentCamera: Camera {
        api.cameras.first(where: { $0.id == camera.id }) ?? camera
    }

    private var isHLS: Bool {
        guard let url = URL(string: currentCamera.url),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path.lowercased().hasSuffix(".m3u8") == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isHLS, let player {
                    VideoPlayer(player: player)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("Прямой HLS-поток оператора. Доступность и задержка зависят от источника.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Встроенное видео недоступно", systemImage: "video.slash",
                        description: Text("RTSP можно проверить и анализировать на сервере. Для просмотра на iPhone нужен HLS-поток."))
                }

                if let snapshot = currentCamera.snapshot_url {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Последний полученный кадр").font(.headline)
                        ProtectedMediaImage(api: api, path: snapshot)
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                LabeledContent("Статус", value: currentCamera.status ?? "Не проверена")
                LabeledContent("Координаты", value: "\(currentCamera.lat), \(currentCamera.lon)")
                if let checked = currentCamera.last_checked_at {
                    LabeledContent("Последняя проверка", value: checked)
                }
                if let streamError = currentCamera.last_error, !streamError.isEmpty {
                    Text(streamError).font(.footnote).foregroundStyle(.orange)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }

                if let analysis {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Результат анализа кадра").font(.headline)
                        Text("Класс: \(analysis.classification)")
                        Text("Уверенность модели: \(Int(analysis.confidence * 100))%")
                        Text("Режим: \(analysis.mode)")
                        Text(analysis.disclaimer).font(.caption).foregroundStyle(.secondary)
                        if analysis.mode != "real_model" {
                            Text("DEMO: эвристика не является подтверждённой AI-детекцией.")
                                .font(.caption.bold()).foregroundStyle(.orange)
                        }
                        if let incidentID = analysis.incident_id {
                            Text("Создано событие: \(incidentID)").font(.caption)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    analyzing = true
                    Task {
                        do {
                            analysis = try await api.analyzeCamera(camera)
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                        analyzing = false
                    }
                } label: {
                    Label(analyzing ? "Анализируем кадр..." : "Анализировать кадр с помощью AI", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(analyzing || checking)

                Button {
                    checking = true
                    Task {
                        do {
                            _ = try await api.checkCamera(camera)
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                        checking = false
                    }
                } label: {
                    Label(checking ? "Проверяем..." : "Проверить поток через FFmpeg", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(checking || analyzing)

                if let url = URL(string: currentCamera.url),
                   ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link("Открыть страницу источника", destination: url)
                }

                Button("Удалить камеру", role: .destructive) {
                    Task {
                        do {
                            try await api.deleteCamera(camera)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(camera.name)
        .onAppear {
            if isHLS, let url = URL(string: currentCamera.url) {
                let streamPlayer = AVPlayer(url: url)
                player = streamPlayer
                streamPlayer.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
