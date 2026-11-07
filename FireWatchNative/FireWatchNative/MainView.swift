import SwiftUI
import MapKit

private enum Palette {
    static let accent = Color(red: 0.96, green: 0.32, blue: 0.20)
}

struct MainView: View {
    @StateObject private var api = API()
    var body: some View {
        TabView {
            dashboard.tabItem { Label("Обзор", systemImage: "square.grid.2x2.fill") }
            map.tabItem { Label("Карта", systemImage: "map.fill") }
            incidents.tabItem { Label("События", systemImage: "flame.fill") }
            CameraLibraryView(api: api).tabItem { Label("Камеры", systemImage: "video.fill") }
            settings.tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
        .tint(Palette.accent)
        .task { await api.refresh() }
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
                        Image(systemName: "flame.circle.fill").font(.largeTitle).foregroundStyle(Palette.accent)
                    }
                    if let error = api.error { Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange) }
                    HStack(spacing: 12) {
                        metric("Огонь", value: api.stats?.fire_detections ?? 0, icon: "flame.fill", color: .red)
                        metric("Дым", value: api.stats?.smoke_detections ?? 0, icon: "smoke.fill", color: .gray)
                    }
                    HStack(spacing: 12) {
                        metric("Камеры онлайн", value: api.stats?.cameras_online ?? 0, icon: "video.fill", color: .green)
                        metric("Зоны риска", value: api.stats?.high_risk_zones ?? 0, icon: "exclamationmark.triangle.fill", color: .orange)
                    }
                    Text("Последние события").font(.headline)
                    if api.incidents.isEmpty { ContentUnavailableView("Нет событий", systemImage: "checkmark.shield", description: Text("Обнови данные или проверь подключение к серверу")) }
                    ForEach(api.incidents.prefix(5)) { incident in incidentRow(incident) }
                }
                .padding()
            }
            .navigationTitle("Обзор")
            .refreshable { await api.refresh() }
        }
    }

    private func metric(_ name: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value.formatted()).font(.system(size: 32, weight: .bold, design: .rounded))
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
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Palette.accent, in: Circle())
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .navigationTitle("Карта пожаров")
        }
    }

    private var incidents: some View {
        NavigationStack {
            List(api.incidents) { incident in incidentRow(incident) }
                .overlay { if api.incidents.isEmpty { ContentUnavailableView("Событий нет", systemImage: "flame.slash") } }
                .navigationTitle("События")
                .refreshable { await api.refresh() }
        }
    }

    private func incidentRow(_ incident: Incident) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .foregroundStyle(incident.severity == "critical" ? .red : .orange)
                .frame(width: 36, height: 36)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(incident.title).font(.subheadline.bold())
                Text(incident.location_name ?? "Координаты: \(incident.lat), \(incident.lon)").font(.caption).foregroundStyle(.secondary)
                if incident.is_demo { Text("ДЕМО").font(.caption2.bold()).foregroundStyle(.orange) }
            }
            Spacer()
            Text(incident.severity.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var cameras: some View {
        NavigationStack {
            List(api.cameras) { camera in
                HStack {
                    Image(systemName: "video.fill").foregroundStyle(camera.status == "online" ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(camera.name).font(.headline)
                        Text(camera.status ?? "unchecked").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { if api.cameras.isEmpty { ContentUnavailableView("Камеры не добавлены", systemImage: "video.slash") } }
            .navigationTitle("Камеры")
            .refreshable { await api.refresh() }
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Подключение к FastAPI") {
                    TextField("http://192.168.1.10:8000", text: $api.baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Button("Сохранить и проверить") { api.saveURL(); Task { await api.refresh() } }
                    if let error = api.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                Section("Информация") {
                    LabeledContent("Клиент", value: "Native SwiftUI")
                    LabeledContent("Сервер", value: "FireWatch FastAPI")
                    Text("Демонстрационные инциденты обозначаются отдельно. Не используйте демо-результаты как подтверждённые пожары.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
