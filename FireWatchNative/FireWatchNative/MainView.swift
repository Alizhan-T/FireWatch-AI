import SwiftUI
import MapKit

private enum Palette {
    static let accent = Color(red: 0.96, green: 0.32, blue: 0.20)
}

struct MainView: View {
    @StateObject private var api = API()
    @StateObject private var pushManager = PushManager.shared
    @State private var showSettings = false
    @State private var monitoringBusy = false
    @State private var pushTestBusy = false
    @State private var pushTestMessage: String?
    @State private var selectedTab = 0
    @State private var pushIncident: Incident?

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboard.tabItem { Label("Обзор", systemImage: "square.grid.2x2.fill") }.tag(0)
            map.tabItem { Label("Карта", systemImage: "map.fill") }.tag(1)
            incidents.tabItem { Label("События", systemImage: "flame.fill") }.tag(2)
            CameraLibraryView(api: api).tabItem { Label("Камеры", systemImage: "video.fill") }.tag(3)
            DetectionView(api: api).tabItem { Label("AI", systemImage: "sparkles") }.tag(4)
        }
        .tint(Palette.accent)
        .task {
            await api.refresh()
            if let token = pushManager.fcmToken {
                try? await api.registerDevice(token: token)
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 20_000_000_000)
                } catch {
                    break
                }
                if Task.isCancelled { break }
                await api.refresh()
            }
        }
        .onChange(of: pushManager.fcmToken) { _, token in
            guard let token else { return }
            Task {
                do { try await api.registerDevice(token: token) }
                catch { api.error = error.localizedDescription }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fireWatchOpenIncident)) { notification in
            guard let id = notification.userInfo?["incident_id"] as? String else { return }
            selectedTab = 2
            Task {
                do { pushIncident = try await api.fetchIncident(id: id) }
                catch { api.error = error.localizedDescription }
            }
        }
        .sheet(item: $pushIncident) { incident in
            NavigationStack { IncidentDetailView(api: api, incident: incident) }
        }
    }

    private var dashboard: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FIREWATCH").font(.caption.bold()).tracking(3).foregroundStyle(Palette.accent)
                            Text("Мониторинг пожаров").font(.title2.bold())
                        }
                        Spacer()
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.title3).padding(10)
                                .background(.regularMaterial, in: Circle())
                        }
                    }
                    HStack(spacing: 8) {
                        Circle().fill(api.isConnected ? .green : .orange).frame(width: 8, height: 8)
                        Text(api.isConnected ? "Сервер подключён" : "Нет подключения к серверу")
                            .font(.caption.bold())
                        Spacer()
                        if let last = api.lastSuccessfulSync {
                            Text(last, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    if let error = api.error {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(.orange)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    HStack(spacing: 12) {
                        metric("Обнаружения огня", value: api.stats?.fire_detections ?? 0, icon: "flame.fill", color: .red)
                        metric("Обнаружения дыма", value: api.stats?.smoke_detections ?? 0, icon: "smoke.fill", color: .gray)
                    }
                    HStack(spacing: 12) {
                        metric("Камеры онлайн", value: api.stats?.cameras_online ?? 0, icon: "video.fill", color: .green)
                        metric("Зоны риска", value: api.stats?.high_risk_zones ?? 0, icon: "exclamationmark.triangle.fill", color: .orange)
                    }
                    if let detector = api.health?.detector {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI-модуль").font(.headline)
                            Text(detector.model_name ?? "Модель не указана").font(.subheadline)
                            Text("Режим: \(detector.mode ?? "неизвестен")")
                                .font(.caption.bold())
                                .foregroundStyle(detector.mode == "real_model" ? .green : .orange)
                            if let reason = detector.fallback_reason, !reason.isEmpty {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    HStack {
                        Text("Последние события").font(.headline)
                        Spacer()
                        Button("Обновить") { Task { await api.refresh() } }
                            .font(.caption.bold())
                    }
                    if api.incidents.isEmpty {
                        ContentUnavailableView("Нет событий", systemImage: "checkmark.shield",
                            description: Text(api.isConnected ? "Активных событий пока нет." : "Подключите сервер в настройках."))
                            .frame(minHeight: 150)
                    }
                    ForEach(api.incidents.prefix(5)) { incident in
                        NavigationLink {
                            IncidentDetailView(api: api, incident: incident)
                        } label: {
                            IncidentRow(incident: incident)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
            .refreshable { await api.refresh() }
            .sheet(isPresented: $showSettings) { settings }
        }
    }

    private func metric(_ name: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value.formatted()).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
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
                ForEach(api.cameras) { camera in
                    Marker(camera.name, systemImage: "video.fill",
                           coordinate: CLLocationCoordinate2D(latitude: camera.lat, longitude: camera.lon))
                        .tint(.blue)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .navigationTitle("Карта")
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
                    TextField("http://192.168.1.20:8000", text: $api.baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("API key (если включён на сервере)", text: $api.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Сохранить и проверить") {
                        do {
                            try api.saveURL()
                            Task {
                                await api.refresh()
                                if let token = pushManager.fcmToken {
                                    do { try await api.registerDevice(token: token) }
                                    catch { api.error = error.localizedDescription }
                                }
                            }
                            showSettings = false
                        } catch {
                            api.error = error.localizedDescription
                        }
                    }
                    if let error = api.error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("Push-уведомления") {
                    Text(pushManager.status).font(.footnote).foregroundStyle(.secondary)
                    Button("Запросить разрешение на уведомления") {
                        Task { await pushManager.requestPermission() }
                    }
                    if pushManager.fcmToken != nil {
                        Label("FCM-токен получен", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button(pushTestBusy ? "Отправляем…" : "Отправить тестовое уведомление") {
                        guard let token = pushManager.fcmToken else { return }
                        pushTestBusy = true
                        Task {
                            defer { pushTestBusy = false }
                            do {
                                let result = try await api.testPush(token: token)
                                pushTestMessage = result.sent > 0
                                    ? "Firebase принял сообщение. Проверьте уведомление на iPhone."
                                    : "Отправка не удалась: \(result.errors?.joined(separator: ", ") ?? "проверьте Firebase/APNs")"
                            } catch { pushTestMessage = error.localizedDescription }
                        }
                    }
                    .disabled(pushTestBusy || pushManager.fcmToken == nil || !api.isConnected)
                    if let message = pushTestMessage { Text(message).font(.footnote) }
                    Text("Для push нужны Firebase-проект, GoogleService-Info.plist, APNs key в Firebase и capability Push Notifications в Xcode.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    Text("Для работы с мобильной сетью и удалённым доступом настройте HTTPS и защиту API. Не публикуйте сервер без авторизации.")
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
