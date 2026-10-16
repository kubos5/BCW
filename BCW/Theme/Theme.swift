import SwiftUI
import UIKit

/// Design system di BCW: Material 3 Expressive, come la versione web (`css/bcw.css`).
/// I ruoli dei colori vengono da `ThemeStore` (generati dal colore d'accento scelto); stati,
/// voti e materie hanno palette tonali fisse. Le forme usano angoli continui (supercerchi).
enum Theme {
    private static var c: SchemeColors { ThemeStore.shared.colors }

    // MARK: Ruoli di Material 3

    static var primary: Color { c.primary }
    static var onPrimary: Color { c.onPrimary }
    static var primaryContainer: Color { c.primaryContainer }
    static var onPrimaryContainer: Color { c.onPrimaryContainer }
    static var secondary: Color { c.secondary }
    static var onSecondary: Color { c.onSecondary }
    static var secondaryContainer: Color { c.secondaryContainer }
    static var onSecondaryContainer: Color { c.onSecondaryContainer }
    static var tertiary: Color { c.tertiary }
    static var onTertiary: Color { c.onTertiary }
    static var tertiaryContainer: Color { c.tertiaryContainer }
    static var onTertiaryContainer: Color { c.onTertiaryContainer }
    static var error: Color { c.error }
    static var onError: Color { c.onError }
    static var errorContainer: Color { c.errorContainer }
    static var onErrorContainer: Color { c.onErrorContainer }
    static var surface: Color { c.surface }
    static var surfaceDim: Color { c.surfaceDim }
    static var surfaceBright: Color { c.surfaceBright }
    static var surfaceContainerLowest: Color { c.surfaceContainerLowest }
    static var surfaceContainerLow: Color { c.surfaceContainerLow }
    static var surfaceContainer: Color { c.surfaceContainer }
    static var surfaceContainerHigh: Color { c.surfaceContainerHigh }
    static var surfaceContainerHighest: Color { c.surfaceContainerHighest }
    static var onSurface: Color { c.onSurface }
    static var onSurfaceVariant: Color { c.onSurfaceVariant }
    static var outline: Color { c.outline }
    static var outlineVariant: Color { c.outlineVariant }
    static var inverseSurface: Color { c.inverseSurface }
    static var inverseOnSurface: Color { c.inverseOnSurface }
    static var inversePrimary: Color { c.inversePrimary }
    /// Colore del marchio (la linea del logo).
    static var brand: Color { c.brand }
    static var shadow: Color { c.shadow }
    static var scrim: Color { c.scrim }

    // MARK: Nomi brevi (come gli alias di `css/bcw.css`)

    /// Sfondo delle pagine.
    static var background: Color { c.surface }
    /// Sfondo delle card.
    static var card: Color { c.surfaceContainer }
    static var ink: Color { c.onSurface }
    static var secondaryInk: Color { c.onSurfaceVariant }
    static var accent: Color { c.primary }
    static var separator: Color { c.outlineVariant }

    // MARK: Stati (bene, sufficiente, insufficiente, neutro)

    static let good = dynamic(light: 0x2B6A45, dark: 0x94D5A7)
    static let onGood = dynamic(light: 0xFFFFFF, dark: 0x00391D)
    static let goodContainer = dynamic(light: 0xAFF2C2, dark: 0x0D512F)
    static let onGoodContainer = dynamic(light: 0x00210F, dark: 0xAFF2C2)
    static let fair = dynamic(light: 0x855300, dark: 0xFFB95F)
    static let onFair = dynamic(light: 0xFFFFFF, dark: 0x472A00)
    static let fairContainer = dynamic(light: 0xFFDDB8, dark: 0x653E00)
    static let onFairContainer = dynamic(light: 0x2A1700, dark: 0xFFDDB8)
    static let poor = dynamic(light: 0xAB3429, dark: 0xFFB4A9)
    static let onPoor = dynamic(light: 0xFFFFFF, dark: 0x690002)
    static let poorContainer = dynamic(light: 0xFFDAD5, dark: 0x8A1C14)
    static let onPoorContainer = dynamic(light: 0x410001, dark: 0xFFDAD5)
    static let neutral = dynamic(light: 0x426182, dark: 0xAAC9EF)
    static let onNeutral = dynamic(light: 0xFFFFFF, dark: 0x0F3251)
    static let neutralContainer = dynamic(light: 0xD1E4FF, dark: 0x2A4969)
    static let onNeutralContainer = dynamic(light: 0x001D35, dark: 0xD1E4FF)
    /// Intervalli dell'orario.
    static let breakTint = dynamic(light: 0x9A8C78, dark: 0xB8AC98)

