import SwiftUI

// MARK: - Icona dell'app: opzioni (Impostazioni › Aspetto › Icona dell'app)

/// Colore dell'icona: quello del tema o uno degli undici colori dell'icona, uno per ogni colore
/// d'accento proposto in Aspetto più Grafite. Ogni colore ha un'icona di Icon Composer; lo sfondo
/// segue sempre le icone chiare, scure o colorate di iOS.
enum AppIconColor: String, CaseIterable, Identifiable {
    case theme, mattone, arancio, oro, verde, petrolio, blu, indaco, viola, rosa, ardesia, grafite

    var id: String { rawValue }

    /// I colori fissi.
    static let presets: [AppIconColor] = allCases.filter { $0 != .theme }

    var title: String {
        switch self {
        case .theme: "Tema dell'app"
        case .mattone: "Mattone"
        case .arancio: "Arancio"
        case .oro: "Oro"
        case .verde: "Verde"
        case .petrolio: "Petrolio"
        case .blu: "Blu"
        case .indaco: "Indaco"
        case .viola: "Viola"
        case .rosa: "Rosa"
        case .ardesia: "Ardesia"
        case .grafite: "Grafite"
        }
    }

    /// Tinte del cerchio (`nil` per il tema).
    var tint: AppIconTint? { AppIconPalette.tints[self] }

    /// Colore d'accento proposto in Aspetto (`accentPresets`) a cui il colore dell'icona fa da
    /// predefinito: con "Tema dell'app" e quell'accento l'icona prende questo colore. Grafite non
    /// corrisponde a nessun accento (lo prendono i colori quasi grigi scelti a mano).
    var themeAccent: String? {
        switch self {
        case .mattone: "#a23e2f"
        case .arancio: "#c0661b"
        case .oro: "#9a7b12"
        case .verde: "#2f7d55"
        case .petrolio: "#1f7a80"
        case .blu: "#2f6db5"
        case .indaco: "#5b5bb0"
        case .viola: "#8a4fb0"
        case .rosa: "#b8456f"
        case .ardesia: "#5f6b7a"
        case .theme, .grafite: nil
        }
    }

    /// Valore salvato o arrivato dall'account BCW. I nomi dei colori della 3.1 (uno per accento)
    /// sono di nuovo colori dell'icona; `nil` per un valore sconosciuto.
    init?(stored: String) {
        self.init(rawValue: stored)
    }

    /// Il colore dell'icona per un colore d'accento: per i colori proposti in Aspetto il loro
    /// (`themeAccent`); per un colore scelto a mano Grafite se è quasi grigio (croma HCT sotto 16),
    /// altrimenti il colore con la tonalità più vicina. Solo la tonalità, non la distanza nel piano
    /// tonalità-croma: un azzurro a metà tra Petrolio e Blu finiva su Grafite, che ha poco croma ma
    /// una tonalità blu.
    static func nearest(to accent: String) -> AppIconColor {
        let hex = ThemeStore.normalize(accent) ?? defaultAccent
        if let preset = presets.first(where: { $0.themeAccent == hex }) { return preset }
        if let cached = nearestCache[hex] { return cached }
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
            for color in presets where color != .grafite && color != .ardesia {
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

    /// Chiave del risultato salvato. Quelle delle versioni precedenti (`appIconNearestTint` con sei
    /// colori, `appIconNearest` con dieci) davano colori che ora non sono più i più vicini.
    private static let nearestKey = "appIconThemeTint"
    static let oldNearestKeys = ["appIconNearestTint", "appIconNearest"]
    private static var nearestCache: [String: AppIconColor] = [:]
}

/// Icona scelta, con il colore già risolto (mai `.theme`).
struct AppIconChoice: Hashable {
    var color: AppIconColor

    /// Icona principale (`AppIcon.icon`).
    static let primary = AppIconChoice(color: .mattone)

    /// Nome dell'icona alternativa (`AppIcons/<nome>.icon`, `nil` = icona principale). Gli stessi
    /// nomi vanno in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (progetto e `project.yml`).
    var assetName: String? {
        self == .primary ? nil : "AppIcon-\(color.rawValue)"
    }

    /// Tutte le icone, la principale per prima (per il generatore).
    static var all: [AppIconChoice] {
        AppIconColor.presets.map { AppIconChoice(color: $0) }
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
        .oro: AppIconTint(light: 0xE5AA00, dark: 0xF6C12C),
        .verde: AppIconTint(light: 0x22A55A, dark: 0x34C46E),
        .petrolio: AppIconTint(light: 0x0E959E, dark: 0x27B5BE),
        .blu: AppIconTint(light: 0x1F7AF0, dark: 0x3D8EFF),
        .indaco: AppIconTint(light: 0x5856D6, dark: 0x7472F0),
        .viola: AppIconTint(light: 0x9B4FE0, dark: 0xAE73F7),
        .rosa: AppIconTint(light: 0xDE4479, dark: 0xF26892),
        .ardesia: AppIconTint(light: 0x56677F, dark: 0x8193AB),
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
        case .light:
            return AppIconColors(background: .solid(color(lightBackground)), shape: color(tint.light), bar: color(bar))
        case .dark:
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
        let darkBackground = mode != .light
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
