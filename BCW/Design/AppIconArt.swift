import SwiftUI

// MARK: - Icona dell'app: opzioni (Impostazioni › Aspetto › Icona dell'app)

/// Forma di Material che contiene la barra del logo. `classic` è l'icona di prima: solo la barra
/// su sfondo crema, senza forma.
///
/// Ogni forma pesa: 50 icone piatte (10 colori × 5 varianti), circa 5 MB nel catalogo compilato
/// (metà per dispositivo dopo lo sfoltimento dell'App Store). Dopo aver aggiunto o tolto una forma
/// va rigenerato il catalogo `AppIcons.xcassets` (vedi `AppIconGenerator`).
enum AppIconShape: String, CaseIterable, Identifiable {
    case circle, cookie4, cookie6, cookie9, clover4, clover8, sunny, gem, classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: "Cerchio"
        case .gem: "Gemma"
        case .cookie4: "Biscotto a 4 lati"
        case .cookie6: "Biscotto a 6 lati"
        case .cookie9: "Biscotto a 9 lati"
        case .clover4: "Quadrifoglio"
        case .clover8: "Fiore a 8 petali"
        case .sunny: "Sole"
        case .classic: "Classica"
        }
    }

    /// Forma di Material 3 Expressive (`nil` per l'icona classica).
    var material: MaterialShapeName? {
        switch self {
        case .circle: .circle
        case .gem: .gem
        case .cookie4: .cookie4Sided
        case .cookie6: .cookie6Sided
        case .cookie9: .cookie9Sided
        case .clover4: .clover4Leaf
        case .clover8: .clover8Leaf
        case .sunny: .sunny
        case .classic: nil
        }
    }

    /// Rotazione della forma (gradi): i lobi stanno ai lati della barra invece che sopra.
    var rotation: Double {
        switch self {
        case .cookie4, .clover4: 45
        case .cookie6: 30
        default: 0
        }
    }
}

/// Colore dell'icona: quello del tema (il colore proposto più vicino all'accento) o uno dei
/// colori proposti in Aspetto.
enum AppIconColor: String, CaseIterable, Identifiable {
    case theme, mattone, arancio, oro, verde, petrolio, blu, indaco, viola, rosa, ardesia

    var id: String { rawValue }

    /// I colori fissi, nell'ordine di `accentPresets`.
    static let presets: [AppIconColor] = allCases.filter { $0 != .theme }

    /// Colore d'accento corrispondente (`nil` per il tema).
    var hex: String? {
        guard let index = Self.presets.firstIndex(of: self) else { return nil }
        return accentPresets[index].hex
    }

    var title: String {
        guard let index = Self.presets.firstIndex(of: self) else { return "Tema dell'app" }
        return accentPresets[index].name
    }

    /// Il colore proposto più vicino a un colore qualsiasi, per tonalità e croma (HCT di
    /// Material). Il croma conta fino a 36, quello dei colori di Tonal Spot: i colori vivaci
    /// vanno sulla tonalità più vicina, quelli quasi grigi su Ardesia.
    static func nearest(to accent: String) -> AppIconColor {
        let hex = ThemeStore.normalize(accent) ?? defaultAccent
        if let cached = nearestCache[hex] { return cached }
        if let index = accentPresets.firstIndex(where: { $0.hex == hex }) { return presets[index] }
        guard let target = ColorEngine.shared.hueChroma(hex) else { return .mattone }
        func point(_ value: (hue: Double, chroma: Double)) -> CGPoint {
            let radius = min(value.chroma, 36)
            let angle = value.hue * .pi / 180
            return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
        let origin = point(target)
        var best = AppIconColor.mattone
        var bestDistance = Double.infinity
        for color in presets {
            guard let preset = color.hex.flatMap(ColorEngine.shared.hueChroma) else { continue }
            let p = point(preset)
            let distance = hypot(p.x - origin.x, p.y - origin.y)
            if distance < bestDistance {
                bestDistance = distance
                best = color
            }
        }
        nearestCache[hex] = best
        return best
    }

    private static var nearestCache: [String: AppIconColor] = [:]
}

/// Aspetto dell'icona rispetto alla modalità delle icone di iOS (chiare, scure, colorate).
enum AppIconAppearance: String, CaseIterable, Identifiable {
    case automatic = "auto", light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatico"
        case .light: "Sempre chiaro"
        case .dark: "Sempre scuro"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: "Chiaro o scuro come le icone di iOS"
        case .light: "Colori chiari anche con le icone scure di iOS"
        case .dark: "Colori scuri anche con le icone chiare di iOS"
        }
    }
}

