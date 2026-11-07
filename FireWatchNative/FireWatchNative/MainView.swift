import SwiftUI
import MapKit

private enum Palette {
    static let accent = Color(red: 0.96, green: 0.32, blue: 0.20)
}

struct MainView: View {
    @StateObject private var api = API()
    @StateObject private var pushManager = PushManager.shared
    @State private var showSettings = false

    var body: some View {
        TabView {
            dashboard.tabItem { Label("Обзор", systemImage: "square.grid.2x2.fill") }
            map.tabItem { Label("Карта", systemImage: "map.fill") }
            incidents.tabItem { Label("События", systemImage: "flame.fill") }
            CameraLibraryView(api: api).tabItem { Label("Камеры", systemImage: "video.fill") }
            DetectionView(api: api).tabItem { Label("AI", systemImage: "sparkles") }
        }
        .tint(Palette.accent)
        .task {
            await api.refresh()
            if let token = pushManager.fcmToken {
                try? await api.registerDevice(token: token)
            }
        }
        .onChange(of: pushManager.fcmToken) { _, token in
            guard let token else { return }
            Task {
                do { try await api.registerDevice(token: token) }
                catch { api.error = error.localizedDescription }
            }
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
            Map {
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
                            Task { await api.refresh() }
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
                    Text("Для push нужны Firebase-проект, GoogleService-Info.plist, APNs key в Firebase и capability Push Notifications в Xcode.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Состояние сервера") {
                    LabeledContent("Подключение", value: api.isConnected ? "Подключён" : "Не подключён")
                    LabeledContent("База данных", value: api.health?.database == true ? "Работает" : "Нет связи")
                    LabeledContent("FFmpeg", value: api.health?.ffmpeg == true ? "Установлен" : "Не обнаружен")
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
