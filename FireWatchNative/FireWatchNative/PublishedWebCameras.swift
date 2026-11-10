import SwiftUI
import WebKit
import SafariServices

/// Publisher pages without a known authorized direct HLS feed.
/// They are kept separate from verified HLS streams and never labelled "online".
struct PublishedWebCamera: Identifiable {
    let id: String
    let cityID: String
    let name: String
    let pageURL: URL
    let reliabilityNote: String
    var youtubeVideoID: String? = nil

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
            name: "Алматы — Шымбулак · официальный источник",
            pageURL: URL(string: "https://shymbulak.com/live")!,
            reliabilityNote: "Официальная страница Шымбулака. Успех встроенного воспроизведения зависит от оператора."
        ),
        .init(
            id: "almaty-shymbulak-alt",
            cityID: "almaty",
            name: "Алматы — Шымбулак · камера 1",
            pageURL: URL(string: "https://cam-world.ru/cams/gornolyzhnyy-kurort-shymbulak-almaty-kamera-1-00031157")!,
            reliabilityNote: "Альтернативная страница опубликованного HLS-источника. Прямой поток и воспроизведение в WKWebView не подтверждены."
        ),
        .init(
            id: "almaty-shymbulak-alt4",
            cityID: "almaty",
            name: "Алматы — Шымбулак · камера 4",
            pageURL: URL(string: "https://cam-world.ru/cams/gornolyzhnyy-kurort-shymbulak-almaty-kamera-4-00031182")!,
            reliabilityNote: "Альтернативная страница источника; доступность видео на iPhone не проверена."
        ),
        .init(
            id: "astana-atameken-live",
            cityID: "astana",
            name: "Астана — вид города (Atameken Business)",
            pageURL: URL(string: "https://www.youtube.com/live/FKT8MiiKQG4")!,
            reliabilityNote: "Официальный эфир, анонсированный 28.01.2026. YouTube может запретить встроенное видео; воспользуйтесь кнопкой «Открыть источник внутри приложения». LIVE не проверен на устройстве.",
            youtubeVideoID: "FKT8MiiKQG4"
        ),
        .init(
            id: "astana-khan-shatyr-publisher",
            cityID: "astana",
            name: "Астана — Хан Шатыр · официальный сайт",
            pageURL: URL(string: "https://www.khanshatyr.com/ru/camera")!,
            reliabilityNote: "Официальный сайт ТРЦ «Хан Шатыр» с разделом Live камеры. Доступность самого видео в WebView не подтверждена; прямой разрешённый HLS-адрес не опубликован."
        )
    ]
}

/// View a publisher's public page in-app without claiming to extract/redistribute
/// its protected stream. Video playback may still depend on website policies.

/// Fallback for a publisher whose video cannot play in WKWebView.
/// SafariServices displays the operator's own public page INSIDE this app.
struct InAppCameraBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct InAppPublisherPage: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

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

    func makeCoordinator() -> Coordinator {
        Coordinator(startURL: url, isLoading: $isLoading, errorMessage: $errorMessage)
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let startURL: URL
        let isLoading: Binding<Bool>
        let errorMessage: Binding<String?>

        init(startURL: URL, isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            self.startURL = startURL
            self.isLoading = isLoading
            self.errorMessage = errorMessage
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading.wrappedValue = true
            errorMessage.wrappedValue = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            errorMessage.wrappedValue = "Источник не загрузился: \(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            errorMessage.wrappedValue = "Не удалось подключиться: \(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Some publisher embeds redirect top-level to a player host.
            // Keep browsing in-app, restrict it to HTTPS publisher/video hosts.
            guard navigationAction.targetFrame?.isMainFrame == true,
                  let destination = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let host = destination.host?.lowercased() ?? ""
            let trusted = [
                startURL.host?.lowercased() ?? "",
                "www.youtube.com", "youtube.com", "m.youtube.com",
                "www.youtube-nocookie.com", "youtube-nocookie.com",
                "gorset.kz", "www.gorset.kz",
                "ipcam.kz", "www.ipcam.kz",
                "player.vimeo.com", "shymbulak.com", "www.shymbulak.com"
            ]
            guard destination.scheme == "https", trusted.contains(host) else {
                errorMessage.wrappedValue = "Видеоплеер запросил внешний переход, который недоступен внутри приложения."
                isLoading.wrappedValue = false
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

struct PublisherCameraDetailView: View {
    let camera: PublishedWebCamera
    @State private var reloadID = UUID()
    @State private var pageLoading = true
    @State private var loadError: String?
    @State private var showSourceBrowser = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(camera.name)
                    .font(.title3.bold())
                if let videoID = camera.youtubeVideoID {
                    EmbeddedYouTubePlayer(videoID: videoID)
                        .id(reloadID)
                        .frame(height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    InAppPublisherPage(url: camera.pageURL,
                                       isLoading: $pageLoading,
                                       errorMessage: $loadError)
                        .id(reloadID)
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    if pageLoading {
                        ProgressView("Подключаем страницу оператора…")
                    }
                    if let loadError {
                        Label(loadError, systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if camera.youtubeVideoID != nil {
                    Text("Если YouTube не воспроизводится во встроенном окне, откройте страницу владельца в защищённом браузере внутри приложения.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    showSourceBrowser = true
                } label: {
                    Label("Открыть источник внутри приложения", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $showSourceBrowser) {
                    InAppCameraBrowser(url: camera.pageURL)
                        .ignoresSafeArea()
                }
                Label("Публикация оператора · статус LIVE не гарантирован", systemImage: "video")
                    .font(.subheadline)
                Text(camera.reliabilityNote)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button {
                    loadError = nil
                    pageLoading = true
                    reloadID = UUID()
                } label: {
                    Label("Повторить загрузку источника", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Text("Камера открывается внутри FireWatch. Оператор может отключить эфир или запретить встраивание. Без прямого разрешённого HLS-потока приложение не может восстановить недоступную трансляцию.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(camera.city.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
