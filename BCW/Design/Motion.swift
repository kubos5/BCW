import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Movimento di Material 3 Expressive: molle spaziali (posizione, forma) con un piccolo
/// rimbalzo ed effetti (colore, opacità) senza. Seguono Impostazioni › Aspetto › Animazioni:
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
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func soft() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        #endif
    }
}
