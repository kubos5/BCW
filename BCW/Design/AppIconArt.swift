import CoreText
import SwiftUI

// MARK: - Icona dell'app: opzioni (Impostazioni › Aspetto › Icona dell'app)

/// Colore dell'icona: quello del tema o uno dei dieci colori dell'icona, uno per ogni colore
/// d'accento proposto in Aspetto (richiesta dell'utente, 3.3: ogni colore corrisponde a un tema). Ogni
/// colore ha un'icona di Icon Composer, chiara o scura come le icone di iOS.
enum AppIconColor: String, CaseIterable, Identifiable {
    case theme, mattone, arancio, oro, verde, petrolio, blu, indaco, viola, rosa, ardesia

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
        }
    }

    /// Colori dell'icona chiara e scura (`nil` per il tema).
    var palette: AppIconSchemes? { AppIconPalette.schemes[self] }

    /// Colore d'accento proposto in Aspetto (`accentPresets`) da cui vengono i colori dell'icona:
    /// con "Tema dell'app" e quell'accento l'icona prende questo colore.
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
        case .theme: nil
        }
    }

    /// Valore salvato o arrivato dall'account BCW. I nomi dei colori della 3.1 (uno per accento)
    /// sono di nuovo colori dell'icona; `nil` per un valore sconosciuto.
    init?(stored: String) {
        self.init(rawValue: stored)
    }

    /// Il colore dell'icona per un colore d'accento: per i colori proposti in Aspetto il loro
    /// (`themeAccent`); per un colore scelto a mano Ardesia se è quasi grigio (croma HCT sotto 16),
    /// altrimenti il colore con la tonalità più vicina. Solo la tonalità, non la distanza nel piano
    /// tonalità-croma: un azzurro a metà tra Petrolio e Blu finiva sul grigio, che ha poco croma ma
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
            best = .ardesia
        } else {
            var bestDistance = Double.infinity
            for color in presets where color != .ardesia {
                guard let hue = color.themeAccent.flatMap({ ColorEngine.shared.hueChroma($0)?.hue }) else { continue }
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
    /// colori, `appIconNearest` con dieci, `appIconThemeTint` con Grafite) davano colori che ora non
    /// sono più i più vicini.
    private static let nearestKey = "appIconThemeColor"
    static let oldNearestKeys = ["appIconNearestTint", "appIconNearest", "appIconThemeTint"]
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

/// Colori di un'icona in una modalità: sfondo, scritta e barra. Lo sfondo scuro non si usa: con le
/// icone scure lo sfondo è quello di iOS (richiesta dell'utente).
struct AppIconScheme: Hashable {
    let background: Int
    let text: Int
    let bar: Int
}

/// Colori dell'icona chiara e di quella scura.
struct AppIconSchemes: Hashable {
    let light: AppIconScheme
    let dark: AppIconScheme
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
    var text: Color
    var bar: Color
}

/// Colori delle icone, gli stessi per l'anteprima e per le icone di Icon Composer del generatore.
/// Sono i ruoli di Material 3 del tema di ogni colore d'accento proposto in Aspetto (stile Tonal
/// Spot, contrasto standard, come li genera `bcw-theme.js`), colorati come il logo dell'introduzione
/// (richiesta dell'utente, 3.3): sfondo nel contenitore primario, scritta nel colore del testo
/// (`on-surface`), barra nel colore del marchio (`brand`), per il tema chiaro e per quello scuro; con
/// le icone scure lo sfondo è quello scuro di iOS.
/// Se cambiano i colori dei temi vanno ricalcolati (lo dice il generatore, `BCW-APPICONS`).
enum AppIconPalette {
    static let schemes: [AppIconColor: AppIconSchemes] = [
        .mattone: AppIconSchemes(light: AppIconScheme(background: 0xFAAA9D, text: 0x3E2F2C, bar: 0xA23E2F),
                                 dark: AppIconScheme(background: 0x76453D, text: 0xF9E0DC, bar: 0xE28070)),
        .arancio: AppIconSchemes(light: AppIconScheme(background: 0xFEB788, text: 0x3D3027, bar: 0x964900),
                                 dark: AppIconScheme(background: 0x73482B, text: 0xF8E1D5, bar: 0xD9884E)),
        .oro: AppIconSchemes(light: AppIconScheme(background: 0xFEE090, text: 0x373225, bar: 0x745B00),
                             dark: AppIconScheme(background: 0x62511F, text: 0xEFE4D1, bar: 0xB4984A)),
        .verde: AppIconSchemes(light: AppIconScheme(background: 0xB5F0C9, text: 0x2C352E, bar: 0x196B45),
                               dark: AppIconScheme(background: 0x335B43, text: 0xDEE8DE, bar: 0x6FA785)),
        .petrolio: AppIconSchemes(light: AppIconScheme(background: 0xA8EFF4, text: 0x2A3435, bar: 0x00696F),
                                  dark: AppIconScheme(background: 0x255A5E, text: 0xDDE8E8, bar: 0x6BA5A9)),
        .blu: AppIconSchemes(light: AppIconScheme(background: 0xADCBFA, text: 0x2E333A, bar: 0x1B5FA7),
                             dark: AppIconScheme(background: 0x3E5373, text: 0xE2E5EF, bar: 0x769DD6)),
        .indaco: AppIconSchemes(light: AppIconScheme(background: 0xC2C1F9, text: 0x32313B, bar: 0x5555A9),
                                dark: AppIconScheme(background: 0x4F4F74, text: 0xE7E4F0, bar: 0x9595D8)),
        .viola: AppIconSchemes(light: AppIconScheme(background: 0xECC7FE, text: 0x373039, bar: 0x7E44A4),
                               dark: AppIconScheme(background: 0x604A6D, text: 0xEDE2EE, bar: 0xB889D5)),
        .rosa: AppIconSchemes(light: AppIconScheme(background: 0xFAAFC4, text: 0x3C2F32, bar: 0xA4355F),
                              dark: AppIconScheme(background: 0x734552, text: 0xF6E0E4, bar: 0xE17C9C)),
        .ardesia: AppIconSchemes(light: AppIconScheme(background: 0xADD2FE, text: 0x2E333A, bar: 0x535F6E),
                                 dark: AppIconScheme(background: 0x395571, text: 0xE1E6EF, bar: 0x939CA8)),
    ]
    /// Sfondo scuro delle icone scure e colorate di iOS (misurato sul simulatore con iOS 26): nelle icone
    /// vere lo mette iOS (`automatic`), qui serve per l'anteprima.
    static let systemDark = AppIconBackground.gradient(Color(platformColor: PlatformColor(hex: 0x2E2E30)),
                                                       Color(platformColor: PlatformColor(hex: 0x111112)))
    /// Grigi della scritta e della barra nelle icone colorate e trasparenti (iOS tinge la scala di
    /// grigi): la scritta resta il livello più chiaro, la barra si vede ma resta distinta (con 0,3
    /// spariva quasi, controllato con `ictool`).
    static let tintedText: CGFloat = 1
    static let tintedBar: CGFloat = 0.6

    static func scheme(for color: AppIconColor, dark: Bool) -> AppIconScheme {
        let schemes = color.palette ?? schemes[.mattone]!
        return dark ? schemes.dark : schemes.light
    }

    /// Colori dell'icona in una modalità delle icone di iOS.
    static func colors(for choice: AppIconChoice, mode: AppIconPreview.Mode) -> AppIconColors {
        func color(_ hex: Int) -> Color { Color(platformColor: PlatformColor(hex: hex)) }
        switch mode {
        case .light:
            let scheme = scheme(for: choice.color, dark: false)
            return AppIconColors(background: .solid(color(scheme.background)), text: color(scheme.text), bar: color(scheme.bar))
        case .dark:
            let scheme = scheme(for: choice.color, dark: true)
            return AppIconColors(background: systemDark, text: color(scheme.text), bar: color(scheme.bar))
        case .tinted:
            return AppIconColors(background: .clear, text: Color(white: tintedText), bar: Color(white: tintedBar))
        }
    }
}

// MARK: - Disegno

/// Proporzioni dell'icona, in frazioni della tela (1024 punti per iOS). Le stesse per
/// l'anteprima e per i livelli delle icone di Icon Composer.
enum AppIconGeometry {
    /// Larghezza della scritta "BCW" rispetto alla tela.
    static let text: CGFloat = 0.66
    /// Spostamento verso il basso dell'insieme, rispetto alla tela: centrato a misura sembrava troppo in
    /// alto (la scritta pesa più della barra sottile), così appare centrato (richiesta dell'utente).
    static let opticalOffset: CGFloat = 0.022
    /// Altezza della barra rispetto alla larghezza (come nel logo: 0,15 × 1,1 della misura del testo).
    static let barAspect: CGFloat = 0.15 / 1.1
    /// Raggio degli angoli della maschera delle icone di iOS (solo per l'anteprima).
    static let mask: CGFloat = 0.2237
}

/// Il logo dell'introduzione (`BCWLogo(stacked: true)`) come tracciati: la scritta "BCW" in Google
/// Sans Flex (peso 800, arrotondata, con la stessa spaziatura) e sotto, centrata, la barra larga
/// 1,1 volte la misura del testo e alta 0,15, a 0,3 dalla linea di base (misure prese
/// dall'introduzione). In frazioni della tela, con il centro dell'insieme in (0, 0) e le y verso il
/// basso (più `AppIconGeometry.opticalOffset`); gli stessi tracciati per l'anteprima e per gli SVG del
/// generatore.
enum AppIconLogo {
    struct Shapes {
        let text: CGPath
        let bar: CGRect
    }

    static let shapes: Shapes = make()

    private static func make() -> Shapes {
        let size: CGFloat = 1000
        let font = Typography.ctFont(size: size, weight: 800, rond: 100)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): -size * 0.01,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "BCW", attributes: attributes))
        let glyphs = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                // Core Text ha le y verso l'alto: si capovolgono, con la linea di base a 0.
                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[index].x, ty: -positions[index].y)
                if let glyph = CTFontCreatePathForGlyph(font, ids[index], &transform) { glyphs.addPath(glyph) }
            }
        }
        let box = glyphs.boundingBoxOfPath
        let bar = CGRect(x: box.midX - size * 0.55, y: size * 0.3, width: size * 1.1, height: size * 0.15)
        let top = box.minY, bottom = bar.maxY
        let scale = AppIconGeometry.text / max(box.width, 1)
        let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -box.midX, y: -(top + bottom) / 2)
            .concatenating(CGAffineTransform(translationX: 0, y: AppIconGeometry.opticalOffset))
        return Shapes(text: glyphs.copy(using: [transform]) ?? glyphs, bar: bar.applying(transform))
    }

    /// La scritta in una tela di lato `rect.width`, centrata nel rettangolo.
    struct Text: Shape {
        func path(in rect: CGRect) -> Path {
            let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: rect.width, y: rect.width)
            return Path(AppIconLogo.shapes.text).applying(transform)
        }
    }

    /// La barra (una pillola) in una tela di lato `rect.width`, centrata nel rettangolo.
    struct Bar: Shape {
        func path(in rect: CGRect) -> Path {
            let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: rect.width, y: rect.width)
            let bar = AppIconLogo.shapes.bar.applying(transform)
            return Path(roundedRect: bar, cornerRadius: bar.height / 2, style: .circular)
        }
    }
}

