import SwiftUI
import UIKit

/// Palette di BCW: carta color crema di giorno, grafite calda di notte,
/// con un accento rosso mattone che richiama l'inchiostro delle correzioni.
enum Theme {
    static let background = dynamic(light: 0xF7F2E8, dark: 0x1E1D1C)
    static let surface = dynamic(light: 0xFFFCF6, dark: 0x292826)
    static let surfaceRaised = dynamic(light: 0xFFFFFF, dark: 0x33312F)
    static let separator = dynamic(light: 0xE6DECF, dark: 0x3B3936)
    static let ink = dynamic(light: 0x26221E, dark: 0xF2EDE4)
    static let secondaryInk = dynamic(light: 0x7A7064, dark: 0xA39C92)
    static let accent = dynamic(light: 0xA23E2F, dark: 0xE3826A)
    static let accentSoft = dynamic(light: 0xF1DDD3, dark: 0x4A2E27)

    static let good = dynamic(light: 0x3F7D56, dark: 0x7CC496)
    static let fair = dynamic(light: 0xB7791F, dark: 0xE8B460)
    static let poor = dynamic(light: 0xB33A2E, dark: 0xEE7B6C)
    static let neutral = dynamic(light: 0x4F6D8F, dark: 0x8FB0D6)

    static let corner: CGFloat = 22
    /// Spazio in fondo alle pagine lunghe: stacca l'ultimo elemento dalla tab bar e rende
    /// la pagina abbastanza lunga perché iOS rimpicciolisca la tab bar scorrendo.
    static let bottomInset: CGFloat = 120

    /// Colori tenui e distinti per le materie (assegnati in modo stabile).
    private static let subjectPalette: [(Int, Int)] = [
        (0xB5523B, 0xE88B72), (0x3F7D73, 0x7BC3B6), (0x5B5FA8, 0x9EA2EA), (0xA0782A, 0xE0B865),
        (0x8A4F7D, 0xD493C4), (0x4F7FA6, 0x8FBFE6), (0x6E8B3D, 0xADCB7A), (0xB0563F, 0xF09A80),
        (0x7A6A58, 0xBDAD99), (0x2F7A8C, 0x6FC0D2), (0x9A4A5A, 0xDD8C9C), (0x5E7F52, 0x9CC18F),
    ]

    static func subjectColor(_ id: Int?) -> Color {
        guard let id else { return secondaryInk }
        let pair = subjectPalette[abs(id) % subjectPalette.count]
        return dynamic(light: pair.0, dark: pair.1)
    }

    static func gradeColor(_ grade: Grade) -> Color {
        if grade.canceled { return secondaryInk }
        if !grade.countsTowardAverage { return neutral }
        return gradeColor(value: grade.value)
    }

    static func gradeColor(value: Double?) -> Color {
        guard let value else { return neutral }
        if value >= 6 { return good }
        if value >= 5.5 { return fair }
        return poor
    }

    static func dynamic(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Imposta i font serif (New York) nelle barre native di UIKit.
    static func configureAppearance() {
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: UIFont.newYork(size: 34, weight: .bold)]
        nav.titleTextAttributes = [.font: UIFont.newYork(size: 17, weight: .semibold)]
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: UIFont.newYork(size: 13, weight: .medium)], for: .normal)
    }
}

extension UIColor {
    nonisolated convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension UIFont {
    static func newYork(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension Font {
    /// Numeri grandi per medie e voti.
    static func numeral(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Modificatori di stile

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.7), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// Sfondo crema/grafite a tutta pagina.
    func themedBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// Stile per liste native con sfondo del tema.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}