/// Sfondo dell'icona scura: quello scuro del tema (Material) o quello standard delle icone di iOS.
enum AppIconDarkBackground: String, CaseIterable, Identifiable {
    case material, system = "ios"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .material: "Material"
        case .system: "iOS"
        }
    }
}

// MARK: - Varianti e immagini

/// Una delle immagini piatte di un'icona.
enum AppIconRendition: String, CaseIterable {
    /// Colori chiari del tema.
    case light
    /// Colori scuri del tema, sullo sfondo scuro del tema.
    case dark
    /// Colori scuri su sfondo trasparente: iOS ci mette il suo sfondo scuro.
    case darkSystem
    /// Colori scuri su uno sfondo opaco simile a quello scuro di iOS (per "Scuro" anche con le
    /// icone chiare di iOS, dove iOS non mette il suo sfondo).
    case darkSystemOpaque
    /// Scala di grigi su sfondo trasparente: iOS la tinge (icone colorate) o ne fa vetro
    /// (icone trasparenti).
    case tinted

    var isOpaque: Bool { self == .light || self == .dark || self == .darkSystemOpaque }
}

/// Combinazione di Aspetto e Sfondo scuro: una serie di icone per ogni forma e colore.
enum AppIconVariant: String, CaseIterable {
    case auto, autoios, chiaro, scuro, scuroios

    init(appearance: AppIconAppearance, darkBackground: AppIconDarkBackground) {
        switch (appearance, darkBackground) {
        case (.automatic, .material): self = .auto
        case (.automatic, .system): self = .autoios
        case (.light, _): self = .chiaro
        case (.dark, .material): self = .scuro
        case (.dark, .system): self = .scuroios
        }
    }

    /// Immagini per le icone chiare, scure e colorate di iOS.
    var light: AppIconRendition {
        switch self {
        case .auto, .autoios, .chiaro: .light
        case .scuro: .dark
        case .scuroios: .darkSystemOpaque
        }
    }

    var dark: AppIconRendition {
        switch self {
        case .auto, .scuro: .dark
        case .autoios, .scuroios: .darkSystem
        case .chiaro: .light
        }
    }

    var tinted: AppIconRendition { .tinted }
}

/// Icona scelta: forma, colore già risolto (mai `.theme`) e variante.
struct AppIconChoice: Hashable {
    var shape: AppIconShape
    var color: AppIconColor
    var variant: AppIconVariant

    /// Combinazione dell'icona principale (`AppIcon.icon`, a livelli di vetro).
    static let primary = AppIconChoice(shape: .circle, color: .mattone, variant: .auto)

    /// Nome dell'icona alternativa nel catalogo `AppIcons.xcassets` (`nil` = icona principale).
    var assetName: String? {
        if self == .primary { return nil }
        if shape == .classic { return "AppIcon-classica-\(variant.rawValue)" }
        return "AppIcon-\(shape.rawValue)-\(color.rawValue)-\(variant.rawValue)"
    }

    /// Tutte le icone alternative (per il generatore).
    static var allAlternates: [AppIconChoice] {
        var all: [AppIconChoice] = []
        for shape in AppIconShape.allCases where shape != .classic {
            for color in AppIconColor.presets {
                for variant in AppIconVariant.allCases {
                    let choice = AppIconChoice(shape: shape, color: color, variant: variant)
                    if choice != .primary { all.append(choice) }
                }
            }
        }
        for variant in AppIconVariant.allCases {
            all.append(AppIconChoice(shape: .classic, color: .mattone, variant: variant))
        }
        return all
    }
}

// MARK: - Colori

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

