import SwiftUI

// MARK: - Icona dell'app: opzioni (Impostazioni › Aspetto › Icona dell'app)

/// Colore dell'icona: quello del tema (il colore proposto più vicino all'accento) o uno dei sei
/// colori dell'icona. Ogni colore ha due icone di Icon Composer (automatica e sempre scura).
enum AppIconColor: String, CaseIterable, Identifiable {
    case theme, mattone, arancio, verde, blu, viola, grafite

    var id: String { rawValue }

    /// I colori fissi.
    static let presets: [AppIconColor] = allCases.filter { $0 != .theme }

    var title: String {
        switch self {
        case .theme: "Tema dell'app"
        case .mattone: "Mattone"
        case .arancio: "Arancio"
        case .verde: "Verde"
        case .blu: "Blu"
        case .viola: "Viola"
        case .grafite: "Grafite"
        }
    }

    /// Tinte del cerchio (`nil` per il tema).
    var tint: AppIconTint? { AppIconPalette.tints[self] }

    /// Valore salvato o arrivato dall'account BCW, anche di una versione precedente (fino alla 3.2
    /// c'erano dieci colori, quelli di `accentPresets`): i colori tolti diventano il più vicino
    /// (calcolato con `nearest`). `nil` per un valore sconosciuto.
    init?(stored: String) {
        if let color = AppIconColor(rawValue: stored) {
            self = color
            return
        }
        switch stored {
        case "oro": self = .arancio
        case "petrolio": self = .verde
        case "indaco": self = .blu
        case "rosa": self = .mattone
        case "ardesia": self = .grafite
        default: return nil
        }
    }

    /// Il colore dell'icona più vicino a un colore qualsiasi (HCT di Material): Grafite per i
    /// colori quasi grigi (croma sotto 16), altrimenti il colore con la tonalità più vicina.
    /// Solo la tonalità, non la distanza nel piano tonalità-croma: con sei colori distanti tra loro
    /// un azzurro (a metà tra Verde e Blu) finiva su Grafite, che ha poco croma ma una tonalità blu.
    static func nearest(to accent: String) -> AppIconColor {
        let hex = ThemeStore.normalize(accent) ?? defaultAccent
        if let cached = nearestCache[hex] { return cached }
        if hex == defaultAccent { return .mattone }
        // Il risultato resta salvato tra un avvio e l'altro: calcolarlo carica JavaScriptCore, che
        // all'avvio con un colore qualsiasi non serve (i colori del tema sono in cache), e
        // `AppIconController` lo chiede appena parte l'interfaccia.
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: nearestKey)?.split(separator: "=").map(String.init) ?? []
        if saved.count == 2, saved[0] == hex, let color = AppIconColor(rawValue: saved[1]), color != .theme {
            nearestCache[hex] = color
            return color
        }
        guard let target = ColorEngine.shared.hueChroma(hex) else { return .mattone }
        var best = AppIconColor.mattone
        if target.chroma < 16 {
            best = .grafite
        } else {
            var bestDistance = Double.infinity
            for color in presets where color != .grafite {
                guard let hue = color.tint.flatMap({ ColorEngine.shared.hueChroma($0.lightHex)?.hue }) else { continue }
                let difference = abs(hue - target.hue).truncatingRemainder(dividingBy: 360)
                let distance = min(difference, 360 - difference)
                if distance < bestDistance {
                    bestDistance = distance
                    best = color
                }
            }
        }
        nearestCache[hex] = best
        defaults.set("\(hex)=\(best.rawValue)", forKey: nearestKey)
        return best
    }

    /// Chiave del risultato salvato (quella delle versioni con dieci colori era `appIconNearest`).
    private static let nearestKey = "appIconNearestTint"
    private static var nearestCache: [String: AppIconColor] = [:]
}

/// Aspetto dell'icona rispetto alla modalità delle icone di iOS (chiare, scure, colorate).
enum AppIconAppearance: String, CaseIterable, Identifiable {
    case automatic = "auto", dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatico"
        case .dark: "Sempre scuro"
        }
    }

    /// Valore salvato o arrivato dall'account BCW: "Sempre chiaro" (fino alla 3.2) diventa
    /// automatico.
    init?(stored: String) {
        if let appearance = AppIconAppearance(rawValue: stored) {
            self = appearance
        } else if stored == "light" {
            self = .automatic
        } else {
            return nil
        }
    }
}

