import SwiftUI

/// Non-interactive training visualization ONLY. This does not inspect video frames,
/// run Vision/Core ML or indicate real fire/smoke detections.
struct DemoScannerOverlay: View {
    var title: String = "SCAN · DEMO"

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let cycle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3.4) / 3.4
                let y = max(18, geometry.size.height * CGFloat(0.1 + cycle * 0.8))
                ZStack {
                    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                        let green = Color(red: 0.26, green: 1.0, blue: 0.51)

                        // Thin translucent scan band + brighter leading edge.
                        let band = Path(CGRect(x: 0, y: max(0, y - 25),
                                               width: size.width, height: 29))
                        context.fill(
                            band,
                            with: .linearGradient(
                                Gradient(colors: [.clear, green.opacity(0.035),
                                                  green.opacity(0.18), green.opacity(0.04)]),
                                startPoint: CGPoint(x: 0, y: y - 25),
                                endPoint: CGPoint(x: 0, y: y + 4)
                            )
                        )

                        var line = Path()
                        line.move(to: CGPoint(x: 8, y: y))
                        line.addLine(to: CGPoint(x: size.width - 8, y: y))
                        context.stroke(line, with: .color(green.opacity(0.88)), lineWidth: 1.3)

                        // Geometric corner guides, not claimed model boxes.
                        var corners = Path()
                        let margin: CGFloat = 13
                        let leg: CGFloat = min(23, size.width * 0.09)
                        let left = margin, right = size.width - margin
                        let top = margin, bottom = size.height - margin
                        corners.move(to: CGPoint(x: left, y: top + leg))
                        corners.addLine(to: CGPoint(x: left, y: top))
                        corners.addLine(to: CGPoint(x: left + leg, y: top))
                        corners.move(to: CGPoint(x: right - leg, y: top))
                        corners.addLine(to: CGPoint(x: right, y: top))
                        corners.addLine(to: CGPoint(x: right, y: top + leg))
                        corners.move(to: CGPoint(x: left, y: bottom - leg))
                        corners.addLine(to: CGPoint(x: left, y: bottom))
                        corners.addLine(to: CGPoint(x: left + leg, y: bottom))
                        corners.move(to: CGPoint(x: right - leg, y: bottom))
                        corners.addLine(to: CGPoint(x: right, y: bottom))
                        corners.addLine(to: CGPoint(x: right, y: bottom - leg))
                        context.stroke(corners, with: .color(green.opacity(0.8)), lineWidth: 1.2)
                    }
                    VStack(alignment: .trailing) {
                        HStack {
                            Spacer()
                            Text(title)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.72), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        HStack {
                            Text("ВИЗУАЛИЗАЦИЯ • БЕЗ АНАЛИЗА КАДРОВ")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                                .padding(5)
                                .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 5))
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Учебная движущаяся зелёная линия; реальный AI-анализ камеры не выполняется")
    }
}

/// Clearly artificial fallback for a publisher page that exposes no permitted
/// video stream. Never show VFX over the publisher's navigation or player controls.
struct DemoTrainingBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(red: 0.09, green: 0.16, blue: 0.19), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            Canvas { context, size in
                var grid = Path()
                let step: CGFloat = 25
                var x: CGFloat = 0
                while x < size.width {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(grid, with: .color(.green.opacity(0.045)), lineWidth: 0.5)
            }
            VStack(spacing: 7) {
                Image(systemName: "rectangle.on.rectangle.slash")
                    .foregroundStyle(.white.opacity(0.5))
                Text("СИНТЕТИЧЕСКАЯ УЧЕБНАЯ СЦЕНА")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text("Кадры сайта камеры не получены")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.72))
            .multilineTextAlignment(.center)
            .padding()
        }
        .accessibilityLabel("Учебный фон, не изображение реальной камеры")
    }
}


/// Dedicated synthetic preview for publisher pages whose camera frames
/// are unavailable to FireWatch. Never overlays the real publisher webpage.
struct DemoTrainingStage: View {
    var body: some View {
        DemoTrainingBackdrop()
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .overlay {
                GeometryReader { geometry in
                    RealisticFireOverlay()
                        .scaleEffect(0.65)
                        .position(x: geometry.size.width * 0.6,
                                  y: geometry.size.height - 15 - 117 * 0.65)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                DemoScannerOverlay()
            }
            .overlay(alignment: .topLeading) {
                Text("DEMO • ОГОНЬ И ДЫМ")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.red.opacity(0.9), in: Capsule())
                    .padding(10)
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("Учебная симуляция огня, дыма и зелёной линии, не кадры реальной камеры")
    }
}
