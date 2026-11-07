import SwiftUI
import UIKit

/// Cambio di colori con un cerchio che si allarga (Material 3 Expressive): sopra la finestra resta per
/// un attimo una fotografia dell'interfaccia di prima, con un foro circolare che cresce da `point`
/// fino a coprire lo schermo; sotto, già tutta con i colori nuovi, c'è l'app vera. Una sola animazione
/// di Core Animation, quindi niente disegni doppi e nessun lavoro per SwiftUI.
/// Con le animazioni ridotte è una dissolvenza.
enum ThemeReveal {
    private static var isRunning = false

    /// - Parameters:
    ///   - point: da dove parte il cerchio, in coordinate della finestra (`nil`: il centro).
    ///   - changes: il cambiamento (colori, tema, cosa si vede), fatto subito sotto la fotografia.
    static func perform(from point: CGPoint? = nil, duration: CFTimeInterval = 1.15, changes: () -> Void) {
        guard !isRunning, let window = keyWindow,
              let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            withAnimation(Motion.effects) { changes() }
            return
        }
        let reduced = UIAccessibility.isReduceMotionEnabled || ThemeStore.shared.motion == .reduced
        isRunning = true
        snapshot.frame = window.bounds
        // Finché il cerchio cresce i tocchi si fermano sulla fotografia.
        window.addSubview(snapshot)
        changes()
        Theme.applyTint()

        if reduced {
            UIView.animate(withDuration: 0.2) {
                snapshot.alpha = 0
            } completion: { _ in
                snapshot.removeFromSuperview()
                isRunning = false
            }
            return
        }

        let bounds = window.bounds
        let center = point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        // Fino all'angolo più lontano, più lo spessore del bordo.
        let corners = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                       CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
        let radius = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max()! + 8

        func circle(_ radius: CGFloat) -> CGRect {
            CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
        func hole(_ radius: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addEllipse(in: circle(radius))
            return path
        }

        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.path = hole(radius)
        snapshot.layer.mask = mask

        // Il fronte dell'onda: un anello del colore nuovo che si assottiglia e svanisce.
        let ring = CAShapeLayer()
        ring.fillColor = nil
        ring.strokeColor = UIColor(Theme.primary).resolvedColor(with: window.traitCollection).cgColor
        ring.lineWidth = 3
        ring.path = CGPath(ellipseIn: circle(radius), transform: nil)
        ring.opacity = 0
        window.layer.addSublayer(ring)

        // Curva "emphasized" di Material 3: parte piano, accelera, si posa.
        let timing = CAMediaTimingFunction(controlPoints: 0.42, 0, 0.18, 1)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            snapshot.removeFromSuperview()
            ring.removeFromSuperlayer()
            isRunning = false
        }

        let opening = CABasicAnimation(keyPath: "path")
        opening.fromValue = hole(0.5)
        opening.toValue = hole(radius)
        opening.duration = duration
        opening.timingFunction = timing
        mask.add(opening, forKey: "open")

        let wave = CABasicAnimation(keyPath: "path")
        wave.fromValue = CGPath(ellipseIn: circle(0.5), transform: nil)
        wave.toValue = CGPath(ellipseIn: circle(radius), transform: nil)
        wave.duration = duration
        wave.timingFunction = timing
        let thinning = CABasicAnimation(keyPath: "lineWidth")
        thinning.fromValue = 26
        thinning.toValue = 2
        thinning.duration = duration
        thinning.timingFunction = timing
        let fading = CAKeyframeAnimation(keyPath: "opacity")
        fading.values = [0.0, 0.5, 0.3, 0.0]
        fading.keyTimes = [0, 0.12, 0.6, 1]
        fading.duration = duration
        let group = CAAnimationGroup()
        group.animations = [wave, thinning, fading]
        group.duration = duration
        ring.add(group, forKey: "wave")

        CATransaction.commit()
        Haptics.soft()
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first
    }
}