/// Disegno dell'icona a tutta tela (senza maschera) per l'anteprima: sfondo, scritta e barra come
/// due lastre, con un riflesso in alto e un'ombra leggera, per somigliare al vetro che iOS dà alle
/// icone di Icon Composer.
struct AppIconArtwork: View {
    let colors: AppIconColors
    let size: CGFloat
    /// Riflessi e ombre delle lastre (non per lo sfondo da solo).
    var glass = true

    var body: some View {
        ZStack {
            switch colors.background {
            case .solid(let color): Rectangle().fill(color)
            case .gradient(let top, let bottom): Rectangle().fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            case .clear: Color.clear
            }
            plate(AppIconLogo.Text(), colors.text)
            plate(AppIconLogo.Bar(), colors.bar)
        }
        .frame(width: size, height: size)
    }

    /// Una lastra: la forma piena con la luce dall'alto e un'ombra leggera. Niente bordo: i glifi del
    /// carattere variabile hanno contorni sovrapposti, che il tratto mostrerebbe dentro le lettere.
    private func plate(_ shape: some Shape, _ color: Color) -> some View {
        ZStack {
            shape.fill(color)
            if glass {
                shape.fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0), .black.opacity(0.06)],
                                          startPoint: .top, endPoint: .bottom))
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(glass ? 0.2 : 0), radius: size / 60, y: size / 100)
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
                AppIconArtwork(colors: AppIconColors(background: AppIconPalette.systemDark, text: .clear, bar: .clear),
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
