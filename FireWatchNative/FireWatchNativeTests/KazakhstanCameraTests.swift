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

    func testBundledCamerasAreKazakhstanOnlyHTTPSHLS() {
        let candidates = PublicCameraCatalog.candidates
        XCTAssertGreaterThanOrEqual(candidates.count, 8)
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
