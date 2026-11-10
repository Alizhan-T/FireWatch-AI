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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("AI-анализ изображения").font(.title2.bold())
                    Text("Загрузите фотографию для анализа. Выберите только город — координаты проставятся автоматически. Сейчас реальная модель YOLO работает через дополнительный AI-сервер.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !api.isConnected {
                        Label("AI-сервер не подключён. Выбор фото доступен, но реальная нейросетевая проверка без Core ML пока недоступна.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    } else if api.health?.detector?.mode != "real_model" {
                        Label("Сервер использует демо-режим. Это не подтверждённая детекция.",
                              systemImage: "info.circle")
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
                                VStack(alignment: .leading, spacing: 5) {
                                    Label("Результат Core ML: \(localResult.classification)",
                                          systemImage: "cpu.fill")
                                        .font(.headline)
                                    Text("Уверенность: \(Int(localResult.confidence * 100))% · объектов: \(localResult.objectCount)")
                                    Text("Одиночное фото, порог 65%. Результат предварительный и требует подтверждения человеком. DEMO-событие отдельно создаётся во вкладке «События».")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                            if let localError {
                                Text(localError).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Toggle("Создать инцидент при обнаружении огня/дыма", isOn: $saveIncident)
                        if saveIncident {
                            Picker("Город Казахстана", selection: $cityID) {
                                ForEach(KazakhstanCities.all) { city in
                                    Text(city.name).tag(city.id)
                                }
                            }
                            Text("Событие появится приблизительно в центре города. Это не точная геолокация пожара.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button(analyzing ? "Анализ..." : "Проверить на огонь и дым") {
                            let city = KazakhstanCities.find(cityID)
                            let lat: Double? = saveIncident ? city.lat : nil
                            let lon: Double? = saveIncident ? city.lon : nil
                            Task {
                                guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
                                    error = "Не удалось подготовить фотографию."
                                    return
                                }
                                analyzing = true
                                do {
                                    result = try await api.detect(
                                        jpeg: jpeg,
                                        saveIncident: saveIncident,
                                        latitude: lat,
                                        longitude: lon,
                                        locationName: saveIncident ? "\(city.name) (координаты центра города)" : nil
                                    )
                                    error = nil
                                } catch {
                                    self.error = error.localizedDescription
                                }
                                analyzing = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(analyzing || !api.isConnected)
                    }
                    if let result {
                        ProtectedMediaImage(
                            api: api,
                            path: result.annotated_image_url ?? result.image_url
                        )
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 10) {
                            Label(result.classification == "none" ? "Объекты не обнаружены" : "Обнаружено: \(result.classification)", systemImage: result.classification == "none" ? "checkmark.shield" : "exclamationmark.triangle")
                                .font(.headline)
                            Text("Уверенность: \(Int(result.confidence * 100))%")
                            Text("Режим: \(result.mode)")
                            Text("Модель: \(result.model_name)")
                            Text(result.disclaimer).font(.caption).foregroundStyle(.secondary)
                            if let incidentID = result.incident_id {
                                Label("Инцидент создан: \(incidentID)", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                            }
                            if result.mode != "real_model" {
                                Text("ВНИМАНИЕ: демонстрационная эвристика — не подтверждённая AI-детекция.")
                                    .font(.caption.bold()).foregroundStyle(.orange)
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