    // MARK: Forme

    static var radii: CornerRadii { ThemeStore.shared.radii }
    /// Angoli delle card (`--r-li`).
    static var corner: CGFloat { radii.li }

    /// Spazio in fondo alle pagine lunghe: con Liquid Glass stacca l'ultimo elemento dalla barra
    /// delle schede (che sta sopra il contenuto) e rende la pagina abbastanza lunga perché iOS la
    /// rimpicciolisca scorrendo; con la barra di Material 3 il contenuto finisce già sopra la barra.
    static var bottomInset: CGFloat { ThemeStore.shared.liquidGlass ? 120 : 40 }

    // MARK: Materie e voti

    /// Palette tonali delle materie (`--subject-N`, `-container`, `on-…-container`).
    private static let subjectPalette: [(tone: (Int, Int), container: (Int, Int), onContainer: (Int, Int))] = [
        ((0x9E412B, 0xFFB4A3), (0xFFDAD2, 0x7F2A17), (0x3D0600, 0xFFDAD2)),
        ((0x29685F, 0x94D2C7), (0xAFEFE2, 0x055047), (0x00201C, 0xAFEFE2)),
        ((0x5357A0, 0xBFC1FF), (0xE1E0FF, 0x3B3F86), (0x0C0E5A, 0xE1E0FF)),
        ((0x7C5808, 0xEFBF6A), (0xFFDEA9, 0x5E4100), (0x271900, 0xFFDEA9)),
        ((0x854A78, 0xF8B0E4), (0xFFD7F1, 0x6A335F), (0x370531, 0xFFD7F1)),
        ((0x306388, 0x9CCCF6), (0xCCE5FF, 0x114B6F), (0x001E31, 0xCCE5FF)),
        ((0x4C671D, 0xB1D27B), (0xCDEE94, 0x354E04), (0x131F00, 0xCDEE94)),
        ((0x99452F, 0xFFB4A2), (0xFFDAD2, 0x7B2E1A), (0x3C0800, 0xFFDAD2)),
        ((0x6B5C4A, 0xD7C3AE), (0xF4DFC9, 0x524434), (0x241A0C, 0xF4DFC9)),
        ((0x136779, 0x8BD1E5), (0xADECFF, 0x004E5D), (0x001F26, 0xADECFF)),
        ((0x944555, 0xFFB2BE), (0xFFD9DE, 0x772E3E), (0x3E0215, 0xFFD9DE)),
        ((0x47663C, 0xACD19D), (0xC8EDB7, 0x304E26), (0x042101, 0xC8EDB7)),
    ]

    private static let subjectColors: [Color] = subjectPalette.map { dynamic(light: $0.tone.0, dark: $0.tone.1) }

    /// Colore stabile di una materia (`--subject-N`).
    static func subjectColor(_ id: Int?) -> Color {
        guard let id else { return secondaryInk }
        return subjectColors[abs(id) % subjectColors.count]
    }

    /// Colore della materia numero `index` (0–11), per le icone delle sezioni.
    static func subject(_ index: Int) -> Color { subjectColors[index % subjectColors.count] }

