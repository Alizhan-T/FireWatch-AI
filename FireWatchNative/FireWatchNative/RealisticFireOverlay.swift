import SwiftUI
import UIKit
import ImageIO

/// Draw in the visible picture area. Positions specify the fuel bed on the ground.
struct RealisticFireOverlay: View {
    var horizontalPosition: CGFloat = 0.60
    var verticalPosition: CGFloat = 0.92
    var scale: CGFloat = 0.82

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height * scale
            FirePlumeSprite(animate: !reduceMotion && scenePhase == .active)
                .frame(width: height * 176 / 224, height: height)
                // The ground contact is at row 207 in each 224-pixel frame.
                .position(x: geometry.size.width * horizontalPosition,
                          y: geometry.size.height * verticalPosition - height * (207.0 / 224 - 0.5))
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One transparent texture shared by all training screens. Core Animation changes
/// the visible tile, so neither the plume simulation nor image decoding runs per tick.
struct FirePlumeSprite: UIViewRepresentable {
    let animate: Bool
    private static let columns = 12
    private static let rows = 8
    private static let fps = 24
    private static let animationKey = "trainingPlume"
    static let texture: CGImage? = {
        guard let url = Bundle.main.url(forResource: "DemoFirePlume", withExtension: "webp"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }()

    static let tiles: [NSValue] = (0..<(columns * rows)).map { index in
        NSValue(cgRect: CGRect(x: CGFloat(index % columns) / CGFloat(columns),
                               y: CGFloat(index / columns) / CGFloat(rows),
                               width: 1 / CGFloat(columns), height: 1 / CGFloat(rows)))
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.layer.contents = Self.texture
        view.layer.contentsGravity = .resize
        view.layer.contentsRect = Self.tiles[0].cgRectValue
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let layer = view.layer
        guard animate else {
            layer.removeAnimation(forKey: Self.animationKey)
            return
        }
        guard layer.animation(forKey: Self.animationKey) == nil else { return }
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        animation.values = Self.tiles
        animation.calculationMode = .discrete
        animation.duration = Double(Self.tiles.count) / Double(Self.fps)
        animation.repeatCount = .infinity
        layer.add(animation, forKey: Self.animationKey)
    }
}
