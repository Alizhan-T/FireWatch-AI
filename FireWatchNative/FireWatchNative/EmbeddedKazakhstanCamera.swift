import SwiftUI
import WebKit

/// The publisher's YouTube embed stays inside the iPhone app.
/// This does not bypass the publisher's embed settings or DRM restrictions.
struct EmbeddedYouTubePlayer: UIViewRepresentable {
    let videoID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        if let url = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0") {
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Embedded media resources may use multiple Google domains; block
            // only navigation of the main view to a publisher website.
            if navigationAction.targetFrame?.isMainFrame == true,
               let host = navigationAction.request.url?.host?.lowercased(),
               host != "www.youtube-nocookie.com" && host != "youtube-nocookie.com" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

struct AkzhaiykEmbeddedCameraView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Резерват «Акжайык»").font(.title3.bold())
                EmbeddedYouTubePlayer(videoID: "CmtFHHCJbOo")
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Label("Видео встроено в FireWatch", systemImage: "play.rectangle")
                    .font(.subheadline)
                Text("Источник — публично анонсированная трансляция наблюдательных вышек Казахстана. Сейчас она может быть завершена, недоступна или запрещена к встраиванию владельцем. Если плеер сообщает об ошибке, приложение не может принудительно открыть этот поток.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Просмотр здесь не означает разрешения на сохранение или автоматический AI-анализ кадров.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Акжайык")
        .navigationBarTitleDisplayMode(.inline)
    }
}
