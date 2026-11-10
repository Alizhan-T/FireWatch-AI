import SwiftUI
import PhotosUI
import UIKit

struct DetectionView: View {
    @ObservedObject var api: API
    @State private var selected: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analyzing = false
    @State private var result: DetectionSummary?
    @State private var saveIncident = false
    @State private var cityID = "semey"
    @State private var error: String?
    @State private var localResult: OnDeviceFireResult?
    @State private var localError: String?
    @State private var localAnalyzing = false

    private var realServerAvailable: Bool {
        api.isConnected && api.health?.detector?.mode == "real_model"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("AI-анализ изображения").font(.title2.bold())
                    Text("Выберите фотографию или стоп-кадр. ИИ ищет только признаки огня и дыма, не определяет причину и не подтверждает происшествие. Для точного вывода требуется проверка оператором.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !api.isConnected {
                        Label("AI-сервер не подключён. Выбор фото доступен, но реальная нейросетевая проверка без Core ML пока недоступна.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    } else if realServerAvailable {
                        Label("Подключён YOLO AI-сервер: анализ реальной моделью, результат предварительный.",
                              systemImage: "checkmark.shield")
                            .font(.footnote).foregroundStyle(.green)
                    } else {
                        Label("DEMO-режим сервера: цветовая эвристика, НЕ нейросеть. Она не может подтвердить пожар.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    PhotosPicker(selection: $selected, matching: .images) {
                        Label("Выбрать фотографию", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .onChange(of: selected) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self) {
                                image = UIImage(data: data)
                                result = nil; error = nil
                                localResult = nil; localError = nil
                            }
                        }
                    }
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 16))
                        Section {
                            if OnDeviceFireDetector.isInstalled {
                                Button(localAnalyzing ? "Проверяем на iPhone…" : "Проверить локально через Core ML") {
                                    localAnalyzing = true
                                    localResult = nil
                                    Task {
                                        defer { localAnalyzing = false }
                                        do {
                                            localResult = try await OnDeviceFireDetector.analyze(image)
                                            localError = nil
                                        } catch {
                                            localError = error.localizedDescription
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(localAnalyzing)
                            } else {
                                Label("Локальная модель Core ML ещё не установлена. Можно добавить экспортированную модель или подключить AI-сервер.",
                                      systemImage: "cpu")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            if let localResult {
                                let kind = localResult.fireDetected && localResult.smokeDetected ? "fire_smoke" :
                                    (localResult.fireDetected ? "fire" : (localResult.smokeDetected ? "smoke" : "none"))
                                VStack(alignment: .leading, spacing: 7) {
                                    Label("Core ML · \(AIFireAssessment.headline(for: kind))",
                                          systemImage: "cpu.fill")
                                        .font(.headline)
                                    Text(AIFireAssessment.evidence(for: kind))
                                        .font(.subheadline)
                                    Text(AIFireAssessment.score(Double(localResult.confidence),
                                                                mode: "real_model", classification: kind))
                                        .font(.footnote)
                                    Text("Объектов выше порога 65%: \(localResult.objectCount)")
                                        .font(.footnote)
                                    Text(AIFireAssessment.action(for: kind, mode: "real_model"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                            if let localError {
                                Text(localError).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Toggle("Создать инцидент при обнаружении моделью", isOn: $saveIncident)
                            .disabled(!realServerAvailable)
                        if !realServerAvailable {
                            Text("Автоматическое создание инцидента отключено в DEMO-режиме. Оператор может отдельно добавить ручное событие.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if saveIncident {
                            Picker("Город Казахстана", selection: $cityID) {
                                ForEach(KazakhstanCities.all) { city in
                                    Text(city.name).tag(city.id)
                                }
                            }
                            Text("Событие появится приблизительно в центре города. Это не точная геолокация пожара.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button(analyzing ? "ИИ анализирует кадр…" :
                               (realServerAvailable ? "Анализировать через YOLO" : "Демо-анализ цвета")) {
                            let city = KazakhstanCities.find(cityID)
                            let shouldSave = saveIncident && realServerAvailable
                            let lat: Double? = shouldSave ? city.lat : nil
                            let lon: Double? = shouldSave ? city.lon : nil
                            Task {
                                guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
                                    error = "Не удалось подготовить фотографию."
                                    return
                                }
                                analyzing = true
                                result = nil
                                error = nil
                                do {
                                    result = try await api.detect(
                                        jpeg: jpeg,
                                        saveIncident: shouldSave,
                                        latitude: lat,
                                        longitude: lon,
                                        locationName: shouldSave ? "\(city.name) (координаты центра города)" : nil
                                    )
                                    error = nil
                                } catch {
                                    self.error = error.localizedDescription
                                }
                                analyzing = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(analyzing || localAnalyzing || !api.isConnected)
                    }
                    if let result {
                        ProtectedMediaImage(
                            api: api,
                            path: result.annotated_image_url ?? result.image_url
                        )
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 10) {
                            Label(AIFireAssessment.headline(for: result.classification),
                                  systemImage: result.classification == "none" ?
                                      "viewfinder" : "exclamationmark.triangle.fill")
                                .font(.headline)
                            Text(AIFireAssessment.status(mode: result.mode))
                                .font(.subheadline.bold())
                                .foregroundStyle(result.mode == "real_model" ? .green : .orange)
                            Text(AIFireAssessment.evidence(for: result.classification))
                                .font(.subheadline)
                            Text(AIFireAssessment.score(result.confidence, mode: result.mode,
                                                       classification: result.classification))
                                .font(.footnote)
                            Text("Модель: \(result.model_name)")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text("Обработка: \(result.processing_ms) мс")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(AIFireAssessment.action(for: result.classification, mode: result.mode))
                                .font(.footnote)
                            Text(result.disclaimer).font(.caption).foregroundStyle(.secondary)
                            if let incidentID = result.incident_id {
                                Label("Создано событие на проверку: \(incidentID)",
                                      systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding()
            }
            .navigationTitle("AI-детекция")
        }
    }
}
