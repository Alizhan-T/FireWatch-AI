import XCTest
import UIKit
@testable import FireWatchNative

final class FirePlumeTests: XCTestCase {
    @MainActor
    func testBundledPlumeFramesAreVisibleDistinctAndTransparent() throws {
        let atlas = try XCTUnwrap(FirePlumeSprite.texture)
        let tiles = FirePlumeSprite.tiles
        XCTAssertEqual(tiles.count, 96)
        let atlasSize = CGAffineTransform(scaleX: CGFloat(atlas.width), y: CGFloat(atlas.height))
        func pixels(in index: Int) throws -> [UInt8] {
            let rect = tiles[index].cgRectValue.applying(atlasSize)
            let tile = try XCTUnwrap(atlas.cropping(to: rect))
            XCTAssertEqual(tile.width, 176)
            XCTAssertEqual(tile.height, 224)
            let width = 44, height = 56
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let bitmap = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                bitmap.draw(tile, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return bytes
        }
        let first = try pixels(in: 0)
        let alpha = stride(from: 3, to: first.count, by: 4).map { first[$0] }
        XCTAssertTrue(alpha.contains(0))
        XCTAssertTrue(alpha.contains { $0 > 180 })
        XCTAssertNotEqual(first, try pixels(in: 36))
        XCTAssertNotEqual(first, try pixels(in: tiles.count - 1))
    }
}
