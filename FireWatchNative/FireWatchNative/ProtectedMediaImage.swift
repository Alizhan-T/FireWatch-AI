import SwiftUI
import UIKit

struct ProtectedMediaImage: View {
    @ObservedObject var api: API
    let path: String
    @State private var image: UIImage?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if loading {
                ProgressView("Загружаем изображение…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if failed {
                ContentUnavailableView("Изображение недоступно", systemImage: "photo")
            }
        }
        .task(id: path) {
            loading = true
            failed = false
            image = nil
            do {
                let data = try await api.mediaData(for: path)
                image = UIImage(data: data)
                failed = image == nil
            } catch {
                failed = true
            }
            loading = false
        }
    }
}
