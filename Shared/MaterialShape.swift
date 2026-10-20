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
