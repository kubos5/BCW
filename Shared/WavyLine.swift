import SwiftUI

/// Linea ondulata orizzontale (separatore degli intervalli).
struct WavyLine: Shape {
    var amplitude: CGFloat = 2
    var wavelength: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }
        // Comincia e finisce a metà altezza, con onde intere centrate nello spazio disponibile.
        let waves = max(1, (rect.width / wavelength).rounded(.down))
        let length = waves * wavelength
        let start = rect.minX + (rect.width - length) / 2
        path.move(to: CGPoint(x: start, y: rect.midY))
        var x: CGFloat = 0
        while x < length {
            x = min(x + 1, length)
            path.addLine(to: CGPoint(x: start + x, y: rect.midY - sin(x / wavelength * 2 * .pi) * amplitude))
        }
        return path
    }
}
