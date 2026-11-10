import SwiftUI

private struct TrainingCameraOption: Identifiable {
    let id: String
    let title: String
    let city: String
    let cityID: String
    let streamURL: URL?
    let youtubeID: String?
}

struct DemoFireScenarioView: View {
    let event: LocalFireEvent
    let notifyAtStart: Bool
    var onClose: (() -> Void)? = nil

    @StateObject private var savedCameras = LocalHLSCameraStore()
    @State private var chosenID: String = ""
    @State private var showFireEffect = true
    @State private var notificationStatus = "Тестовые уведомления не отправляются службам спасения."
    @State private var didRequestNotification = false
    @Environment(\.dismiss) private var dismiss

    init(event: LocalFireEvent, notifyAtStart: Bool = false, onClose: (() -> Void)? = nil) {
        self.event = event
        self.notifyAtStart = notifyAtStart
        self.onClose = onClose
    }

    private var cameras: [TrainingCameraOption] {
        let publicOptions = PublicCameraCatalog.candidates.compactMap { candidate -> TrainingCameraOption? in
            guard let url = URL(string: candidate.url) else { return nil }
            return TrainingCameraOption(
                id: "public.\(candidate.id)",
                title: candidate.name,
                city: candidate.id.hasPrefix("almaty-") ? "Алматы" : "Актау",
                cityID: candidate.id.hasPrefix("almaty-") ? "almaty" : "aktau",
                streamURL: url,
                youtubeID: nil
            )
        }
        let personal = savedCameras.cameras.compactMap { camera -> TrainingCameraOption? in
            guard let url = URL(string: camera.streamURL) else { return nil }
            return TrainingCameraOption(
                id: "personal.\(camera.id.uuidString)",
                title: camera.name,
                city: "Пользовательский источник",
                cityID: "personal",
                streamURL: url,
                youtubeID: nil
            )
        }
        let publishedVideo = KazakhstanPublisherCameras.candidates.compactMap { camera -> TrainingCameraOption? in
            guard let videoID = camera.youtubeVideoID else { return nil }
            return TrainingCameraOption(
                id: "publisher.\(camera.id)",
                title: camera.name,
                city: camera.city.name,
                cityID: camera.cityID,
                streamURL: nil,
                youtubeID: videoID
            )
        }
        return publicOptions + publishedVideo + personal
    }

    private var selectedCamera: TrainingCameraOption? {
        cameras.first { $0.id == chosenID } ?? cameras.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SOS · DEMO")
                            .font(.title2.bold())
                        Text("УЧЕБНАЯ ИМИТАЦИЯ — НЕ РЕАЛЬНЫЙ ПОЖАР")
                            .font(.caption.bold())
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title).font(.title3.bold())
                    Text("Сценарий: \(event.city.name) · \(event.kind) · \(event.severity)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Сценарий не подтверждён камерой или нейросетью. Место имитации обозначено приблизительно в центре города.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Источник видеонаблюдения", systemImage: "video.fill")
                        .font(.headline)
                    if cameras.isEmpty {
                        ContentUnavailableView(
                            "Нет доступных HLS-ссылок",
                            systemImage: "video.slash",
                            description: Text("Добавьте прямую HLS-камеру во вкладке «Камеры», чтобы показать видео в тренировке.")
                        )
                    } else {
                        Picker("Камера для демонстрации", selection: $chosenID) {
                            ForEach(cameras) { camera in
                                Text(camera.title).tag(camera.id)
                            }
                        }
                        .pickerStyle(.menu)
                        if let camera = selectedCamera {
                            ZStack(alignment: .topLeading) {
                                if let url = camera.streamURL {
                                    DirectHLSPlayer(url: url)
                                        .id(camera.id)
                                } else if let videoID = camera.youtubeID {
                                    EmbeddedYouTubePlayer(videoID: videoID)
                                        .frame(height: 275)
                                        .id(camera.id)
                                }
                                VStack {
                                    Text("DEMO · ВИЗУАЛЬНАЯ СИМУЛЯЦИЯ")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(.red.opacity(0.95), in: Capsule())
                                    Spacer()
                                }
                                .padding(10)
                                .allowsHitTesting(false)

                                if showFireEffect {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            RealisticFireOverlay()
                                        }
                                    }
                                    .padding(.bottom, 14)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            Label("Видео: \(camera.city). Учебное событие: \(event.city.name). Это могут быть разные города.", systemImage: "location.circle")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }

                    Toggle("Огонь и дым поверх камеры (VFX)", isOn: $showFireEffect)
                        .tint(.orange)

                    Text("Если прямой HLS-поток недоступен, приложение честно покажет ошибку плеера. Анимация огня, дыма и отсветов создана программно. Она не изменяет исходное видео, не создаёт записи и не означает реального пожара.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Label("Уведомление SOS · только DEMO", systemImage: "bell.badge.fill")
                        .font(.headline)
                    Text(notificationStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            notificationStatus = await DemoSOSNotifications.schedule(for: event)
                        }
                    } label: {
                        Label("Отправить тестовое SOS на этот iPhone", systemImage: "bell.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    Text("Реальные службы 101/112, другие люди и серверы не получают это сообщение. Разрешите уведомления iOS при первом запуске теста.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                Button("Завершить тренировку") {
                    if let onClose { onClose() } else { dismiss() }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Учебный пожар")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if chosenID.isEmpty {
                chosenID = cameras.first(where: { $0.cityID == event.cityID })?.id ??
                           cameras.first(where: { $0.cityID == "aktau" })?.id ??
                           cameras.first?.id ?? ""
            }
            guard notifyAtStart, !didRequestNotification else { return }
            didRequestNotification = true
            notificationStatus = await DemoSOSNotifications.schedule(for: event)
        }
    }
}
