import SwiftUI
import WebKit

/// Publisher pages without a known authorized direct HLS feed.
/// They are kept separate from verified HLS streams and never labelled "online".
struct PublishedWebCamera: Identifiable {
    let id: String
    let cityID: String
    let name: String
    let pageURL: URL
    let reliabilityNote: String

    var city: KazakhstanCity { KazakhstanCities.find(cityID) }
}

enum KazakhstanPublisherCameras {
    static let candidates: [PublishedWebCamera] = [
        .init(
            id: "semey-central-square",
            cityID: "semey",
            name: "Семей — Центральная площадь",
            pageURL: URL(string: "https://www.geocam.ru/online/abaya/")!,
            reliabilityNote: "Источник gorset.kz через Geocam. Отмечен как нестабильный; прямой HLS не найден. Воспроизведение на iPhone не подтверждено."
        ),
        .init(
            id: "almaty-shymbulak",
            cityID: "almaty",
            name: "Алматы — Шымбулак",
            pageURL: URL(string: "https://shymbulak.com/live")!,
            reliabilityNote: "Страница трансляций курорта. Прямая ссылка HLS не подтверждена; сайт может ограничивать встроенное воспроизведение."
        )
    ]
}

/// View a publisher's public page in-app without claiming to extract/redistribute
/// its protected stream. Video playback may still depend on website policies.
private struct InAppPublisherPage: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator(startURL: url) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let startURL: URL
        init(startURL: URL) { self.startURL = startURL }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow linked video players/embedded subframes; do not open Safari.
            // The initial provider site remains the only top-level page.
            if navigationAction.targetFrame?.isMainFrame == true,
               let destination = navigationAction.request.url,
               destination.host?.lowercased() != startURL.host?.lowercased() {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

struct PublisherCameraDetailView: View {
    let camera: PublishedWebCamera

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(camera.name)
                .font(.title3.bold())
                .padding(.horizontal)
            Text("Источник открыт в FireWatch. Это не прямой HLS и не подтверждённое воспроизведение: сайт может заблокировать видео внутри iPhone.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal)
            InAppPublisherPage(url: camera.pageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(camera.reliabilityNote)
                .font(.caption).foregroundStyle(.orange)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .navigationTitle(camera.city.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
