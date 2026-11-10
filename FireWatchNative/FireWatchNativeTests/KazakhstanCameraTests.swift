import Foundation
import XCTest
@testable import FireWatchNative

final class KazakhstanCameraTests: XCTestCase {
    func testManifestParserAcceptsHLSAndRejectsHTML() {
        XCTAssertTrue(HLSManifestProbe.looksLikePlaylist(
            Data("#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:2.0,\nsegment.ts".utf8)
        ))
        XCTAssertFalse(HLSManifestProbe.looksLikePlaylist(
            Data("<html><body>403 Forbidden</body></html>".utf8)
        ))
        XCTAssertFalse(HLSManifestProbe.looksLikePlaylist(Data()))
    }

    func testCoreMLClassMappingUsesActualCheckpointOrder() {
        let reverse = ["0": "smoke", "1": "fire"]
        XCTAssertEqual(OnDeviceFireDetector.resolvedLabel("0", labelsByID: reverse), "smoke")
        XCTAssertEqual(OnDeviceFireDetector.resolvedLabel("1", labelsByID: reverse), "fire")
        XCTAssertEqual(OnDeviceFireDetector.resolvedLabel("fire", labelsByID: [:]), "fire")
        XCTAssertNil(OnDeviceFireDetector.resolvedLabel("0", labelsByID: [:]))
        XCTAssertNil(OnDeviceFireDetector.resolvedLabel("2", labelsByID: reverse))
    }

    func testAstanaUsesNewerPublishedCityStreamFirstAndRetainsBackup() {
        let astana = KazakhstanPublisherCameras.candidates.filter { $0.cityID == "astana" }
        XCTAssertGreaterThanOrEqual(astana.count, 3)
        XCTAssertEqual(astana.first?.id, "astana-atameken-city-2026")
        XCTAssertEqual(astana.first?.youtubeVideoID, "sR4YuJ-6UO4")
        XCTAssertEqual(astana.first?.pageURL.host, "www.youtube.com")
        XCTAssertTrue(astana.contains { $0.id == "astana-atameken-live" })
        XCTAssertTrue(astana.contains { $0.id == "astana-khan-shatyr-publisher" })
    }

    func testAstanaPublisherFallbackDoesNotMasqueradeAsHLS() {
        let cameras = KazakhstanPublisherCameras.candidates.filter { $0.cityID == "astana" }
        XCTAssertGreaterThanOrEqual(cameras.count, 2)
        XCTAssertTrue(cameras.contains { $0.id == "astana-khan-shatyr-publisher" })
        XCTAssertTrue(cameras.contains { $0.youtubeVideoID != nil })
        for camera in cameras {
            XCTAssertEqual(camera.pageURL.scheme, "https")
            XCTAssertFalse(camera.pageURL.pathExtension.lowercased() == "m3u8")
            XCTAssertFalse(camera.reliabilityNote.isEmpty)
        }
    }

    func testBundledCamerasAreKazakhstanOnlyHTTPSHLS() {
        let candidates = PublicCameraCatalog.candidates
        XCTAssertGreaterThanOrEqual(candidates.count, 7)
        XCTAssertEqual(Set(candidates.map(\.id)).count, candidates.count)
        for camera in candidates {
            let url = URL(string: camera.url)
            XCTAssertEqual(url?.scheme, "https", camera.name)
            XCTAssertEqual(url?.pathExtension.lowercased(), "m3u8", camera.name)
            XCTAssertTrue(camera.lat >= 42 && camera.lat <= 56, camera.name)
            XCTAssertTrue(camera.lon >= 46 && camera.lon <= 88, camera.name)
            XCTAssertFalse(camera.verified, "Catalogue entries must not pretend to be field-verified")
        }
    }
}