enum AppIconPalette {
    /// Sfondo scuro delle icone di iOS (misurato sul simulatore con iOS 26), per l'icona scura
    /// con le icone chiare di iOS.
    static let systemDark = AppIconBackground.gradient(Color(platformColor: PlatformColor(hex: 0x2E2E30)),
                                                       Color(platformColor: PlatformColor(hex: 0x111112)))
    /// Grigio della forma nell'immagine colorata (e trasparente): la barra, bianca, resta il livello
    /// più chiaro. iOS schiarisce i grigi tingendoli: con 0,45 la forma diventava quasi bianca e la
    /// barra si vedeva appena (verificato sul simulatore), con 0,3 forma e barra restano distinte.
    static let tintedShapeWhite: CGFloat = 0.3
    static let tintedShape = Color(white: tintedShapeWhite)

    /// Colori di un'immagine. Chiara: sfondo surface, forma primary, barra on-primary (la forma
    /// si stacca bene dallo sfondo anche in piccolo, e la barra bianca resta il segno di BCW).
    /// Scura: sfondo surface-dim, forma primary-container, barra primary del tema scuro (toni
    /// bassi come le icone scure di iOS, con la barra chiara come nella versione chiara).
    static func colors(for choice: AppIconChoice, rendition: AppIconRendition) -> AppIconColors {
        if choice.shape == .classic { return classic(rendition) }
        let scheme = scheme(for: choice.color)
        func color(_ values: SchemeValues, _ role: String) -> Color { Color(platformColor: PlatformColor(hex: values.color(role))) }
        switch rendition {
        case .light:
            return AppIconColors(background: .solid(color(scheme.light, "surface")),
                                 shape: color(scheme.light, "primary"), bar: color(scheme.light, "on-primary"))
        case .dark, .darkSystem, .darkSystemOpaque:
            let background: AppIconBackground = switch rendition {
            case .dark: .solid(color(scheme.dark, "surface-dim"))
            case .darkSystemOpaque: systemDark
            default: .clear
            }
            return AppIconColors(background: background, shape: color(scheme.dark, "primary-container"),
                                 bar: color(scheme.dark, "primary"))
        case .tinted:
            return AppIconColors(background: .clear, shape: tintedShape, bar: .white)
        }
    }

    /// L'icona di prima (`AppIcon.icon` fino alla versione 3.1): barra mattone su crema.
    private static func classic(_ rendition: AppIconRendition) -> AppIconColors {
        let brand = Color(platformColor: PlatformColor(hex: 0xA23E2F))
        let brandDark = Color(platformColor: PlatformColor(hex: 0xE3826A))
        switch rendition {
        case .light:
            return AppIconColors(background: .gradient(Color(platformColor: PlatformColor(hex: 0xFFFCF6)),
                                                       Color(platformColor: PlatformColor(hex: 0xF7F2E8))),
                                 shape: .clear, bar: brand)
        case .dark: return AppIconColors(background: .solid(Color(platformColor: PlatformColor(hex: 0x130D0B))), shape: .clear, bar: brandDark)
        case .darkSystem: return AppIconColors(background: .clear, shape: .clear, bar: brandDark)
        case .darkSystemOpaque: return AppIconColors(background: systemDark, shape: .clear, bar: brandDark)
        case .tinted: return AppIconColors(background: .clear, shape: .clear, bar: .white)
        }
    }

    /// Schema di Material (Tonal Spot, contrasto standard) di un colore proposto.
    static func scheme(for color: AppIconColor) -> (light: SchemeValues, dark: SchemeValues) {
        let hex = color.hex ?? defaultAccent
        if let cached = schemes[hex] { return cached }
        let built = ColorEngine.shared.build(signature: "\(hex)|tonalSpot|standard")
            ?? (SchemeValues(roles: [:]), SchemeValues(roles: [:]))
        schemes[hex] = built
        return built
    }

    private static var schemes: [String: (light: SchemeValues, dark: SchemeValues)] = [:]
}

// MARK: - Disegno