/// Icona scelta: colore già risolto (mai `.theme`) e aspetto.
struct AppIconChoice: Hashable {
    var color: AppIconColor
    var appearance: AppIconAppearance

    /// Combinazione dell'icona principale (`AppIcon.icon`).
    static let primary = AppIconChoice(color: .mattone, appearance: .automatic)

    /// Nome dell'icona alternativa (`AppIcons/<nome>.icon`, `nil` = icona principale). Gli stessi
    /// nomi vanno in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (progetto e `project.yml`).
    var assetName: String? {
        if self == .primary { return nil }
        return appearance == .dark ? "AppIcon-\(color.rawValue)-scura" : "AppIcon-\(color.rawValue)"
    }

    /// Tutte le combinazioni, la principale per prima (per il generatore).
    static var all: [AppIconChoice] {
        AppIconAppearance.allCases.flatMap { appearance in
            AppIconColor.presets.map { AppIconChoice(color: $0, appearance: appearance) }
        }
    }
}

// MARK: - Colori

/// Tinte del cerchio di un colore: sullo sfondo chiaro e su quello scuro (più chiara, come le
/// icone scure di iOS).
struct AppIconTint: Hashable {
    let light: Int
    let dark: Int

    var lightHex: String {
        let digits = String(light, radix: 16)
        return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }
}

/// Sfondo dell'icona.
enum AppIconBackground: Equatable {
    case solid(Color)
    /// Sfumatura verticale (dall'alto in basso).
    case gradient(Color, Color)
    case clear
}

/// Colori di un'immagine dell'icona.
struct AppIconColors: Equatable {
    var background: AppIconBackground
    var shape: Color
    var bar: Color
}

/// Colori delle icone, gli stessi per l'anteprima e per le icone di Icon Composer del generatore.
/// Tinte piene e sature come quelle delle app di iOS (non i ruoli di Material: le icone stanno
/// sulla Home, non nell'app), scelte guardando le icone sulla Home del simulatore.
enum AppIconPalette {
    static let tints: [AppIconColor: AppIconTint] = [
        .mattone: AppIconTint(light: 0xC4432B, dark: 0xEC6F55),
        .arancio: AppIconTint(light: 0xFF8A1F, dark: 0xFF9632),
        .verde: AppIconTint(light: 0x22A55A, dark: 0x34C46E),
        .blu: AppIconTint(light: 0x1F7AF0, dark: 0x3D8EFF),
        .viola: AppIconTint(light: 0x9B4FE0, dark: 0xAE73F7),
        .grafite: AppIconTint(light: 0x5A6068, dark: 0x7F868F),
    ]
    /// Sfondo dell'icona chiara: un bianco caldo.
    static let lightBackground = 0xFBF7F4
    /// Barra: sempre bianca.
    static let bar = 0xFFFFFF
    /// Sfondo scuro delle icone di iOS (misurato sul simulatore con iOS 26): nelle icone vere lo
    /// mette iOS (`automatic`, `system-dark`), qui serve per l'anteprima.
    static let systemDark = AppIconBackground.gradient(Color(platformColor: PlatformColor(hex: 0x2E2E30)),
                                                       Color(platformColor: PlatformColor(hex: 0x111112)))
    /// Grigio del cerchio nelle icone colorate e trasparenti: la barra, bianca, resta il livello
    /// più chiaro. iOS schiarisce i grigi tingendoli: con 0,45 il cerchio diventava quasi bianco e la
    /// barra si vedeva appena (verificato sul simulatore), con 0,3 restano distinti.
    static let tintedShapeWhite: CGFloat = 0.3

    /// Colori dell'icona in una modalità delle icone di iOS.
    static func colors(for choice: AppIconChoice, mode: AppIconPreview.Mode) -> AppIconColors {
        let tint = choice.color.tint ?? tints[.mattone]!
        func color(_ hex: Int) -> Color { Color(platformColor: PlatformColor(hex: hex)) }
        switch mode {
        case .light where choice.appearance == .automatic:
            return AppIconColors(background: .solid(color(lightBackground)), shape: color(tint.light), bar: color(bar))
        case .light, .dark:
            return AppIconColors(background: systemDark, shape: color(tint.dark), bar: color(bar))
        case .tinted:
            return AppIconColors(background: .clear, shape: Color(white: tintedShapeWhite), bar: color(bar))
        }
    }
}

