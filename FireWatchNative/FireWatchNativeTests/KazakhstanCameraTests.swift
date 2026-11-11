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

    @MainActor
    func testNewCityRefreshWinsOverAnOlderProbe() async throws {
        let camera = try XCTUnwrap(PublicCameraCatalog.candidates.first)
        let availability = KazakhstanCameraAvailability()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let oldRefresh = Task {
            await availability.refresh([camera]) { _ in
                started.continuation.finish()
                for await _ in release.stream {}
                return .unavailable
            }
        }
        for await _ in started.stream {}
        XCTAssertEqual(availability.status(for: camera.id), .checking)
        await availability.refresh([camera]) { _ in .playlistAvailable }
        release.continuation.finish()
        await oldRefresh.value
        XCTAssertFalse(availability.checking)
        XCTAssertEqual(availability.status(for: camera.id), .playlistAvailable)
    }

    @MainActor
    func testCancelledProbeRestoresPreviousStatus() async throws {
        let camera = try XCTUnwrap(PublicCameraCatalog.candidates.first)
        let availability = KazakhstanCameraAvailability()
        await availability.refresh([camera]) { _ in .playlistAvailable }
        let started = AsyncStream<Void>.makeStream()
        let refresh = Task {
            await availability.refresh([camera]) { _ in
                started.continuation.finish()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return .unavailable
            }
        }
        for await _ in started.stream {}
        refresh.cancel()
        await refresh.value
        XCTAssertFalse(availability.checking)
        XCTAssertEqual(availability.status(for: camera.id), .playlistAvailable)
    }

    func testCoreMLClassMappingUsesActualCheckpointOrder() {
        let reverse = ["0": "smoke", "1": "fire"]
        XCTAssertEqual(OnDeviceFireDetector.resolvedLabel("0", labelsByID: reverse), "smoke")
        XCTAssertEqual(OnDeviceFireDetector.resolvedLabel("1", labelsByID: reverse), "fire")
        XCTAssertEqual(OnDeviceFireDetector.resolvedLabel("fire", labelsByID: [:]), "fire")
        XCTAssertNil(OnDeviceFireDetector.resolvedLabel("0", labelsByID: [:]))
        XCTAssertNil(OnDeviceFireDetector.resolvedLabel("2", labelsByID: reverse))
    }

    func testAstanaPrioritizesUserSuppliedOfficialCameraPage() {
        let astana = KazakhstanPublisherCameras.candidates.filter { $0.cityID == "astana" }
        XCTAssertGreaterThanOrEqual(astana.count, 3)
        XCTAssertEqual(astana.first?.id, "astana-khan-shatyr-publisher")
        XCTAssertEqual(astana.first?.pageURL.absoluteString,
                       "https://www.khanshatyr.com/ru/camera")
        XCTAssertNil(astana.first?.youtubeVideoID, "A publisher page is not a direct HLS feed")
        XCTAssertTrue(astana.contains {
            $0.id == "astana-atameken-city-2026" && $0.youtubeVideoID == "sR4YuJ-6UO4"
        })
        XCTAssertTrue(astana.contains { $0.id == "astana-atameken-live" })
    }

    func testAstanaFilterIncludesBothDirectKhanShatyrFeeds() {
        let feeds = PublicCameraCatalog.candidates.filter { $0.catalogCityID == "astana" }
        XCTAssertEqual(Set(feeds.map(\.url)), [
            "https://shatyr-stream.smarty.kz/cam1/index.m3u8?cookieCheck=1",
            "https://shatyr-stream.smarty.kz/cam2/index.m3u8?cookieCheck=1"
        ])
        let cityIDs = Set(KazakhstanCities.all.map(\.id))
        XCTAssertTrue(PublicCameraCatalog.candidates.allSatisfy { cityIDs.contains($0.catalogCityID) })
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
