import SwiftUI

/// Arco dell'anello della media: la parte piena (ondulata) o la traccia dopo lo spazio.
struct RingShape: Shape {
    var progress: Double
    let lineWidth: CGFloat
    let track: Bool
    let wavy: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let r = (size - lineWidth) / 2 - (size >= 60 ? 3 : 0)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = -Double.pi / 2
        let gap = Double(lineWidth * 1.1 + 4) / Double(r)
        let end = start + progress * 2 * .pi
        var path = Path()
        if track {
            guard progress < 0.999 else { return path }
            let from = progress > 0 ? end + gap : start
            let to = start + 2 * .pi - (progress > 0 ? gap : 0)
            guard to > from else { return path }
            path.addArc(center: center, radius: r, startAngle: .radians(from), endAngle: .radians(to), clockwise: false)
            return path
        }
        guard progress > 0 else { return path }
        let to = progress >= 0.999 ? start + 2 * .pi : end
        if !wavy {
            path.addArc(center: center, radius: r, startAngle: .radians(start), endAngle: .radians(to), clockwise: false)
            return path
        }
        // L'onda si appiattisce agli estremi, così l'arco comincia e finisce sul cerchio.
        let amplitude = min(3, Double(size) / 40)
        let wavelength = max(16, Double(size) / 4)
        let length = (to - start) * Double(r)
        let steps = max(8, Int(ceil(length / 2)))
        for i in 0...steps {
            let t = start + (to - start) * Double(i) / Double(steps)
            let s = (t - start) * Double(r)
            let fade = min(1, s / wavelength, (length - s) / wavelength)
            let rr = Double(r) + amplitude * fade * sin(s / wavelength * 2 * .pi)
            let point = CGPoint(x: center.x + rr * cos(t), y: center.y + rr * sin(t))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
