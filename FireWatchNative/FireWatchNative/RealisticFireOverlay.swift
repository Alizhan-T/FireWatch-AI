import SwiftUI

/// Camera-backed training VFX, never a result from AI or a real camera event.
/// Animated organic plumes replace SF Symbols; drawing stays local to the iPhone.
struct RealisticFireOverlay: View {
    var intensity: Double = 0.86

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                render(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: 220, height: 234)
        .allowsHitTesting(false)
        .accessibilityLabel("Реалистичный искусственный огонь и дым — учебная симуляция")
    }

    private func render(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let baseY = size.height * 0.95
        let centerX = size.width * 0.57
        let pulse = 0.87 + 0.13 * sin(time * 10.7) + 0.05 * sin(time * 17.1)

        // Diffuse firelight softly illuminates the camera pixels around the source.
        var reflectedLight = context
        reflectedLight.addFilter(.blur(radius: 23))
        let glow = Path(ellipseIn: CGRect(
            x: centerX - 82, y: baseY - 87, width: 164, height: 110
        ))
        reflectedLight.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.37, blue: 0.12).opacity(0.37 * intensity * pulse),
                    Color(red: 0.72, green: 0.14, blue: 0.05).opacity(0.14 * intensity),
                    .clear
                ]),
                center: CGPoint(x: centerX, y: baseY - 28),
                startRadius: 4,
                endRadius: 98
            )
        )

        // Smoke drifts and expands rather than bouncing like cartoon clouds.
        var smoke = context
        smoke.addFilter(.blur(radius: 14))
        for index in 0..<21 {
            let phase = Double(index) * 0.137
            let age = (time * (0.075 + Double(index % 3) * 0.011) + phase)
                .truncatingRemainder(dividingBy: 1)
            let drift = sin(time * 0.63 + Double(index) * 1.29) * 19
            let x = centerX + CGFloat(drift) - CGFloat(age * 28)
            let y = baseY - 38 - CGFloat(age) * size.height * 0.96
            let width = CGFloat(18 + 59 * age + Double(index % 4) * 6)
            let height = width * CGFloat(0.65 + 0.15 * sin(Double(index)))
            let opacity = max(0, (1 - age) * min(1, age * 5 + 0.10)) * 0.24 * intensity
            let shade = 0.17 + 0.18 * age + 0.025 * Double(index % 3)
            let puff = Path(ellipseIn: CGRect(
                x: x - width / 2, y: y - height / 2, width: width, height: height
            ))
            smoke.fill(
                puff,
                with: .color(Color(red: shade, green: shade, blue: shade + 0.015)
                    .opacity(opacity))
            )
        }

        // Warm blurred flame silhouettes, each with its own turbulent motion.
        var softFlames = context
        softFlames.addFilter(.blur(radius: 8))
        for index in 0..<9 {
            let flicker = sin(time * (7.3 + Double(index) * 0.59) + Double(index) * 2.4)
            let lean = sin(time * 2.1 + Double(index) * 1.7)
            let offsetX = CGFloat(index - 4) * 15
            let x = centerX + offsetX
            let height = CGFloat(64 + (index % 4) * 17) * CGFloat(0.83 + 0.20 * flicker)
            let width = CGFloat(18 + (index % 3) * 10)
            let tip = CGPoint(x: x + CGFloat(lean) * 14, y: baseY - height)
            let outline = flameShape(base: CGPoint(x: x, y: baseY),
                                     tip: tip, width: width, bend: CGFloat(lean) * 9)
            softFlames.fill(
                outline,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.65, green: 0.10, blue: 0.03).opacity(0.04), location: 0),
                        .init(color: Color(red: 0.93, green: 0.27, blue: 0.06).opacity(0.47 * intensity), location: 0.38),
                        .init(color: Color(red: 1, green: 0.64, blue: 0.14).opacity(0.74 * intensity), location: 0.86),
                        .init(color: Color(red: 1, green: 0.86, blue: 0.38).opacity(0.42 * intensity), location: 1)
                    ]),
                    startPoint: tip,
                    endPoint: CGPoint(x: x, y: baseY)
                )
            )
        }

        // Smaller, sharper hot cores make the flame appear textured, not an icon.
        for index in 0..<12 {
            let flicker = sin(time * (9.0 + Double(index % 5)) + Double(index) * 3.7)
            let sway = sin(time * 3.3 + Double(index)) * 7
            let x = centerX + CGFloat(index - 6) * 10
            let h = CGFloat(25 + (index % 5) * 11) * CGFloat(0.76 + 0.24 * flicker)
            let tip = CGPoint(x: x + CGFloat(sway), y: baseY - h)
            let shape = flameShape(base: CGPoint(x: x, y: baseY),
                                   tip: tip, width: CGFloat(9 + index % 3 * 3),
                                   bend: CGFloat(sway * 0.5))
            context.fill(
                shape,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 1, green: 0.37, blue: 0.06).opacity(0.12),
                        Color(red: 1, green: 0.67, blue: 0.15).opacity(0.68 * intensity),
                        Color(red: 1, green: 0.92, blue: 0.58).opacity(0.88 * intensity)
                    ]),
                    startPoint: tip,
                    endPoint: CGPoint(x: x, y: baseY)
                )
            )
        }

        // Individual embers rise at different speeds and fade before reaching the smoke.
        for index in 0..<12 {
            let phase = Double(index) * 0.31
            let age = (time * (0.19 + 0.016 * Double(index % 3)) + phase)
                .truncatingRemainder(dividingBy: 1)
            let x = centerX + CGFloat(sin(Double(index) * 2.1 + time * 1.4) * 42)
            let y = baseY - 28 - CGFloat(age) * 138
            let diameter = CGFloat(1.1 + Double(index % 3) * 0.6)
            let dot = Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter))
            context.fill(dot, with: .color(Color(red: 1, green: 0.65, blue: 0.23)
                .opacity((1 - age) * 0.8 * intensity)))
        }
    }

    private func flameShape(base: CGPoint, tip: CGPoint, width: CGFloat, bend: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: base.x - width, y: base.y))
        path.addCurve(to: tip,
                      control1: CGPoint(x: base.x - width * 0.86 + bend, y: base.y - (base.y - tip.y) * 0.37),
                      control2: CGPoint(x: tip.x - width * 0.36, y: tip.y + (base.y - tip.y) * 0.25))
        path.addCurve(to: CGPoint(x: base.x + width, y: base.y),
                      control1: CGPoint(x: tip.x + width * 0.75, y: tip.y + (base.y - tip.y) * 0.35),
                      control2: CGPoint(x: base.x + width * 0.35 + bend, y: base.y - (base.y - tip.y) * 0.25))
        path.closeSubpath()
        return path
    }
}
