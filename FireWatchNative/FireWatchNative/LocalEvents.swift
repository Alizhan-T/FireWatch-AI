import Foundation
import SwiftUI

/// Local operator notes and simulations are never asserted as AI detections.
/// City center is used as an approximate display point, not an exact fire location.
struct LocalFireEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var details: String
    var cityID: String
    var kind: String
    var severity: String
    var isSimulation: Bool
    var resolved: Bool
    var createdAt: Date

    var city: KazakhstanCity { KazakhstanCities.find(cityID) }
}

@MainActor
final class LocalEventStore: ObservableObject {
    @Published private(set) var events: [LocalFireEvent] = []
    private let defaults: UserDefaults
    private let storageKey = "firewatch.localEvents.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([LocalFireEvent].self, from: data) {
            events = saved.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func create(title: String, details: String, cityID: String, kind: String,
                severity: String, simulation: Bool) {
        let city = KazakhstanCities.find(cityID)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = LocalFireEvent(
            id: UUID(),
            title: name.isEmpty ? (simulation ? "Учебная тревога" : "Сообщение оператора") : name,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            cityID: city.id,
            kind: kind,
            severity: severity,
            isSimulation: simulation,
            resolved: false,
            createdAt: Date()
        )
        events.insert(event, at: 0)
        save()
    }

    func setResolved(_ event: LocalFireEvent, _ done: Bool) {
        guard let i = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[i].resolved = done
        save()
    }

    func delete(_ event: LocalFireEvent) {
        events.removeAll { $0.id == event.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct LocalEventCard: View {
    let event: LocalFireEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.isSimulation ? "play.square.fill" : "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(event.isSimulation ? .orange : .red)
                .font(.title2)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                HStack(spacing: 8) {
                    Text(event.isSimulation ? "DEMO · СИМУЛЯЦИЯ" : "РУЧНОЕ СООБЩЕНИЕ")
                        .font(.caption2.bold())
                        .foregroundStyle(event.isSimulation ? .orange : .secondary)
                    if event.resolved { Text("ЗАКРЫТО").font(.caption2.bold()).foregroundStyle(.green) }
                }
                Text("\(event.city.name) · \(event.kind) · \(event.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct LocalEventDetailView: View {
    @ObservedObject var store: LocalEventStore
    let event: LocalFireEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Тип события") {
                Label(event.isSimulation ? "DEMO — не реальный пожар" : "Сообщение вручную — не подтверждено AI",
                      systemImage: event.isSimulation ? "play.square" : "hand.raised")
                    .foregroundStyle(event.isSimulation ? .orange : .secondary)
                LabeledContent("Город", value: event.city.name)
                LabeledContent("Тип", value: event.kind)
                LabeledContent("Важность", value: event.severity)
                LabeledContent("Время", value: event.createdAt.formatted())
                Text("На карте отмечен центр города, а не точное место возгорания.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !event.details.isEmpty {
                Section("Описание") { Text(event.details) }
            }
            Section("Управление") {
                Button(event.resolved ? "Вернуть в активные" : "Отметить закрытым") {
                    store.setResolved(event, !event.resolved)
                    dismiss()
                }
                Button("Удалить запись", role: .destructive) {
                    store.delete(event)
                    dismiss()
                }
            }
        }
        .navigationTitle(event.title)
    }
}

struct CreateLocalEventView: View {
    @ObservedObject var store: LocalEventStore
    let startsAsSimulation: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var cityID = "semey"
    @State private var kind = "Огонь"
    @State private var severity = "Средняя"
    @State private var isSimulation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Событие") {
                    TextField("Название (необязательно)", text: $title)
                    Picker("Город Казахстана", selection: $cityID) {
                        ForEach(KazakhstanCities.all) { city in
                            Text(city.name).tag(city.id)
                        }
                    }
                    Picker("Обнаружено", selection: $kind) {
                        Text("Огонь").tag("Огонь")
                        Text("Дым").tag("Дым")
                        Text("Огонь и дым").tag("Огонь и дым")
                        Text("Проверка").tag("Проверка")
                    }
                    Picker("Важность", selection: $severity) {
                        Text("Низкая").tag("Низкая")
                        Text("Средняя").tag("Средняя")
                        Text("Высокая").tag("Высокая")
                        Text("Критическая").tag("Критическая")
                    }
                    TextField("Описание", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Режим") {
                    Toggle("Имитация (DEMO)", isOn: $isSimulation)
                    Text(isSimulation
                         ? "Это учебная симуляция. Она никогда не будет показана как настоящий пожар или подтверждённая AI-детекция."
                         : "Это ваше ручное сообщение, которое не проверено нейросетью и не является официальной пожарной тревогой.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Координаты вводить не нужно: на карте событие будет примерно в центре выбранного города.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isSimulation ? "Имитация события" : "Новое событие")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.create(title: title, details: details, cityID: cityID,
                                     kind: kind, severity: severity, simulation: isSimulation)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { isSimulation = startsAsSimulation }
    }
}

struct EventCenterView: View {
    @ObservedObject var api: API
    @ObservedObject var store: LocalEventStore
    @State private var creatingMode: EventCreationMode?

    private enum EventCreationMode: String, Identifiable {
        case manual, demo
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button {
                            creatingMode = .manual
                        } label: {
                            Label("Создать событие", systemImage: "plus.circle.fill")
                        }
                        Spacer()
                        Button {
                            creatingMode = .demo
                        } label: {
                            Label("Имитация", systemImage: "play.square.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    Text("Локальные события хранятся на этом iPhone. DEMO и ручные сообщения не считаются AI-обнаружениями.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Мои события · \(store.events.count)") {
                    ForEach(store.events) { event in
                        NavigationLink {
                            LocalEventDetailView(store: store, event: event)
                        } label: {
                            LocalEventCard(event: event)
                        }
                    }
                    .onDelete { indices in
                        let existing = store.events
                        for index in indices {
                            store.delete(existing[index])
                        }
                    }
                    if store.events.isEmpty {
                        Text("Пока нет локальных событий. Нажмите «Имитация», чтобы проверить приложение.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if api.isConnected {
                    Section("Обнаружения с AI-сервера") {
                        ForEach(api.incidents) { incident in
                            NavigationLink {
                                IncidentDetailView(api: api, incident: incident)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(incident.title).font(.headline)
                                    Text(incident.is_demo ? "DEMO / сервер" : "От сервера · \(incident.detection_mode)")
                                        .font(.caption)
                                        .foregroundStyle(incident.is_demo ? .orange : .secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("События")
            .sheet(item: $creatingMode) { mode in
                CreateLocalEventView(store: store, startsAsSimulation: mode == .demo)
            }
            .refreshable { if api.isConnected { await api.refresh() } }
        }
    }
}
