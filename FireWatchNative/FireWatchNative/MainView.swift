import SwiftUI
import MapKit

private enum Palette {
    static let accent = Color(red: 0.96, green: 0.32, blue: 0.20)
}

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var api = API()
    @StateObject private var localEvents = LocalEventStore()
    @State private var showSettings = false
    @State private var serverAddress = ""
    @State private var serverKey = ""
    @State private var monitoringBusy = false
    @State private var selectedTab = 0
    @State private var selectedPublicCamera: CameraCandidate?
    @State private var selectedPublisherCamera: PublishedWebCamera?
    @State private var selectedLocalEvent: LocalFireEvent?

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboard
                .tabItem { Label("Обзор", systemImage: "square.grid.2x2.fill") }.tag(0)
            // Instantiate MapKit, AVPlayer and photo analysis only when selected.
            // Keeping all five heavyweight screens alive at launch can increase
            // memory pressure on a physical iPhone.
            Group {
                if selectedTab == 1 { map } else { Color.clear }
            }
            .tabItem { Label("Карта", systemImage: "map.fill") }.tag(1)
            Group {
                if selectedTab == 2 {
                    EventCenterView(api: api, store: localEvents)
                } else { Color.clear }
            }
            .tabItem { Label("События", systemImage: "flame.fill") }.tag(2)
            Group {
                if selectedTab == 3 {
                    CameraLibraryView(api: api)
                } else { Color.clear }
            }
            .tabItem { Label("Камеры", systemImage: "video.fill") }.tag(3)
            Group {
                if selectedTab == 4 {
                    DetectionView(api: api)
                } else { Color.clear }
            }
            .tabItem { Label("AI", systemImage: "sparkles") }.tag(4)
        }
        .tint(Palette.accent)
        .task(id: scenePhase == .active ? api.configurationRevision : nil) {
            // No launch-time network requests or recurring timer in iPhone-only mode.
            guard scenePhase == .active,
                  !api.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            await api.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 45_000_000_000) }
                catch { break }
                guard !Task.isCancelled else { break }
                await api.refresh()
            }
        }
    }

    private var dashboard: some View {
        FireWatchDashboard(
            api: api,
            events: localEvents,
            onOpenCameras: { selectedTab = 3 },
            onOpenEvents: { selectedTab = 2 },
            onOpenSettings: {
                serverAddress = api.baseURL
                serverKey = api.apiKey
                showSettings = true
            }
        )
        .sheet(isPresented: $showSettings) { settings }
    }

    private var map: some View {
        NavigationStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.0196, longitude: 66.9237),
                span: MKCoordinateSpan(latitudeDelta: 15, longitudeDelta: 30)
            ))) {
                ForEach(api.incidents) { incident in
                    Annotation(incident.title, coordinate: CLLocationCoordinate2D(latitude: incident.lat, longitude: incident.lon)) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.white).padding(9)
                            .background(incident.severity == "critical" ? Color.red : Palette.accent, in: Circle())
                    }
                }
                ForEach(localEvents.events.filter { !$0.resolved }) { event in
                    Annotation(event.title,
                               coordinate: CLLocationCoordinate2D(latitude: event.city.lat, longitude: event.city.lon)) {
                        Button {
                            selectedLocalEvent = event
                        } label: {
                            Image(systemName: event.isSimulation ? "play.square.fill" : "flame.fill")
                                .foregroundStyle(.white).padding(8)
                                .background(event.isSimulation ? Color.orange : Color.red, in: Circle())
                        }
                        .accessibilityLabel(event.isSimulation ? "DEMO в \(event.city.name)" : "Ручное событие в \(event.city.name)")
                    }
                }
                ForEach(api.cameras) { camera in
                    Marker(camera.name, systemImage: "video.fill",
                           coordinate: CLLocationCoordinate2D(latitude: camera.lat, longitude: camera.lon))
                        .tint(.blue)
                }
                // Every Kazakhstan public camera pin opens its video inside FireWatch.
                ForEach(PublicCameraCatalog.candidates) { candidate in
                    Annotation(candidate.name,
                               coordinate: CLLocationCoordinate2D(latitude: candidate.lat, longitude: candidate.lon)) {
                        Button {
                            selectedPublicCamera = candidate
                        } label: {
                            Image(systemName: "video.fill")
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(.teal, in: Circle())
                        }
                        .accessibilityLabel("Смотреть \(candidate.name)")
                    }
                }
                ForEach(KazakhstanPublisherCameras.candidates) { camera in
                    Annotation(camera.name,
                               coordinate: CLLocationCoordinate2D(latitude: camera.city.lat, longitude: camera.city.lon)) {
                        Button {
                            selectedPublisherCamera = camera
                        } label: {
                            Image(systemName: "video")
                                .foregroundStyle(.white).padding(8)
                                .background(.gray, in: Circle())
                        }
                        .accessibilityLabel("Непроверенная камера: \(camera.name)")
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .safeAreaInset(edge: .top) {
                Text("Бирюзовые — HLS, серые — непроверенные камеры, оранжевые — DEMO, красные — сообщения. Отметки по центру города приблизительные.")
                    .font(.caption2)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
            .navigationTitle("Карта")
            .sheet(item: $selectedPublicCamera) { candidate in
                NavigationStack {
                    PublicCameraDetailView(candidate: candidate)
                }
            }
            .sheet(item: $selectedPublisherCamera) { camera in
                NavigationStack {
                    PublisherCameraDetailView(camera: camera)
                }
            }
            .sheet(item: $selectedLocalEvent) { event in
                NavigationStack {
                    LocalEventDetailView(store: localEvents, event: event)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await api.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
    }

    private var incidents: some View {
        NavigationStack {
            List(api.incidents) { incident in
                NavigationLink {
                    IncidentDetailView(api: api, incident: incident)
                } label: {
                    IncidentRow(incident: incident)
                }
            }
            .overlay {
                if api.incidents.isEmpty {
                    ContentUnavailableView("Событий нет", systemImage: "flame.slash")
                }
            }
            .navigationTitle("События")
            .refreshable { await api.refresh() }
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Подключение к FastAPI") {
                    TextField("http://192.168.1.20:8000", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("API key (если включён на сервере)", text: $serverKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Сохранить и проверить") {
                        do {
                            try api.saveURL(serverAddress, key: serverKey)
                            showSettings = false
                        } catch {
                            api.error = error.localizedDescription
                        }
                    }
                    if let error = api.error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("Без сервера") {
                    Text("Просмотр публичных и сохранённых HLS-камер работает напрямую на iPhone. Сервер нужен только для существующего удалённого YOLO-анализа, журнала инцидентов и push.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Использовать только iPhone") {
                        api.useWithoutServer()
                        showSettings = false
                    }
                }
                Section("Уведомления на iPhone") {
                    Label("Удалённые push отключены в этой версии", systemImage: "bell.slash")
                        .font(.subheadline)
                    Text("Они не требуются для просмотра камер и DEMO-событий. Бесплатный Apple Personal Team не поддерживает APNs. Локальные события остаются в журнале приложения.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Автоматический мониторинг") {
                    HStack {
                        Circle()
                            .fill(api.health?.camera_auto_scan_active == true ? .green : .secondary)
                            .frame(width: 9, height: 9)
                        Text(api.health?.camera_auto_scan_active == true ? "Мониторинг запущен" : "Мониторинг остановлен")
                            .font(.subheadline.bold())
                    }
                    if let current = api.health?.camera_auto_scan_current_camera {
                        LabeledContent("Проверяется", value: current)
                    }
                    if let lastRun = api.health?.camera_auto_scan_last_run_at {
                        LabeledContent("Последняя проверка", value: lastRun)
                    }
                    if let frames = api.health?.camera_confirmation_frames {
                        LabeledContent("Подтверждение тревоги", value: "\(frames) кадра подряд")
                    }
                    if let metrics = api.health?.monitoring_metrics {
                        LabeledContent("Кадров проверено", value: "\(metrics["succeeded"] ?? 0)")
                        LabeledContent("Ошибок проверки", value: "\(metrics["failed"] ?? 0)")
                    }
                    if let scanError = api.health?.camera_auto_scan_last_error, !scanError.isEmpty {
                        Text(scanError).font(.footnote).foregroundStyle(.orange)
                    }
                    if let apiError = api.error, !apiError.isEmpty {
                        Text(apiError).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        let shouldEnable = api.health?.camera_auto_scan_active != true
                        monitoringBusy = true
                        Task {
                            do {
                                _ = try await api.setMonitoring(enabled: shouldEnable)
                            } catch {
                                api.error = error.localizedDescription
                            }
                            monitoringBusy = false
                        }
                    } label: {
                        if monitoringBusy {
                            ProgressView("Применяем…")
                        } else {
                            Label(
                                api.health?.camera_auto_scan_active == true ? "Остановить мониторинг" : "Запустить мониторинг",
                                systemImage: api.health?.camera_auto_scan_active == true ? "stop.circle.fill" : "play.circle.fill"
                            )
                        }
                    }
                    .disabled(
                        monitoringBusy ||
                        (api.health?.camera_auto_scan_active != true &&
                         !(api.health?.detector?.mode == "real_model" &&
                           api.health?.ffmpeg == true &&
                           (api.health?.cameras_configured ?? 0) > 0))
                    )
                    Text("Автоматический режим доступен только при загруженной YOLO-модели, установленном FFmpeg и хотя бы одной добавленной камере. Сервер проверяет кадры по очереди.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Состояние сервера") {
                    LabeledContent("Подключение", value: api.isConnected ? "Подключён" : "Не подключён")
                    LabeledContent("База данных", value: api.health?.database == true ? "Работает" : "Нет связи")
                    LabeledContent("FFmpeg", value: api.health?.ffmpeg == true ? "Установлен" : "Не обнаружен")
                    LabeledContent("Автосканирование", value: api.health?.camera_auto_scan_active == true ? "Активно" : api.health?.camera_auto_scan_enabled == true ? "Включено, но не запущено" : "Выключено")
                    if let interval = api.health?.camera_auto_scan_interval_sec {
                        LabeledContent("Интервал сканирования", value: "\(interval) сек.")
                    }
                    LabeledContent("Firebase", value: api.health?.firebase ?? "Неизвестно")
                    LabeledContent("Камер", value: "\(api.health?.cameras_configured ?? 0)")
                }
                Section("Важно") {
                    Text("Для физического iPhone укажите LAN-IP Mac, например http://192.168.1.20:8000. localhost и 127.0.0.1 на телефоне указывают на сам телефон.")
                    Text("Просмотр HLS-камер через интернет не требует FireWatch-сервера. Для будущего удалённого AI-мониторинга используйте HTTPS и авторизацию.")
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showSettings = false }
                }
            }
        }
    }
}

private struct IncidentRow: View {
    let incident: Incident
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .foregroundStyle(incident.severity == "critical" ? .red : .orange)
                .frame(width: 36, height: 36)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(incident.title).font(.subheadline.bold())
                Text(incident.location_name ?? "Координаты: \(incident.lat), \(incident.lon)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(incident.status.uppercased())
                    if incident.is_demo { Text("DEMO").foregroundStyle(.orange) }
                }
                .font(.caption2.bold()).foregroundStyle(.secondary)
            }
            Spacer()
            Text(incident.severity.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