/// Proporzioni dell'icona, in frazioni della tela (1024 punti per iOS). Le stesse per
/// l'anteprima, le icone piatte del generatore e i livelli di `AppIcon.icon`.
enum AppIconGeometry {
    /// Lato della forma rispetto alla tela.
    static let shape: CGFloat = 0.86
    /// Larghezza della barra rispetto alla forma.
    static let bar: CGFloat = 0.77
    /// Larghezza della barra dell'icona classica rispetto alla tela (come `AppIcon.icon` fino alla 3.1).
    static let classicBar: CGFloat = 0.75
    /// Altezza della barra rispetto alla larghezza (rettangolo 64 × 8,73 del logo, a pillola).
    static let barAspect: CGFloat = 8.73 / 64
    /// Raggio degli angoli della maschera delle icone di iOS (solo per l'anteprima).
    static let mask: CGFloat = 0.2237
}

/// Disegno dell'icona a tutta tela (senza maschera): sfondo, forma di Material e barra al centro.
/// Lo usano sia l'anteprima sia il generatore delle icone piatte, così sono identiche.
struct AppIconArtwork: View {
    let shape: AppIconShape
    let colors: AppIconColors
    let size: CGFloat

    var body: some View {
        let barWidth = size * (shape.material == nil ? AppIconGeometry.classicBar : AppIconGeometry.shape * AppIconGeometry.bar)
        ZStack {
            switch colors.background {
            case .solid(let color): Rectangle().fill(color)
            case .gradient(let top, let bottom): Rectangle().fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            case .clear: Color.clear
            }
            if let material = shape.material {
                AppIconShapeOutline(name: material, rotation: shape.rotation)
                    .fill(colors.shape)
                    .frame(width: size * AppIconGeometry.shape, height: size * AppIconGeometry.shape)
            }
            // Il rettangolo del logo ha raggio pari a metà altezza (archi di cerchio, come l'SVG).
            Capsule(style: .circular)
                .fill(colors.bar)
                .frame(width: barWidth, height: barWidth * AppIconGeometry.barAspect)
        }
        .frame(width: size, height: size)
    }
}

/// Forma di Material ruotata attorno al centro.
struct AppIconShapeOutline: Shape {
    let name: MaterialShapeName
    var rotation: Double = 0

    func path(in rect: CGRect) -> Path {
        let unit = MaterialShape.unitPath(name)
        let rotated = rotation == 0 ? unit : unit.applying(
            CGAffineTransform(translationX: 50, y: 50)
                .rotated(by: rotation * .pi / 180)
                .translatedBy(x: -50, y: -50))
        return rotated.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / 100, y: rect.height / 100))
    }
}

/// Icona come la mostra iOS in una modalità delle icone (chiara, scura o colorata), con la
/// maschera della Home: per l'anteprima e le celle della pagina Icona dell'app.
struct AppIconPreview: View {
    enum Mode { case light, dark, tinted }

    let choice: AppIconChoice
    let mode: Mode
    let size: CGFloat
    /// Tinta delle icone colorate.
    var tint: Color = .white

    var body: some View {
        let mask = RoundedRectangle(cornerRadius: size * AppIconGeometry.mask, style: .continuous)
        ZStack {
            switch mode {
            case .light:
                artwork(choice.variant.light)
            case .dark:
                artwork(choice.variant.dark)
            case .tinted:
                // iOS tinge la scala di grigi sul suo sfondo scuro.
                AppIconArtwork(shape: choice.shape, colors: AppIconColors(background: AppIconPalette.systemDark, shape: .clear, bar: .clear), size: size)
                AppIconArtwork(shape: choice.shape, colors: AppIconPalette.colors(for: choice, rendition: .tinted), size: size)
                    .colorMultiply(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(mask)
        .overlay(mask.strokeBorder(Color.white.opacity(mode == .light ? 0 : 0.08), lineWidth: max(0.5, size / 120)))
        .compositingGroup()
    }

    @ViewBuilder
    private func artwork(_ rendition: AppIconRendition) -> some View {
        if rendition == .darkSystem {
            // Sfondo trasparente: in anteprima quello scuro di iOS.
            AppIconArtwork(shape: choice.shape, colors: AppIconPalette.colors(for: choice, rendition: .darkSystemOpaque), size: size)
        } else {
            AppIconArtwork(shape: choice.shape, colors: AppIconPalette.colors(for: choice, rendition: rendition), size: size)
        }
    }
}
