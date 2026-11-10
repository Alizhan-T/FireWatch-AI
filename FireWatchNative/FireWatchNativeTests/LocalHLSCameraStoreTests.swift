import Foundation
import XCTest
@testable import FireWatchNative

/// Regression coverage for standalone mode: this must work without FastAPI.
final class LocalHLSCameraStoreTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "firewatch-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testSavedLinksSurviveStoreRecreation() async throws {
        try await MainActor.run {
            let (defaults, suite) = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }
            let first = LocalHLSCameraStore(defaults: defaults)
            XCTAssertNoThrow(try first.add(name: "  Coast  ", streamURL: " https://example.com/live.m3u8?token=abc "))
            XCTAssertEqual(first.cameras.count, 1)
            XCTAssertEqual(first.cameras[0].name, "Coast")

            let second = LocalHLSCameraStore(defaults: defaults)
            XCTAssertEqual(second.cameras, first.cameras)
            second.remove(second.cameras[0])
            XCTAssertTrue(LocalHLSCameraStore(defaults: defaults).cameras.isEmpty)
        }
    }

    func testBadProtocolsAndNonHLSFilesAreRejected() async throws {
        try await MainActor.run {
            let (defaults, suite) = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LocalHLSCameraStore(defaults: defaults)
            let badURLs = [
                "rtsp://example.com/stream",
                "file:///tmp/local.m3u8",
                "https://example.com/stream.mp4",
                "https://example.com/",
                "not-a-valid-url"
            ]
            for url in badURLs {
                XCTAssertThrowsError(try store.add(name: "Test", streamURL: url), url)
            }
            XCTAssertThrowsError(try store.add(name: " ", streamURL: "https://example.com/a.m3u8"))
            XCTAssertTrue(store.cameras.isEmpty)
        }
    }

    func testDuplicateIsRejectedWithoutErasingOriginal() async throws {
        try await MainActor.run {
            let (defaults, suite) = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = LocalHLSCameraStore(defaults: defaults)
            let url = "https://example.com/live.m3u8"
            XCTAssertNoThrow(try store.add(name: "First", streamURL: url))
            XCTAssertThrowsError(try store.add(name: "Second", streamURL: url))
            XCTAssertEqual(store.cameras.map(\.name), ["First"])
        }
    }
}
