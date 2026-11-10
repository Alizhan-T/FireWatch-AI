import SwiftUI

/// Lightweight, server-free dashboard. All counts explicitly distinguish
/// saved/manual items from verified AI detections and live camera playback.
private enum FireWatchStyle {
    static let accent = Color(red: 1.00, green: 0.34, blue: 0.21)
    static let deep = Color(red: 0.075, green: 0.086, blue: 0.115)
    static let light = Color(red: 0.96, green: 0.97, blue: 0.98)
}

struct FireWatchDashboard: View {
    @ObservedObject var api: API
    @ObservedObject var events: LocalEventStore
    let onOpenCameras: () -> Void
    let onOpenEvents: () -> Void
    let onOpenSettings: () -> Void

    @State private var showSimulation = false
    @State private var showManualEvent = false

    private var aiReady: Bool {
        OnDeviceFireDetector.isInstalled ||
        (api.isConnected && api.health?.detector?.mode == "real_model")
    }

    private var aiStatusText: String {
        if OnDeviceFireDetector.isInstalled {
            return "Core ML установлена · анализ фото на iPhone доступен"
        }
        if api.isConnected && api.health?.detector?.mode == "real_model" {
            return "YOLO-сервер подключён · анализ изображений доступен"
        }
        if api.isConnected {
            return "AI-сервер подключён, но настоящая модель не активна (DEMO)"
        }
        return "Камеры доступны без сервера · AI требует Core ML или YOLO"
    }

    private var activeEvents: [LocalFireEvent] {
        events.events.filter { !$0.resolved }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    hero
                    overview
                    quickActions
                    latestEvents
                    statusFooter
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 26)
            }
            .background(FireWatchStyle.light.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSimulation) {
                CreateLocalEventView(store: events, startsAsSimulation: true)
            }
            .sheet(isPresented: $showManualEvent) {
                CreateLocalEventView(store: events, startsAsSimulation: false)
            }
            .refreshable {
                if !api.baseURL.isEmpty { await api.refresh() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(FireWatchStyle.deep)
                    .frame(width: 48, height: 48)
                Image(systemName: "flame.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FireWatchStyle.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("FIREWATCH")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(FireWatchStyle.deep)
                Text("Мониторинг • Казахстан")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(FireWatchStyle.deep)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
            }
            .accessibilityLabel("Открыть настройки")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("НАБЛЮДЕНИЕ", systemImage: "eye")
                    .font(.caption.bold())
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("КАМЕРЫ")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.white.opacity(0.12), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Держите ситуацию\nпод контролем")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Публичные видеопотоки Казахстана и ваши события — в одном приложении.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Button(action: onOpenCameras) {
                HStack {
                    Label("Смотреть камеры", systemImage: "video.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(FireWatchStyle.deep)
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [FireWatchStyle.deep, Color(red: 0.19, green: 0.20, blue: 0.27)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "flame.fill")
                .font(.system(size: 125, weight: .thin))
                .foregroundStyle(FireWatchStyle.accent.opacity(0.10))
                .rotationEffect(.degrees(-15))
                .padding(.trailing, 10)
                .padding(.top, 26)
                .allowsHitTesting(false)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Сводка", subtitle: "Только подтверждённые данные")
            HStack(spacing: 12) {
                statistic(
                    title: "HLS-источники",
                    value: "\(PublicCameraCatalog.candidates.count)",
                    subtitle: "В каталоге, не статус онлайн",
                    symbol: "video.fill",
                    color: Color(red: 0.12, green: 0.53, blue: 0.72)
                )
                statistic(
                    title: "Активные события",
                    value: "\(activeEvents.count)",
                    subtitle: "Ручные и DEMO",
                    symbol: "flame.fill",
                    color: FireWatchStyle.accent
                )
            }
            HStack(spacing: 7) {
                Image(systemName: aiReady ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(aiReady ? .green : .orange)
                Text(aiStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statistic(title: String, value: String, subtitle: String,
                           symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(FireWatchStyle.deep)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(FireWatchStyle.deep)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Быстрые действия", subtitle: "Управление без сервера")
            Button { showSimulation = true } label: {
                actionRow(
                    symbol: "play.square.fill",
                    title: "Имитировать пожар",
                    subtitle: "Учебная тревога с отметкой DEMO",
                    color: FireWatchStyle.accent
                )
            }
            Button { showManualEvent = true } label: {
                actionRow(
                    symbol: "plus.circle.fill",
                    title: "Добавить событие",
                    subtitle: "Вручную, без утверждения об AI-детекции",
                    color: Color(red: 0.15, green: 0.48, blue: 0.73)
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func actionRow(symbol: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 21))
                .foregroundStyle(color)
                .frame(width: 45, height: 45)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold()).foregroundStyle(FireWatchStyle.deep)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var latestEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeading("Последние события", subtitle: "Отмеченные вручную")
                Spacer()
                Button("Все") { onOpenEvents() }
                    .font(.subheadline.bold())
                    .foregroundStyle(FireWatchStyle.accent)
            }
            if events.events.isEmpty && api.incidents.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    Text("Событий пока нет")
                        .font(.subheadline.bold())
                        .foregroundStyle(FireWatchStyle.deep)
                    Text("Создайте учебную тревогу, чтобы проверить карту и журнал.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }
            ForEach(events.events.prefix(3)) { event in
                NavigationLink {
                    LocalEventDetailView(store: events, event: event)
                } label: {
                    LocalEventCard(event: event)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            if api.isConnected {
                ForEach(api.incidents.prefix(2)) { incident in
                    NavigationLink {
                        IncidentDetailView(api: api, incident: incident)
                    } label: {
                        Label(incident.title, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(FireWatchStyle.deep)
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Режим демонстрации", systemImage: "info.circle")
                .font(.caption.bold())
            Text("Ручные события и DEMO не являются подтверждёнными пожарами. Автоматическое AI-распознавание требует проверенной модели и доступного источника видео.")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline).foregroundStyle(FireWatchStyle.deep)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}
