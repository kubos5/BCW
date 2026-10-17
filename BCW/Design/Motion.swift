import SwiftUI
import UIKit

/// Movimento di Material 3 Expressive (`MotionScheme` di Compose): molle spaziali (posizione,
/// forma) con un piccolo rimbalzo ed effetti (colore, opacità) senza. Valori espressivi: spaziali
/// veloce 800/0,6, normale 380/0,8, lento 200/0,8; effetti 3800, 1600 (smorzamento 1). Con
/// risposta = 2π/√rigidezza. Seguono Impostazioni › Aspetto › Animazioni:
/// espressive, standard (senza rimbalzo) o ridotte (brevi, senza movimenti ampi).
enum Motion {
    private static var style: MotionStyle { ThemeStore.shared.motion }

    /// Molla spaziale veloce (pulsanti, forme che cambiano alla pressione).
    static var spatialFast: Animation {
        switch style {
        case .expressive: .spring(response: 0.22, dampingFraction: 0.6)
        case .standard: .spring(response: 0.17, dampingFraction: 0.9)
        case .reduced: .easeOut(duration: 0.12)
        }
    }

    /// Molla spaziale predefinita (sezioni, schede, elementi che si spostano).
    static var spatial: Animation {
        switch style {
        case .expressive: .spring(response: 0.32, dampingFraction: 0.8)
        case .standard: .spring(response: 0.24, dampingFraction: 0.9)
        case .reduced: .easeOut(duration: 0.15)
        }
    }

    /// Molla spaziale lenta (fogli, grandi spostamenti).
    static var spatialSlow: Animation {
        switch style {
        case .expressive: .spring(response: 0.44, dampingFraction: 0.8)
        case .standard: .spring(response: 0.36, dampingFraction: 0.9)
        case .reduced: .easeOut(duration: 0.18)
        }
    }

    /// Effetti veloci (velo della pressione).
    static var effectsFast: Animation {
        style == .reduced ? .easeOut(duration: 0.1) : .spring(response: 0.1, dampingFraction: 1)
    }

    /// Effetti (colori, opacità).
    static var effects: Animation {
        style == .reduced ? .easeOut(duration: 0.15) : .spring(response: 0.16, dampingFraction: 1)
    }
}

// MARK: - Transizioni di Material 3

extension AnyTransition {
    /// Asse condiviso orizzontale: tra elementi allo stesso livello (giorni, schede). Quello che
    /// esce scivola e svanisce da una parte, quello che entra arriva dall'altra.
    static func sharedAxisX(forward: Bool, distance: CGFloat = 48) -> AnyTransition {
        .asymmetric(insertion: .offset(x: forward ? distance : -distance).combined(with: .opacity),
                    removal: .offset(x: forward ? -distance : distance).combined(with: .opacity))
    }

    /// Asse condiviso verticale: tra passaggi di un flusso o viste della stessa pagina.
    static func sharedAxisY(forward: Bool = true, distance: CGFloat = 32) -> AnyTransition {
        .asymmetric(insertion: .offset(y: forward ? distance : -distance).combined(with: .opacity),
                    removal: .offset(y: forward ? -distance : distance).combined(with: .opacity))
    }

    /// Dissolvenza incrociata (fade through): tra contenuti senza relazione. Quello vecchio svanisce
    /// in fretta, quello nuovo compare ingrandendosi appena.
    static var fadeThrough: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)).animation(Motion.spatial.delay(0.05)),
                    removal: .opacity.animation(Motion.effectsFast))
    }

    /// Espansione: il contenuto compare mentre il contenitore si allunga con la molla spaziale (e
    /// svanisce in fretta chiudendo).
    static var expand: AnyTransition {
        .asymmetric(insertion: .opacity.animation(Motion.effects.delay(0.04)).combined(with: .scale(scale: 0.98, anchor: .top)),
                    removal: .opacity.animation(Motion.effectsFast))
    }
}

/// Icona di Material Symbols Rounded (le stesse della versione web), dal catalogo delle risorse.
struct Icon: View {
    let name: String
    var size: CGFloat = 24

    init(_ name: String, size: CGFloat = 24) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("m.\(name)")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Image {
    /// Icona di Material Symbols per etichette, menu e schede di sistema.
    static func m(_ name: String) -> Image {
        Image("m.\(name)").renderingMode(.template)
    }
}

extension Label where Title == Text, Icon == Image {
    /// Etichetta con un'icona di Material Symbols.
    init(_ title: String, icon: String) {
        self.init { Text(title) } icon: { Image.m(icon) }
    }
}

// MARK: - Feedback aptico

/// Vibrazioni dell'interfaccia (solo iPhone): tocco leggero, selezione, conferma.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }
}
