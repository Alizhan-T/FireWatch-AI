import Foundation

/// Kazakhstan-only public HLS candidate catalogue. Entries are NOT proof of
/// live playback and public viewing does not grant AI processing permission.
enum PublicCameraCatalog {
    static let sourceURL = "https://cam.xcom.kz/"
    static let catalogueURL = "https://pocketworld.org/ru/webcams/country/kz"
    static let streamListURL = "https://pikniktv.info/viewtopic.php?start=50&t=9395"
    static let akzhaiykVideoURL = "https://www.youtube.com/live/CmtFHHCJbOo"
    static let akzhaiykAnnouncementURL = "https://informburo.kz/novosti/za-proisxodiashhim-v-rezervate-akzaiyk-teper-mozno-nabliudat-onlain"

    static let candidates: [CameraCandidate] = [
        CameraCandidate(
            id: "aktau-amphitheater-a",
            name: "Актау — амфитеатр 15A",
            url: "https://cam.xcom.kz:8081/amfiteatr15a/tracks-v1/mono.m3u8",
            lat: 43.6505,
            lon: 51.1441,
            source_name: "XCOM Aktau",
            source_url: "https://xcom.kz/cam/",
            catalog_url: catalogueURL,
            stream_list_url: streamListURL,
            verification_note: "XCOM обозначает камеру как онлайн; доступность HLS проверяется в приложении.",
            verified: false
        ),
        CameraCandidate(
            id: "aktau-amphitheater-b",
            name: "Актау — амфитеатр 15B",
            url: "https://cam.xcom.kz:8081/amfiteatr15b/tracks-v1/mono.m3u8",
            lat: 43.6508,
            lon: 51.1444,
            source_name: "XCOM Aktau",
            source_url: "https://xcom.kz/cam/",
            catalog_url: catalogueURL,
            stream_list_url: streamListURL,
            verification_note: "XCOM обозначает камеру как онлайн; доступность HLS проверяется в приложении.",
            verified: false
        ),
        CameraCandidate(
            id: "aktau-caspian-14",
            name: "Актау — Каспий, 14-й микрорайон",
            url: "https://cam.xcom.kz:8081/caspy14/tracks-v1/mono.m3u8",
            lat: 43.6545,
            lon: 51.1385,
            source_name: "XCOM Aktau",
            source_url: sourceURL,
            catalog_url: catalogueURL,
            stream_list_url: streamListURL,
            verification_note: "Публичная ссылка HLS. Доступность сейчас и разрешение на AI-анализ не подтверждены.",
            verified: false
        ),
        CameraCandidate(
            id: "aktau-caspian-15",
            name: "Актау — Каспий, 15-й микрорайон",
            url: "https://cam.xcom.kz:8081/caspy15/tracks-v1/mono.m3u8",
            lat: 43.6560,
            lon: 51.1375,
            source_name: "XCOM Aktau",
            source_url: sourceURL,
            catalog_url: catalogueURL,
            stream_list_url: streamListURL,
            verification_note: "Публичная ссылка HLS. Доступность сейчас и разрешение на AI-анализ не подтверждены.",
            verified: false
        ),
        CameraCandidate(
            id: "aktau-yntymak",
            name: "Актау — площадь Ынтымак",
            url: "https://cam.xcom.kz:8081/yntymak/tracks-v1/mono.m3u8",
            lat: 43.6445,
            lon: 51.1530,
            source_name: "XCOM Aktau",
            source_url: sourceURL,
            catalog_url: catalogueURL,
            stream_list_url: streamListURL,
            verification_note: "XCOM обозначает площадь Ынтымак как онлайн; фактический HLS проверяется в приложении.",
            verified: false
        ),
        CameraCandidate(
            id: "aktau-drama",
            name: "Актау — драматический театр",
            url: "https://cam.xcom.kz:8081/dramteatr/tracks-v1/mono.m3u8",
            lat: 43.6397,
            lon: 51.1521,
            source_name: "XCOM Aktau",
            source_url: sourceURL,
            catalog_url: catalogueURL,
            stream_list_url: streamListURL,
            verification_note: "Публичная ссылка HLS. Доступность сейчас и разрешение на AI-анализ не подтверждены.",
            verified: false
        ),
        CameraCandidate(
            id: "aktau-13-microdistrict",
            name: "Актау — 13-й микрорайон",
            url: "https://cam.xcom.kz:8081/13-1/tracks-v1/index.m3u8",
            lat: 43.6315,
            lon: 51.1595,
            source_name: "XCOM Aktau",
            source_url: sourceURL,
            catalog_url: catalogueURL,
            stream_list_url: streamListURL,
            verification_note: "Публичная ссылка HLS. Доступность сейчас и разрешение на AI-анализ не подтверждены.",
            verified: false
        )
    ]
}