// MARK: - Disegno

/// Proporzioni dell'icona, in frazioni della tela (1024 punti per iOS). Le stesse per
/// l'anteprima e per i livelli delle icone di Icon Composer.
enum AppIconGeometry {
    /// Lato del cerchio rispetto alla tela.
    static let shape: CGFloat = 0.86
    /// Larghezza della barra rispetto al cerchio.
    static let bar: CGFloat = 0.77
    /// Altezza della barra rispetto alla larghezza (rettangolo 64 × 8,73 del logo, a pillola).
    static let barAspect: CGFloat = 8.73 / 64
    /// Raggio degli angoli della maschera delle icone di iOS (solo per l'anteprima).
    static let mask: CGFloat = 0.2237
}

/// Disegno dell'icona a tutta tela (senza maschera) per l'anteprima: sfondo, cerchio e barra come
/// due lastre, con un riflesso in alto e un'ombra leggera, per somigliare al vetro che iOS dà alle
/// icone di Icon Composer.
struct AppIconArtwork: View {
    let colors: AppIconColors
    let size: CGFloat
    /// Riflessi e ombre delle lastre (non per lo sfondo da solo).
    var glass = true

    var body: some View {
        let circle = size * AppIconGeometry.shape
        let barWidth = circle * AppIconGeometry.bar
        ZStack {
            switch colors.background {
            case .solid(let color): Rectangle().fill(color)
            case .gradient(let top, let bottom): Rectangle().fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            case .clear: Color.clear
            }
            Circle()
                .fill(colors.shape)
                .overlay {
                    if glass {
                        // Luce dall'alto e bordo chiaro, come le lastre di vetro di iOS.
                        Circle().fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0), .black.opacity(0.06)],
                                                     startPoint: .top, endPoint: .bottom))
                        Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.25)],
                                                             startPoint: .top, endPoint: .bottom),
                                              lineWidth: max(0.5, size / 160))
                    }
                }
                .frame(width: circle, height: circle)
                .shadow(color: .black.opacity(glass ? 0.18 : 0), radius: size / 40, y: size / 80)
            // Il rettangolo del logo ha raggio pari a metà altezza (archi di cerchio, come l'SVG).
            Capsule(style: .circular)
                .fill(colors.bar)
                .overlay {
                    if glass {
                        Capsule(style: .circular)
                            .fill(LinearGradient(colors: [.white.opacity(0), .black.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .frame(width: barWidth, height: barWidth * AppIconGeometry.barAspect)
                .shadow(color: .black.opacity(glass ? 0.22 : 0), radius: size / 70, y: size / 120)
        }
        .frame(width: size, height: size)
    }
}

/// Icona come la mostra iOS in una modalità delle icone (chiara, scura o colorata), con la
/// maschera della Home: per l'anteprima e i campioni della pagina Icona dell'app.
struct AppIconPreview: View {
    enum Mode { case light, dark, tinted }

    let choice: AppIconChoice
    let mode: Mode
    let size: CGFloat
    /// Tinta delle icone colorate.
    var tint: Color = .white

    var body: some View {
        let mask = RoundedRectangle(cornerRadius: size * AppIconGeometry.mask, style: .continuous)
        let colors = AppIconPalette.colors(for: choice, mode: mode)
        let darkBackground = mode != .light || choice.appearance == .dark
        ZStack {
            if mode == .tinted {
                // iOS tinge la scala di grigi sul suo sfondo scuro.
                AppIconArtwork(colors: AppIconColors(background: AppIconPalette.systemDark, shape: .clear, bar: .clear),
                               size: size, glass: false)
                AppIconArtwork(colors: colors, size: size)
                    .colorMultiply(tint)
            } else {
                AppIconArtwork(colors: colors, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(mask)
        .overlay(mask.strokeBorder(Color.white.opacity(darkBackground ? 0.1 : 0), lineWidth: max(0.5, size / 120)))
        .compositingGroup()
    }
}
