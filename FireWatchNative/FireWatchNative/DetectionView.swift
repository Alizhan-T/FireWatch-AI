import SwiftUI
import PhotosUI
import UIKit

struct DetectionView: View {
    @ObservedObject var api: API
    @State private var selected: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analyzing = false
    @State private var result: DetectionSummary?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("AI-анализ изображения").font(.title2.bold())
                    Text("Отправляет выбранное фото на FastAPI /detect. Нейросеть работает на сервере, а не на iPhone. Проверяйте режим модели в результате.")
                        .font(.subheadline).foregroundStyle(.secondary)
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
                            }
                        }
                    }
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 16))
                        Button(analyzing ? "Анализ..." : "Проверить на огонь и дым") {
                            Task {
                                guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return }
                                analyzing = true
                                do { result = try await api.detect(jpeg: jpeg); error = nil }
                                catch { self.error = error.localizedDescription }
                                analyzing = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(analyzing)
                    }
                    if let result {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(result.classification == "none" ? "Объекты не обнаружены" : "Обнаружено: \(result.classification)", systemImage: result.classification == "none" ? "checkmark.shield" : "exclamationmark.triangle")
                                .font(.headline)
                            Text("Уверенность: \(Int(result.confidence * 100))%")
                            Text("Режим: \(result.mode)")
                            Text("Модель: \(result.model_name)")
                            Text(result.disclaimer).font(.caption).foregroundStyle(.secondary)
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

struct DetectionSummary: Decodable {
    let classification: String
    let confidence: Double
    let mode: String
    let model_name: String
    let disclaimer: String
}