    /// Tono di una media o di un voto: bene, quasi, insufficiente, neutro.
    enum Tone {
        case good, fair, poor, neutral

        var color: Color {
            switch self {
            case .good: Theme.good
            case .fair: Theme.fair
            case .poor: Theme.poor
            case .neutral: Theme.neutral
            }
        }

        var container: Color {
            switch self {
            case .good: Theme.goodContainer
            case .fair: Theme.fairContainer
            case .poor: Theme.poorContainer
            case .neutral: Theme.neutralContainer
            }
        }

        var onContainer: Color {
            switch self {
            case .good: Theme.onGoodContainer
            case .fair: Theme.onFairContainer
            case .poor: Theme.onPoorContainer
            case .neutral: Theme.onNeutralContainer
            }
        }
    }

    static func tone(value: Double?) -> Tone {
        guard let value else { return .neutral }
        if value >= 6 { return .good }
        if value >= 5.5 { return .fair }
        return .poor
    }

    static func tone(_ grade: Grade) -> Tone {
        if grade.canceled || !grade.countsTowardAverage { return .neutral }
        return tone(value: grade.value)
    }

    static func gradeColor(_ grade: Grade) -> Color {
        if grade.canceled { return secondaryInk }
        return tone(grade).color
    }

    static func gradeColor(value: Double?) -> Color { tone(value: value).color }

    // MARK: Colori dinamici

    static func dynamic(light: Int, dark: Int, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? dark : light).withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        })
    }

    /// Font e colori delle barre native di UIKit (usate con Liquid Glass).
    static func configureAppearance() {
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: Typography.platformFont(size: 34, weight: 500, rounded: true)]
        nav.titleTextAttributes = [.font: Typography.platformFont(size: 18, weight: 550, rounded: true)]
        let item = UITabBarItem.appearance()
        item.setTitleTextAttributes([.font: Typography.platformFont(size: 10, weight: 600)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: Typography.platformFont(size: 13, weight: 550)], for: .normal)
        applyTint()
    }

    /// Colore d'accento dei componenti di UIKit (barra delle schede, pulsanti e menu di sistema,
    /// avvisi): non vedono il `.tint` di SwiftUI e userebbero il colore d'accento del catalogo.
    /// Si aggiorna a ogni cambio del colore d'accento, anche nelle finestre già aperte.
    static func applyTint() {
        let tint = UIColor(primary)
        UIWindow.appearance().tintColor = tint
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.tintColor = tint }
        }
    }
}

extension Color {
    /// Mescola due colori come `color-mix(in srgb, a p%, b)`.
    func mix(_ other: Color, _ amount: Double) -> Color {
        Color(platformColor: PlatformColor.mixing(self, other, amount))
    }
}

extension PlatformColor {
    /// Colore dinamico che mescola `a` (per `amount`) con `b`, risolto nel tema in uso.
    static func mixing(_ a: Color, _ b: Color, _ amount: Double) -> PlatformColor {
        UIColor { traits in
            let ca = UIColor(a).resolvedColor(with: traits)
            let cb = UIColor(b).resolvedColor(with: traits)
            var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            ca.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            cb.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(red: r1 * amount + r2 * (1 - amount), green: g1 * amount + g2 * (1 - amount),
                           blue: b1 * amount + b2 * (1 - amount), alpha: a1 * amount + a2 * (1 - amount))
        }
    }
}

// MARK: - Modificatori di stile

/// Card di Material 3: contenitore pieno (`surface-container`) con angoli ampi e continui.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var color: Color?
    var radius: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? Theme.card, in: .rect(cornerRadius: radius ?? Theme.radii.li, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16, color: Color? = nil, radius: CGFloat? = nil) -> some View {
        modifier(CardBackground(padding: padding, color: color, radius: radius))
    }

    /// Sfondo delle pagine a tutta altezza.
    func themedBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// Stile per liste native con lo sfondo del tema.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}
