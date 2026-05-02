import SwiftUI

/// Single speaker's data point on the radar — five values in 0...1 in the
/// canonical order: Talk Time, Dominance, Confidence, Questions, Interruptions.
struct RadarSpeaker: Identifiable {
    let id: Int
    let label: String
    let color: Color
    let values: [Double] // 5 elements
}

/// 5-axis radar chart drawn in a SwiftUI Canvas with grid + speaker polygons.
struct RadarChart: View {
    static let axisLabels = ["Talk Time", "Dominance", "Confidence", "Questions", "Interruptions"]
    let speakers: [RadarSpeaker]

    @State private var animationProgress: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    Canvas { ctx, _ in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let radius = size / 2 - 36 // padding for axis labels
                        let n = Self.axisLabels.count

                        // Concentric grid rings (20 / 40 / 60 / 80 / 100%).
                        for level in stride(from: 0.2, through: 1.0, by: 0.2) {
                            let path = Self.polygonPath(
                                center: center,
                                radius: radius * level,
                                sides: n
                            )
                            ctx.stroke(path, with: .color(.gray.opacity(level == 1.0 ? 0.5 : 0.25)), lineWidth: 0.5)
                        }

                        // Axis spokes.
                        for i in 0 ..< n {
                            let angle = Self.angle(forAxis: i, sides: n)
                            let end = CGPoint(
                                x: center.x + Darwin.cos(angle) * radius,
                                y: center.y + Darwin.sin(angle) * radius
                            )
                            var spoke = Path()
                            spoke.move(to: center)
                            spoke.addLine(to: end)
                            ctx.stroke(spoke, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
                        }

                        // Speaker polygons.
                        for speaker in speakers {
                            let path = Self.speakerPath(
                                values: speaker.values,
                                center: center,
                                radius: radius,
                                progress: animationProgress
                            )
                            ctx.fill(path, with: .color(speaker.color.opacity(0.15)))
                            ctx.stroke(path, with: .color(speaker.color), lineWidth: 1.5)
                        }
                    }
                    .frame(width: size, height: size)

                    // External axis labels.
                    ForEach(Array(Self.axisLabels.enumerated()), id: \.offset) { idx, label in
                        let angle = Self.angle(forAxis: idx, sides: Self.axisLabels.count)
                        let radius = size / 2 - 16
                        let x = size / 2 + Darwin.cos(angle) * radius
                        let y = size / 2 + Darwin.sin(angle) * radius
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .position(x: x, y: y)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            .aspectRatio(1, contentMode: .fit)

            // Legend.
            FlexibleHStack(spacing: 12) {
                ForEach(speakers) { speaker in
                    HStack(spacing: 6) {
                        Circle().fill(speaker.color).frame(width: 8, height: 8)
                        Text(speaker.label).font(.caption)
                    }
                }
            }
        }
        .onAppear {
            animationProgress = 0
            withAnimation(.easeInOut(duration: 0.6)) { animationProgress = 1 }
        }
    }

    // MARK: - Geometry

    private static func angle(forAxis i: Int, sides: Int) -> Double {
        -.pi / 2 + Double(i) * 2 * .pi / Double(sides)
    }

    private static func polygonPath(center: CGPoint, radius: CGFloat, sides: Int) -> Path {
        var path = Path()
        for i in 0 ..< sides {
            let angle = angle(forAxis: i, sides: sides)
            let p = CGPoint(x: center.x + Darwin.cos(angle) * radius, y: center.y + Darwin.sin(angle) * radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func speakerPath(
        values: [Double],
        center: CGPoint,
        radius: CGFloat,
        progress: Double
    ) -> Path {
        var path = Path()
        let n = values.count
        for i in 0 ..< n {
            let v = max(0, min(1, values[i])) * progress
            let angle = angle(forAxis: i, sides: n)
            let p = CGPoint(
                x: center.x + Darwin.cos(angle) * radius * v,
                y: center.y + Darwin.sin(angle) * radius * v
            )
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// Tiny wrap-around HStack for legends (no UIKit collection view needed).
struct FlexibleHStack<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content
    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    var body: some View {
        HStack(spacing: spacing) { content }
    }
}
