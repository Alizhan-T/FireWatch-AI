import Foundation
import XCTest
@testable import FireWatchNative

final class ServerConfigurationTests: XCTestCase {
    func testAppBundleIncludesLocalNetworkConfiguration() throws {
        let info = try XCTUnwrap(Bundle(for: API.self).infoDictionary)
        let description = try XCTUnwrap(info["NSLocalNetworkUsageDescription"] as? String)
        XCTAssertFalse(description.isEmpty)
        let settings = try XCTUnwrap(info["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(settings["NSAllowsLocalNetworking"] as? Bool, true)
    }
}
