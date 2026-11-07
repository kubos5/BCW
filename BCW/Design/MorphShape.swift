import SwiftUI

/// Forma di Material 3 Expressive che si trasforma in un'altra con un'animazione (la morfologia delle
/// forme di M3 Expressive): ogni forma è campionata nello stesso numero di punti, nello stesso verso e
/// a partire dallo stesso lato, e l'animazione interpola i punti. Cambiando forma a metà animazione si
/// riparte da dove si è, senza salti.
struct MorphShape: Shape {
    var points: MorphPoints

    init(_ name: MaterialShapeName) {
        points = MorphPoints.of(name)
    }

    var animatableData: MorphPoints {
        get { points }
        set { points = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let values = points.values
        guard values.count >= 6 else { return path }
        let scale = min(rect.width, rect.height)
        let x = rect.midX - scale / 2, y = rect.midY - scale / 2
        path.move(to: CGPoint(x: x + values[0] * scale, y: y + values[1] * scale))
        var index = 2
        while index + 1 < values.count {
            path.addLine(to: CGPoint(x: x + values[index] * scale, y: y + values[index + 1] * scale))
            index += 2
        }
        path.closeSubpath()
        return path
    }
}

/// I punti di una forma come vettore animabile (x e y alternati, da 0 a 1).
struct MorphPoints: VectorArithmetic {
    var values: [CGFloat]

    private static let count = 180
    private static var cache: [MaterialShapeName: MorphPoints] = [:]

    static func of(_ name: MaterialShapeName) -> MorphPoints {
        if let cached = cache[name] { return cached }
        let points = sample(MaterialShape.unitPath(name))
        cache[name] = points
        return points
    }

    /// Punti alla stessa distanza lungo il contorno, in senso orario, dal punto più in alto al centro.
    private static func sample(_ path: Path) -> MorphPoints {
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let t = CGFloat(index + 1) / CGFloat(count)
            if let point = path.trimmedPath(from: 0, to: t).currentPoint {
                points.append(CGPoint(x: point.x / 100, y: point.y / 100))
            }
        }
        guard points.count == count else { return MorphPoints(values: []) }
        // Stesso verso per tutte (area con segno).
        var area: CGFloat = 0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        if area < 0 { points.reverse() }
        // Stesso punto di partenza: quello più vicino alla verticale sopra il centro.
        let center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(count),
                             y: points.map(\.y).reduce(0, +) / CGFloat(count))
        let start = points.indices.min { a, b in
            angleFromTop(points[a], center) < angleFromTop(points[b], center)
        } ?? 0
        let ordered = points[start...] + points[..<start]
        return MorphPoints(values: ordered.flatMap { [$0.x, $0.y] })
    }

    private static func angleFromTop(_ point: CGPoint, _ center: CGPoint) -> CGFloat {
        abs(atan2(point.x - center.x, center.y - point.y))
    }

    static var zero: MorphPoints { MorphPoints(values: []) }

    private static func combine(_ a: MorphPoints, _ b: MorphPoints, _ operation: (CGFloat, CGFloat) -> CGFloat) -> MorphPoints {
        if a.values.isEmpty { return MorphPoints(values: b.values.map { operation(0, $0) }) }
        if b.values.isEmpty { return a }
        return MorphPoints(values: zip(a.values, b.values).map(operation))
    }

    static func + (a: MorphPoints, b: MorphPoints) -> MorphPoints { combine(a, b, +) }
    static func - (a: MorphPoints, b: MorphPoints) -> MorphPoints { combine(a, b, -) }

    mutating func scale(by rhs: Double) {
        let factor = CGFloat(rhs)
        for index in values.indices { values[index] *= factor }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + Double($1 * $1) }
    }
}
