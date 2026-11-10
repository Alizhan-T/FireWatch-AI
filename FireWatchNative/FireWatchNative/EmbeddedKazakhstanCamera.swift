import SwiftUI
import WebKit

/// The publisher's YouTube embed stays inside the iPhone app.
/// This does not bypass the publisher's embed settings or DRM restrictions.
struct EmbeddedYouTubePlayer: UIViewRepresentable {
    let videoID: String
    @Binding var errorMessage: String?

    init(videoID: String, errorMessage: Binding<String?> = .constant(nil)) {
        self.videoID = videoID
        self._errorMessage = errorMessage
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(errorMessage: $errorMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        // Standard publisher embed. YouTube's "nocookie" host and legacy
        // video IDs may fail on iOS, so the detail screen provides a direct
        // in-app publisher-browser fallback. We do not scrape media URLs.
        if let url = URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0") {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 20)
            // YouTube requires an identifying HTTP Referer for embedded players
            // (error 153 otherwise). Identify this app via its real project URL,
            // rather than an invented domain or a fake operator referrer.
            request.setValue("https://github.com/Alizhan-T/FireWatch-AI",
                             forHTTPHeaderField: "Referer")
            webView.load(request)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let errorMessage: Binding<String?>

        init(errorMessage: Binding<String?>) {
            self.errorMessage = errorMessage
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            errorMessage.wrappedValue = "не удалось открыть плеер: \(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            errorMessage.wrappedValue = "ошибка загрузки: \(error.localizedDescription)"
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            errorMessage.wrappedValue = "процесс веб-плеера остановлен. Попробуйте резервный просмотр."
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The web document loaded, but this does NOT prove video plays.
            errorMessage.wrappedValue = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  let destination = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let host = destination.host?.lowercased() ?? ""
            let allowedHosts: Set<String> = [
                "www.youtube.com", "youtube.com", "m.youtube.com",
                "www.youtube-nocookie.com", "youtube-nocookie.com"
            ]
            // Never open unrelated sites or unknown HTTP redirects in the embed.
            guard destination.scheme == "https", allowedHosts.contains(host) else {
                errorMessage.wrappedValue = "плеер потребовал внешний переход. Откройте источник через кнопку под видео."
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
