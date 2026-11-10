import SwiftUI
import AVKit

struct IncidentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var api: API
    let incident: Incident
    @State private var selectedStatus: String
    @State private var savedStatus: String
    @State private var savingStatus = false
    @State private var showingDeleteConfirmation = false
    @State private var error: String?
    @State private var player: AVPlayer?

    init(api: API, incident: Incident) {
        self.api = api
        self.incident = incident
        _selectedStatus = State(initialValue: incident.status)
        _savedStatus = State(initialValue: incident.status)
    }

    var body: some View {
        Form {
            Section("Инцидент") {
                LabeledContent("Название", value: incident.title)
                LabeledContent("Уровень", value: incident.severity.uppercased())
                LabeledContent("Источник", value: incident.source)
                LabeledContent("Классификация", value: incident.classification ?? "Не указана")
                LabeledContent("Режим детектора", value: incident.detection_mode)
                if let confidence = incident.confidence {
                    LabeledContent("Уверенность модели", value: "\(Int(confidence * 100))%")
                }
                LabeledContent("Координаты", value: "\(incident.lat), \(incident.lon)")
                if let location = incident.location_name {
                    LabeledContent("Место", value: location)
                }
                LabeledContent("Создан", value: incident.created_at)
                if incident.is_demo {
                    Label("ДЕМО / НЕ ПОДТВЕРЖДЕНО", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let description = incident.description, !description.isEmpty {
                    Text(description)
                }
            }

            if let mediaPath = incident.media_url {
                Section("Материал") {
                    if incident.media_type == "video" {
                        if let player {
                            VideoPlayer(player: player).frame(height: 220)
                        } else {
                            ProgressView("Загружаем видео…")
                        }
                    } else {
                        ProtectedMediaImage(api: api, path: mediaPath)
                            .frame(maxHeight: 300)
                    }
                    if let note = incident.media_note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Обработка") {
                Picker("Статус", selection: $selectedStatus) {
                    Text("Новое").tag("new")
                    Text("Принято").tag("acknowledged")
                    Text("Решено").tag("resolved")
                    Text("Ложная тревога").tag("false_alarm")
                }
                Button {
                    savingStatus = true
                    Task {
                        do {
                            try await api.updateIncident(incident, status: selectedStatus)
                            savedStatus = selectedStatus
                            error = nil
                        } catch {
                            self.error = error.localizedDescription
                        }
                        savingStatus = false
                    }
                } label: {
                    if savingStatus { ProgressView("Сохраняем…") }
                    else { Label("Сохранить статус", systemImage: "checkmark.circle") }
                }
                .disabled(savingStatus || selectedStatus == savedStatus)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }

            Section {
                Button("Удалить инцидент", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Детали события")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Удалить этот инцидент?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task {
                    do {
                        try await api.deleteIncident(incident)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear {
            if incident.media_type == "video", let mediaPath = incident.media_url {
                Task {
                    do {
                        let localURL = try await api.downloadMedia(for: mediaPath)
                        player = AVPlayer(url: localURL)
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
