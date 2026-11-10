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
            id: "astana-khan-shatyr-publisher",
            cityID: "astana",
            name: "Астана — Хан Шатыр · официальный сайт",
            pageURL: URL(string: "https://www.khanshatyr.com/ru/camera")!,
            reliabilityNote: "Официальная страница Live камер ТРЦ «Хан Шатыр», проспект Туран, 37. Доступность видео в iOS не подтверждена; отдельный HLS-поток не предоставлен. Для огня и сканера используется только отдельная учебная сцена."
        ),
        .init(
            id: "astana-atameken-city-2026",
            cityID: "astana",
            name: "Астана — городские виды 24/7 · Atameken Business",
            pageURL: URL(string: "https://www.youtube.com/watch?v=sR4YuJ-6UO4")!,
            reliabilityNote: "Опубликованная Atameken Business 24.02.2026 городская трансляция с видами на Хан Шатыр и мост Кунаева. Актуальное воспроизведение и разрешение на встраивание проверяются на вашем iPhone; прямого HLS нет.",
            youtubeVideoID: "sR4YuJ-6UO4"
        ),
        .init(
            id: "astana-atameken-live",
            cityID: "astana",
            name: "Астана — резервный эфир · Atameken Business",
            pageURL: URL(string: "https://www.youtube.com/live/FKT8MiiKQG4")!,
            reliabilityNote: "Ранее опубликованная Atameken Business трансляция, анонсированная 28.01.2026. Резервная ссылка; эфир мог завершиться, а встраивание может быть запрещено.",
            youtubeVideoID: "FKT8MiiKQG4"
        ),

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

struct InAppPublisherPage: UIViewRepresentable {
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
            // Document completion does NOT verify the embedded video.
            isLoading.wrappedValue = false
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isLoading.wrappedValue = false
            errorMessage.wrappedValue = "Процесс видеостраницы остановлен. Нажмите «Повторить» или откройте официальный сайт."
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
                "player.vimeo.com", "shymbulak.com", "www.shymbulak.com",
                "khanshatyr.com", "www.khanshatyr.com"
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
    @State private var embedError: String?
    @State private var showVideoScanner = false
    @State private var showVideoFireDemo = false
    @State private var showSeparateTraining = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(camera.name)
                    .font(.title3.bold())
                if let videoID = camera.youtubeVideoID {
                    EmbeddedYouTubePlayer(videoID: videoID, errorMessage: $embedError)
                        .id(reloadID)
                        .frame(height: 270)
                        .overlay {
                            if showVideoScanner {
                                DemoScannerOverlay()
                                    .allowsHitTesting(false)
                            }
                            if showVideoFireDemo {
                                GeometryReader { geometry in
                                    let videoHeight = min(geometry.size.height,
                                                          geometry.size.width * 9 / 16)
                                    RealisticFireOverlay()
                                        .scaleEffect(0.58)
                                        .position(x: geometry.size.width * 0.65,
                                                  y: geometry.size.height / 2 + videoHeight * 0.42 - 117 * 0.58)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if showVideoFireDemo {
                                Text("DEMO • ИСКУССТВЕННЫЙ ОГОНЬ")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(7)
                                    .background(.red.opacity(0.9), in: Capsule())
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    Toggle("Зелёная линия сканирования (DEMO)", isOn: $showVideoScanner)
                        .tint(.green)
                    Toggle("Огонь и дым поверх видео (DEMO)", isOn: $showVideoFireDemo)
                        .tint(.orange)
                    if showVideoScanner || showVideoFireDemo {
                        Text("Эффекты только визуальные: кадры не анализируются нейросетью, реальный пожар не обнаружен.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let embedError {
                        Label("Встроенный YouTube: \(embedError)", systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
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
                    if !pageLoading && loadError == nil {
                        Label("Страница загрузилась; работа самого видео не подтверждена",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Показать учебный пожар и зелёную линию отдельно", isOn: $showSeparateTraining)
                        .tint(.orange)
                    if showSeparateTraining {
                        DemoTrainingStage()
                        Text("Учебный фон без кадров «Хан Шатыр». Огонь, дым и сканирование — анимация, а не AI-детекция.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if camera.youtubeVideoID != nil {
                    Text("Если изображение чёрное, YouTube сообщает об ошибке или требует дополнительной проверки, нажмите ниже «Смотреть эфир во встроенном браузере». Это другой режим просмотра, не обход ограничений издателя.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    showSourceBrowser = true
                } label: {
                    Label(camera.youtubeVideoID == nil ? "Открыть страницу камеры" :
                          "Смотреть эфир во встроенном браузере", systemImage: "globe")
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
                    embedError = nil
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
