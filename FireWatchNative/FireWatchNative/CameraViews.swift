import SwiftUI
import AVKit

struct CameraLibraryView: View {
    @ObservedObject var api: API
    @StateObject private var localStore = LocalHLSCameraStore()
    @StateObject private var availability = KazakhstanCameraAvailability()
    @State private var showingLocalAdd = false
    @State private var showingServerAdd = false
    @State private var showUnverified = false

    private var accessible: [CameraCandidate] {
        PublicCameraCatalog.candidates.filter {
            availability.status(for: $0.id) == .playlistAvailable
        }
    }

    private var otherCandidates: [CameraCandidate] {
        PublicCameraCatalog.candidates.filter {
            availability.status(for: $0.id) != .playlistAvailable
        }
    }

    private func reachabilityDescription(_ candidate: CameraCandidate) -> String {
        switch availability.status(for: candidate.id) {
        case .playlistAvailable: "HLS-плейлист отвечает · нажмите для просмотра"
        case .checking: "Проверяется доступность…"
        case .unavailable: "Плейлист не отвечает · можно попробовать вручную"
        case .unchecked: "Ожидает проверки"
        }
    }

    private func cameraRow(_ candidate: CameraCandidate) -> some View {
        NavigationLink {
            PublicCameraDetailView(candidate: candidate)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .foregroundStyle(availability.status(for: candidate.id) == .playlistAvailable ? .green : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.name).font(.subheadline.bold())
                    Text(reachabilityDescription(candidate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(candidate.source_name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 5)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Казахстан · прямой просмотр") {
                    Text("Нажмите на камеру — видео откроется внутри FireWatch через AVPlayer. На другие сайты переходить не нужно. Используются только публично опубликованные HLS-ссылки камер Казахстана.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if availability.checking {
                            ProgressView()
                        }
                        Text(availability.checking ? "Проверяем HLS-плейлисты…" : "Проверка доступности по запросу")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Обновить") {
                            Task { await availability.refresh(PublicCameraCatalog.candidates) }
                        }
                        .disabled(availability.checking)
                    }
                    Text("Доступный HLS-плейлист ещё не гарантирует видеокадры или право на автоматический AI-анализ. Действительное воспроизведение проверяется во встроенном плеере.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("Ответившие HLS-камеры") {
                    ForEach(accessible) { camera in
                        cameraRow(camera)
                    }
                    if accessible.isEmpty {
                        if availability.checking {
                            ProgressView("Поиск доступных потоков Казахстана…")
                        } else {
                            Text("Сейчас нет подтверждённых ответов от HLS-плейлистов. Это не исключает временную сетевую ошибку — откройте ручную проверку ниже.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !otherCandidates.isEmpty {
                    Section {
                        DisclosureGroup("Остальные камеры Казахстана (\(otherCandidates.count))", isExpanded: $showUnverified) {
                            ForEach(otherCandidates) { camera in
                                cameraRow(camera)
                            }
                            Text("Это опубликованные ссылки, а не подтверждённые рабочие камеры. Все они по нажатию открываются внутри приложения.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Природные территории Казахстана") {
                    NavigationLink {
                        AkzhaiykEmbeddedCameraView()
                    } label: {
                        Label("Резерват «Акжайык» · видео внутри приложения", systemImage: "leaf")
                    }
                    Text("Опубликованная трансляция YouTube. Встроенное воспроизведение зависит от доступности записи/эфира и разрешения владельца на встраивание; текущий LIVE-статус не подтверждён.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section("Мои HLS-камеры · только iPhone") {
                    ForEach(localStore.cameras) { camera in
                        NavigationLink {
                            LocalHLSCameraDetailView(camera: camera)
                        } label: {
                            Label(camera.name, systemImage: "video.fill")
                        }
                    }
                    .onDelete { indices in
                        for index in indices.sorted(by: >) {
                            localStore.remove(localStore.cameras[index])
                        }
                    }
                    Button {
                        showingLocalAdd = true
                    } label: {
                        Label("Добавить прямой HLS-поток", systemImage: "plus.circle")
                    }
                }
                if api.isConnected {
                    Section("Камеры дополнительного AI-сервера") {
                        ForEach(api.cameras) { camera in
                            NavigationLink {
                                CameraDetailView(api: api, camera: camera)
                            } label: {
                                Label(camera.name, systemImage: "video")
                            }
                        }
                        Button {
                            showingServerAdd = true
                        } label: {
                            Label("Добавить камеру для AI", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("Камеры Казахстана")
            .sheet(isPresented: $showingLocalAdd) {
                AddLocalHLSCameraView(store: localStore)
            }
            .sheet(isPresented: $showingServerAdd) {
                AddCameraView(api: api)
            }
            .task {
                await availability.refresh(PublicCameraCatalog.candidates)
            }
            .refreshable {
                await availability.refresh(PublicCameraCatalog.candidates)
                if api.isConnected { await api.refresh() }
            }
        }
    }
}

struct PublicCameraDetailView: View {
    let candidate: CameraCandidate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = URL(string: candidate.url) {
                    DirectHLSPlayer(url: url)
                } else {
                    ContentUnavailableView("Ссылка на поток недействительна",
                        systemImage: "video.slash",
                        description: Text("Источник сейчас недоступен."))
                        .frame(height: 250)
                }
                Text(candidate.name).font(.title3.bold())
                Label("Прямой HLS · просмотр внутри FireWatch", systemImage: "play.rectangle")
                    .font(.subheadline)
                Text("Источник: \(candidate.source_name)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("Координаты каталога", value: "\(candidate.lat), \(candidate.lon)")
                Text("Никакой сервер FireWatch для просмотра не требуется. Если оператор отключил трансляцию, видео не загрузится. Просмотр не даёт разрешения на сохранение кадров или AI-анализ.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Прямой эфир")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AddCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var api: API
    @State private var name = ""
    @State private var url = ""
    @State private var cityID = "semey"
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
                Section("Город") {
                    Picker("Город Казахстана", selection: $cityID) {
                        ForEach(KazakhstanCities.all) { city in
                            Text(city.name).tag(city.id)
                        }
                    }
                    Text("Координаты камеры будут ориентировочно указаны как центр города. Для точного лесного мониторинга позже потребуется реальное местоположение объектива.")
                        .font(.caption).foregroundStyle(.secondary)
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
                        guard let parsedURL = URL(string: url),
                              let scheme = parsedURL.scheme?.lowercased(),
                              ["http", "https", "rtsp", "rtsps"].contains(scheme),
                              parsedURL.host != nil,
                              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            error = "Проверьте название и полный URL камеры."
                            return
                        }
                        saving = true
                        Task {
                            do {
                                let city = KazakhstanCities.find(cityID)
                                _ = try await api.addCamera(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                        streamURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                                        lat: city.lat, lon: city.lon)
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
                if isHLS, let url = URL(string: currentCamera.url) {
                    DirectHLSPlayer(url: url)
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
    }
}
