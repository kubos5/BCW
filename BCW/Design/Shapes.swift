import SwiftUI

// MARK: - Tracciati SVG

/// Lettore minimo di tracciati SVG (comandi M, L, H, V, C, S, Q, T, Z, assoluti e relativi):
/// serve per le forme di Material 3 Expressive, scritte come nella versione web.
enum SVGPath {
    static func parse(_ string: String) -> Path {
        var path = Path()
        var scanner = Tokens(string)
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?

        while let next = scanner.nextCommandOrNumber() {
            if case .command(let c) = next {
                command = c
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = start
                    lastControl = nil
                    continue
                }
            } else {
                scanner.rewind()
            }
            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command.uppercased() {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
                lastControl = nil
                // I punti successivi di un "M" sono linee.
                command = relative ? "l" : "L"
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                lastControl = c2
                current = p
            case "S":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                lastControl = c2
                current = p
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                lastControl = c
                current = p
            case "T":
                let c = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                lastControl = c
                current = p
            default:
                return path
            }
        }
        return path
    }

    private struct Tokens {
        enum Token { case command(Character), number(CGFloat) }
        let chars: [Character]
        var index = 0
        var previous = 0

        init(_ string: String) { chars = Array(string) }

        mutating func skip() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" { index += 1 }
        }

        mutating func nextCommandOrNumber() -> Token? {
            skip()
            previous = index
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter && c != "e" && c != "E" {
                index += 1
                return .command(c)
            }
            return number().map { .number($0) }
        }

        mutating func rewind() { index = previous }

        mutating func number() -> CGFloat? {
            skip()
            let begin = index
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
            var seenDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    index += 1
                } else if c == ".", !seenDot {
                    seenDot = true
                    index += 1
                } else if c == "e" || c == "E" {
                    index += 1
                    if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
                } else {
                    break
                }
            }
            guard index > begin else { return nil }
            return Double(String(chars[begin..<index])).map { CGFloat($0) }
        }
    }
}

// MARK: - Forme di Material 3 Expressive

/// Una forma di Material 3 Expressive (biscotto, trifoglio, sole…) adattata al riquadro.
struct MaterialShape: Shape {
    var name: MaterialShapeName

    init(_ name: MaterialShapeName) { self.name = name }

    private static var cache: [MaterialShapeName: Path] = [:]

    static func unitPath(_ name: MaterialShapeName) -> Path {
        if let path = cache[name] { return path }
        let path = SVGPath.parse(name.svg)
        cache[name] = path
        return path
    }

    func path(in rect: CGRect) -> Path {
        Self.unitPath(name).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / 100, y: rect.height / 100))
    }
}

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
