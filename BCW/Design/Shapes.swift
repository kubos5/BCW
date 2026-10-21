import SwiftUI

// Tracciati SVG e forme di Material 3 Expressive: `Shared/MaterialShape.swift` (usati anche dai widget).

/// Contenuto al centro di una forma piena (come `.shaped` nella versione web).
struct Shaped<Content: View>: View {
    var shape: MaterialShapeName
    var fill: Color
    var size: CGFloat
    var rotation: Angle = .zero
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            MaterialShape(shape)
                .fill(fill)
                .rotationEffect(rotation)
            content()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Indicatore di caricamento

/// Indicatore di caricamento di M3 Expressive: una forma che si trasforma e ruota.
struct LoadingIndicator: View {
    var size: CGFloat = 48
    /// Con il contenitore (cerchio nel colore del contenitore primario).
    var contained = false
    var color: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * (slow ? 0.5 : 1)
            let morph = Self.morphShape(at: t)
            let spin = Self.spin(at: t)
            let turn = (t.truncatingRemainder(dividingBy: 4.666) / 4.666) * 360
            ZStack {
                if contained {
                    Circle().fill(Theme.primaryContainer)
                }
                PolygonShape(points: morph)
                    .fill(color ?? (contained ? Theme.onPrimaryContainer : Theme.primary))
                    .frame(width: size * (contained ? 0.62 : 0.79), height: size * (contained ? 0.62 : 0.79))
                    .rotationEffect(.degrees(spin))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turn))
        }
        .accessibilityElement()
        .accessibilityLabel("Caricamento")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var slow: Bool { reduceMotion || ThemeStore.shared.motion == .reduced }

    /// Curva a molla dei passaggi (la `linear()` di `css/bcw.css`).
    private static let spring: [Double] = [0, 0.024, 0.087, 0.177, 0.283, 0.396, 0.51, 0.619, 0.719, 0.808, 0.884, 0.948, 0.998,
                                            1.036, 1.064, 1.082, 1.092, 1.095, 1.093, 1.087, 1.079, 1.069, 1.058, 1.047, 1.037,
                                            1.027, 1.019, 1.012, 1.005, 1.001, 0.997, 0.994, 0.992, 0.991, 0.991, 0.991, 0.992,
                                            0.992, 0.993, 0.994, 1]

    private static func ease(_ p: Double) -> Double {
        let x = min(max(p, 0), 1) * Double(spring.count - 1)
        let i = Int(x)
        guard i < spring.count - 1 else { return 1 }
        return spring[i] + (spring[i + 1] - spring[i]) * (x - Double(i))
    }

    private static func morphShape(at t: Double) -> [CGPoint] {
        let frames = LoadingIndicatorFrames.frames
        let segments = frames.count - 1
        let duration = 4.55 / Double(segments)
        let position = t.truncatingRemainder(dividingBy: 4.55) / duration
        let index = min(Int(position), segments - 1)
        let p = ease(position - Double(index))
        let a = frames[index], b = frames[index + 1]
        return zip(a, b).map { CGPoint(x: $0.x + ($1.x - $0.x) * p, y: $0.y + ($1.y - $0.y) * p) }
    }

    private static func spin(at t: Double) -> Double {
        let position = t.truncatingRemainder(dividingBy: 2.6) / 0.65
        let quarter = Int(position)
        return Double(quarter) * 90 + ease(position - Double(quarter)) * 90
    }
}

/// Poligono da punti in frazioni del riquadro.
struct PolygonShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}
