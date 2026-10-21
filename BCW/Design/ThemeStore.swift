import SwiftUI
import JavaScriptCore

// MARK: - Opzioni dell'aspetto (Impostazioni › Aspetto, come nella versione web)

/// Colori d'accento proposti (il primo è quello di BCW).
let accentPresets: [(hex: String, name: String)] = [
    ("#a23e2f", "Mattone (BCW)"),
    ("#c0661b", "Arancio"),
    ("#9a7b12", "Oro"),
    ("#2f7d55", "Verde"),
    ("#1f7a80", "Petrolio"),
    ("#2f6db5", "Blu"),
    ("#5b5bb0", "Indaco"),
    ("#8a4fb0", "Viola"),
    ("#b8456f", "Rosa"),
    ("#5f6b7a", "Ardesia"),
]

let defaultAccent = "#a23e2f"

/// Stili degli schemi dinamici di Material 3.
enum ColorStyle: String, CaseIterable, Identifiable {
    case tonalSpot, vibrant, expressive, fidelity, neutral, rainbow, fruitSalad
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tonalSpot: "Tonale"
        case .vibrant: "Vivace"
        case .expressive: "Espressivo"
        case .fidelity: "Fedele"
        case .neutral: "Neutro"
        case .rainbow: "Arcobaleno"
        case .fruitSalad: "Macedonia"
        }
    }

    var subtitle: String {
        switch self {
        case .tonalSpot: "Toni pacati"
        case .vibrant: "Colori più saturi"
        case .expressive: "Accostamenti audaci"
        case .fidelity: "Vicino al colore scelto"
        case .neutral: "Toni quasi grigi"
        case .rainbow: "Superfici neutre"
        case .fruitSalad: "Tonalità diverse"
        }
    }
}

enum ContrastLevel: String, CaseIterable, Identifiable {
    case standard, medium, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Standard"
        case .medium: "Medio"
        case .high: "Alto"
        }
    }
}

enum CornerStyle: String, CaseIterable, Identifiable {
    case square, standard, round
    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: "Meno arrotondati"
        case .standard: "Standard"
        case .round: "Più arrotondati"
        }
    }
}

enum MotionStyle: String, CaseIterable, Identifiable {
    case expressive, standard, reduced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expressive: "Espressive"
        case .standard: "Standard"
        case .reduced: "Ridotte"
        }
    }
}

enum RoundedText: String, CaseIterable, Identifiable {
    case titles, all, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .titles: "Solo i titoli"
        case .all: "Tutto il testo"
        case .none: "Nessuno"
        }
    }
}

// MARK: - Ruoli dei colori

/// Valori esadecimali dei ruoli di Material 3 per un tema (chiaro o scuro).
struct SchemeValues: Codable, Equatable {
    var roles: [String: String]

    func color(_ role: String) -> Int {
        guard let hex = roles[role] else { return 0x808080 }
        return Int(hex.dropFirst(), radix: 16) ?? 0x808080
    }
}

/// Colori del tema in uso: ogni ruolo è un colore che cambia tra chiaro e scuro.
struct SchemeColors {
    let primary, onPrimary, primaryContainer, onPrimaryContainer: Color
    let secondary, onSecondary, secondaryContainer, onSecondaryContainer: Color
    let tertiary, onTertiary, tertiaryContainer, onTertiaryContainer: Color
    let error, onError, errorContainer, onErrorContainer: Color
    let surface, surfaceDim, surfaceBright: Color
    let surfaceContainerLowest, surfaceContainerLow, surfaceContainer, surfaceContainerHigh, surfaceContainerHighest: Color
    let onSurface, onSurfaceVariant, outline, outlineVariant: Color
    let inverseSurface, inverseOnSurface, inversePrimary: Color
    let brand: Color
    let shadow: Color
    let scrim: Color

    init(light: SchemeValues, dark: SchemeValues) {
        func c(_ role: String) -> Color { Theme.dynamic(light: light.color(role), dark: dark.color(role)) }
        primary = c("primary"); onPrimary = c("on-primary")
        primaryContainer = c("primary-container"); onPrimaryContainer = c("on-primary-container")
        secondary = c("secondary"); onSecondary = c("on-secondary")
        secondaryContainer = c("secondary-container"); onSecondaryContainer = c("on-secondary-container")
        tertiary = c("tertiary"); onTertiary = c("on-tertiary")
        tertiaryContainer = c("tertiary-container"); onTertiaryContainer = c("on-tertiary-container")
        error = c("error"); onError = c("on-error")
        errorContainer = c("error-container"); onErrorContainer = c("on-error-container")
        surface = c("surface"); surfaceDim = c("surface-dim"); surfaceBright = c("surface-bright")
        surfaceContainerLowest = c("surface-container-lowest")
        surfaceContainerLow = c("surface-container-low")
        surfaceContainer = c("surface-container")
        surfaceContainerHigh = c("surface-container-high")
        surfaceContainerHighest = c("surface-container-highest")
        onSurface = c("on-surface"); onSurfaceVariant = c("on-surface-variant")
        outline = c("outline"); outlineVariant = c("outline-variant")
        inverseSurface = c("inverse-surface"); inverseOnSurface = c("inverse-on-surface")
        inversePrimary = c("inverse-primary")
        brand = c("brand")
        shadow = c("shadow")
        scrim = Theme.dynamic(light: light.color("shadow"), dark: dark.color("shadow"), lightAlpha: 0.38, darkAlpha: 0.55)
    }
}

/// Colori predefiniti di BCW (gli stessi di `css/bcw.css`): schema Tonal Spot dal rosso mattone.
private enum DefaultScheme {
    static let light = SchemeValues(roles: [
        "primary": "#8c4e43", "on-primary": "#fff7f6", "primary-container": "#faaa9d", "on-primary-container": "#602b22",
        "secondary": "#785751", "on-secondary": "#fff7f6", "secondary-container": "#ffdad4", "on-secondary-container": "#694a45",
        "tertiary": "#795927", "on-tertiary": "#fff8f2", "tertiary-container": "#f6cb8d", "on-tertiary-container": "#5f4211",
        "error": "#a8364b", "on-error": "#fff7f7", "error-container": "#f97386", "on-error-container": "#6e0523",
        "surface": "#fff8f6", "surface-dim": "#edd5d1", "surface-bright": "#fff8f6",
        "surface-container-lowest": "#fffcfb", "surface-container-low": "#fff0ee", "surface-container": "#fee9e6",
        "surface-container-high": "#fae3df", "surface-container-highest": "#f6ddd9",
        "on-surface": "#3e2f2c", "on-surface-variant": "#6d5b58", "outline": "#8a7673", "outline-variant": "#e3cdc9",
        "inverse-surface": "#392e2c", "inverse-on-surface": "#ffedea", "inverse-primary": "#faaa9d",
        "brand": "#a23e2f", "shadow": "#1d110f",
    ])

    static let dark = SchemeValues(roles: [
        "primary": "#f9b6ab", "on-primary": "#61342c", "primary-container": "#76453d", "on-primary-container": "#ffdbd5",
        "secondary": "#e7bdb6", "on-secondary": "#563934", "secondary-container": "#51342f", "on-secondary-container": "#f2cbc4",
        "tertiary": "#ffdaa8", "on-tertiary": "#694a19", "tertiary-container": "#6b4c1a", "on-tertiary-container": "#ffdeb0",
        "error": "#f97386", "on-error": "#490013", "error-container": "#871c34", "on-error-container": "#ffb0bb",
        "surface": "#130d0b", "surface-dim": "#130d0b", "surface-bright": "#372926",
        "surface-container-lowest": "#0e0908", "surface-container-low": "#1a1110", "surface-container": "#221715",
        "surface-container-high": "#291d1b", "surface-container-highest": "#302220",
        "on-surface": "#f9e0dc", "on-surface-variant": "#bca6a2", "outline": "#84716e", "outline-variant": "#4a3a37",
        "inverse-surface": "#f1dfdb", "inverse-on-surface": "#392e2c", "inverse-primary": "#8c4e43",
        "brand": "#e3826a", "shadow": "#080403",
    ])
}

// MARK: - Raggi degli angoli

/// Raggi degli angoli (`--r-*` di `css/bcw.css`), che cambiano con Impostazioni › Aspetto › Angoli.
struct CornerRadii: Equatable {
    let xs, s, m, l, li, xl, xli, xxl: CGFloat

    static func of(_ style: CornerStyle) -> CornerRadii {
        switch style {
        case .square: CornerRadii(xs: 2, s: 4, m: 8, l: 10, li: 12, xl: 16, xli: 20, xxl: 28)
        case .standard: CornerRadii(xs: 4, s: 8, m: 12, l: 16, li: 20, xl: 28, xli: 32, xxl: 48)
        case .round: CornerRadii(xs: 6, s: 12, m: 16, l: 22, li: 26, xl: 34, xli: 38, xxl: 56)
        }
    }
}

// MARK: - Archivio dell'aspetto

/// Aspetto scelto nelle Impostazioni: colori generati dal colore d'accento (schemi dinamici di
/// Material 3, come la versione web), angoli, animazioni, caratteri e Liquid Glass.
///
/// È osservabile: le viste che leggono un colore o un raggio (anche tramite `Theme`) si
/// ridisegnano da sole quando cambia l'aspetto.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Avvisato quando cambia un'impostazione sincronizzata con l'account BCW (`CloudSync`).
    @ObservationIgnored var onSyncedChange: (() -> Void)?
    /// `true` mentre si applicano le impostazioni arrivate dal server: niente avvisi.
    @ObservationIgnored private var applyingRemote = false

    private(set) var colors: SchemeColors
    private(set) var radii: CornerRadii

    var accentColor: String {
        didSet { defaults.set(accentColor, forKey: "accentColor"); regenerate(); syncedChanged() }
    }
    var colorStyle: ColorStyle {
        didSet { defaults.set(colorStyle.rawValue, forKey: "colorStyle"); regenerate(); syncedChanged() }
    }
    var contrast: ContrastLevel {
        didSet { defaults.set(contrast.rawValue, forKey: "contrast"); regenerate(); syncedChanged() }
    }
    var corners: CornerStyle {
        didSet { defaults.set(corners.rawValue, forKey: "corners"); radii = .of(corners); syncedChanged() }
    }
    var motion: MotionStyle {
        didSet { defaults.set(motion.rawValue, forKey: "motion"); syncedChanged() }
    }
    var roundedText: RoundedText {
        didSet { defaults.set(roundedText.rawValue, forKey: "roundedText"); configureSystemBars(); syncedChanged() }
    }
    /// Liquid Glass: barre e pulsanti dei menu di sistema invece di quelli di Material.
    var liquidGlass: Bool {
        didSet { defaults.set(liquidGlass, forKey: "liquidGlass") }
    }

    // Icona dell'app (Impostazioni › Aspetto › Icona dell'app), sincronizzata con l'account BCW.
    // La applica `AppIconController`.
    var appIconShape: AppIconShape {
        didSet { defaults.set(appIconShape.rawValue, forKey: "appIconShape"); syncedChanged() }
    }
    var appIconColor: AppIconColor {
        didSet { defaults.set(appIconColor.rawValue, forKey: "appIconColor"); syncedChanged() }
    }
    var appIconAppearance: AppIconAppearance {
        didSet { defaults.set(appIconAppearance.rawValue, forKey: "appIconAppearance"); syncedChanged() }
    }
    var appIconDarkBackground: AppIconDarkBackground {
        didSet { defaults.set(appIconDarkBackground.rawValue, forKey: "appIconDarkBackground"); syncedChanged() }
    }

    /// Icona scelta, con il colore del tema già risolto (il colore proposto più vicino all'accento).
    var appIconChoice: AppIconChoice {
        AppIconChoice(shape: appIconShape,
                      color: appIconColor == .theme ? AppIconColor.nearest(to: accentColor) : appIconColor,
                      variant: AppIconVariant(appearance: appIconAppearance, darkBackground: appIconDarkBackground))
    }

    var appIconIsDefault: Bool {
        appIconShape == .circle && appIconColor == .theme && appIconAppearance == .automatic && appIconDarkBackground == .material
    }

    /// Ripristina l'icona di BCW (cerchio, colore del tema, automatica, sfondo scuro Material).
    func resetAppIcon() {
        appIconShape = .circle
        appIconColor = .theme
        appIconAppearance = .automatic
        appIconDarkBackground = .material
    }

    /// Asse ROND dei titoli e del testo.
    var rond: CGFloat { roundedText == .none ? 0 : 100 }
    var rondBody: CGFloat {
        switch roundedText {
        case .titles: 30
        case .all: 100
        case .none: 0
        }
    }

    /// Firma delle impostazioni che decidono i colori: se cambia, i colori vanno rigenerati.
    private var signature: String { [Self.normalize(accentColor) ?? defaultAccent, colorStyle.rawValue, contrast.rawValue].joined(separator: "|") }
    private static let defaultSignature = [defaultAccent, ColorStyle.tonalSpot.rawValue, ContrastLevel.standard.rawValue].joined(separator: "|")

    private init() {
        let defaults = UserDefaults.standard
        let corners = CornerStyle(rawValue: defaults.string(forKey: "corners") ?? "") ?? .standard
        colors = SchemeColors(light: DefaultScheme.light, dark: DefaultScheme.dark)
        radii = .of(corners)
        #if DEBUG
        // Per le prove: `-BCWAccent #2f6db5` usa un altro colore senza salvarlo. Va letto qui: una
        // seconda assegnazione nell'init passa da `didSet`, che configura le barre e rilegge `shared`
        // mentre si crea (crash all'avvio).
        accentColor = defaults.string(forKey: "BCWAccent") ?? defaults.string(forKey: "accentColor") ?? defaultAccent
        #else
        accentColor = defaults.string(forKey: "accentColor") ?? defaultAccent
        #endif
        colorStyle = ColorStyle(rawValue: defaults.string(forKey: "colorStyle") ?? "") ?? .tonalSpot
        contrast = ContrastLevel(rawValue: defaults.string(forKey: "contrast") ?? "") ?? .standard
        self.corners = corners
        motion = MotionStyle(rawValue: defaults.string(forKey: "motion") ?? "") ?? .expressive
        roundedText = RoundedText(rawValue: defaults.string(forKey: "roundedText") ?? "") ?? .titles
        liquidGlass = defaults.object(forKey: "liquidGlass") as? Bool ?? false
        appIconShape = AppIconShape(rawValue: defaults.string(forKey: "appIconShape") ?? "") ?? .circle
        appIconColor = AppIconColor(rawValue: defaults.string(forKey: "appIconColor") ?? "") ?? .theme
        appIconAppearance = AppIconAppearance(rawValue: defaults.string(forKey: "appIconAppearance") ?? "") ?? .automatic
        appIconDarkBackground = AppIconDarkBackground(rawValue: defaults.string(forKey: "appIconDarkBackground") ?? "") ?? .material
        #if DEBUG
        // Per le prove: `-BCWLiquidGlass YES` attiva Liquid Glass.
        if defaults.object(forKey: "BCWLiquidGlass") != nil { liquidGlass = defaults.bool(forKey: "BCWLiquidGlass") }
        #endif
        // Le barre di sistema si configurano dopo (`BCWApp.init`): qui leggerebbero `shared`,
        // che non esiste ancora.
        regenerate(configuringBars: false)
    }

    private func syncedChanged() {
        if !applyingRemote { onSyncedChange?() }
    }

    /// Aspetto sincronizzato con l'account BCW (Liquid Glass resta del dispositivo).
    var syncedValues: [String: JSONValue] {
        [
            "accentColor": .string(Self.normalize(accentColor) ?? defaultAccent),
            "colorStyle": .string(colorStyle.rawValue),
            "contrast": .string(contrast.rawValue),
            "corners": .string(corners.rawValue),
            "motion": .string(motion.rawValue),
            "roundedText": .string(roundedText.rawValue),
            "appIconShape": .string(appIconShape.rawValue),
            "appIconColor": .string(appIconColor.rawValue),
            "appIconAppearance": .string(appIconAppearance.rawValue),
            "appIconDarkBackground": .string(appIconDarkBackground.rawValue),
        ]
    }

    /// Applica l'aspetto arrivato dall'account BCW (i valori non validi si saltano).
    func applySynced(_ values: [String: JSONValue]) {
        applyingRemote = true
        defer { applyingRemote = false }
        if let value = values["accentColor"]?.string.flatMap(Self.normalize), value != Self.normalize(accentColor) {
            accentColor = value
        }
        if let value = values["colorStyle"]?.string.flatMap(ColorStyle.init(rawValue:)), value != colorStyle { colorStyle = value }
        if let value = values["contrast"]?.string.flatMap(ContrastLevel.init(rawValue:)), value != contrast { contrast = value }
        if let value = values["corners"]?.string.flatMap(CornerStyle.init(rawValue:)), value != corners { corners = value }
        if let value = values["motion"]?.string.flatMap(MotionStyle.init(rawValue:)), value != motion { motion = value }
        if let value = values["roundedText"]?.string.flatMap(RoundedText.init(rawValue:)), value != roundedText {
            roundedText = value
        }
        // Icona dell'app: i valori sconosciuti (es. una forma di una versione più recente) si saltano.
        if let value = values["appIconShape"]?.string.flatMap(AppIconShape.init(rawValue:)), value != appIconShape {
            appIconShape = value
        }
        if let value = values["appIconColor"]?.string.flatMap(AppIconColor.init(rawValue:)), value != appIconColor {
            appIconColor = value
        }
        if let value = values["appIconAppearance"]?.string.flatMap(AppIconAppearance.init(rawValue:)),
           value != appIconAppearance {
            appIconAppearance = value
        }
        if let value = values["appIconDarkBackground"]?.string.flatMap(AppIconDarkBackground.init(rawValue:)),
           value != appIconDarkBackground {
            appIconDarkBackground = value
        }
    }

    static func normalize(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count == 6 { return "#" + hex }
        if hex.count == 3 { return "#" + hex.map { "\($0)\($0)" }.joined() }
        return nil
    }

    /// Ripristina l'aspetto predefinito (colori, angoli, animazioni, caratteri).
    func reset() {
        accentColor = defaultAccent
        colorStyle = .tonalSpot
        contrast = .standard
        corners = .standard
        motion = .expressive
        roundedText = .titles
    }

    var isDefault: Bool {
        signature == Self.defaultSignature && corners == .standard && motion == .expressive && roundedText == .titles
    }

    private func regenerate(configuringBars: Bool = true) {
        let signature = signature
        if signature == Self.defaultSignature {
            colors = SchemeColors(light: DefaultScheme.light, dark: DefaultScheme.dark)
            defaults.removeObject(forKey: "themeCache")
        } else if let cached = cachedScheme(signature) {
            colors = SchemeColors(light: cached.light, dark: cached.dark)
        } else if let built = ColorEngine.shared.build(signature: signature) {
            colors = SchemeColors(light: built.light, dark: built.dark)
            if let data = try? JSONEncoder().encode(CachedScheme(signature: signature, light: built.light, dark: built.dark)) {
                defaults.set(data, forKey: "themeCache")
            }
        }
        if configuringBars { configureSystemBars() }
    }

    private struct CachedScheme: Codable {
        let signature: String
        let light: SchemeValues
        let dark: SchemeValues
    }

    private func cachedScheme(_ signature: String) -> CachedScheme? {
        guard let data = defaults.data(forKey: "themeCache"),
              let cached = try? JSONDecoder().decode(CachedScheme.self, from: data),
              cached.signature == signature else { return nil }
        return cached
    }

    /// Colori dei campioni del colore d'accento (primario, secondario, terziario).
    func swatch(_ accent: String, dark: Bool) -> [Color] {
        ColorEngine.shared.swatch(accent: accent, style: colorStyle.rawValue, dark: dark)
            .map { Color(platformColor: PlatformColor(hex: Int($0.dropFirst(), radix: 16) ?? 0)) }
    }

    /// Font e colori delle barre di sistema (Liquid Glass).
    func configureSystemBars() {
        Theme.configureAppearance()
    }
}

// MARK: - Generazione dei colori (JavaScriptCore)

/// Esegue `material-color-utilities` (la stessa libreria della versione web) con JavaScriptCore,
/// così i colori sono identici a quelli del sito per lo stesso colore d'accento.
final class ColorEngine {
    static let shared = ColorEngine()

    private lazy var context: JSContext? = {
        guard let context = JSContext(),
              let libraryURL = Bundle.main.url(forResource: "material-color-utilities", withExtension: "js"),
              let themeURL = Bundle.main.url(forResource: "bcw-theme", withExtension: "js"),
              var library = try? String(contentsOf: libraryURL, encoding: .utf8),
              let theme = try? String(contentsOf: themeURL, encoding: .utf8) else { return nil }
        // Il file è un modulo ES: l'esportazione finale diventa un oggetto globale `MCU`.
        if let range = library.range(of: "export{", options: .backwards),
           let end = library[range.upperBound...].firstIndex(of: "}") {
            let names = library[range.upperBound..<end].split(separator: ",").map { pair -> String in
                let parts = pair.split(separator: " ")
                return parts.count == 3 ? "\(parts[2]):\(parts[0])" : "\(pair):\(pair)"
            }
            library.replaceSubrange(range.lowerBound...end, with: "var MCU={\(names.joined(separator: ","))};")
        }
        context.exceptionHandler = { _, exception in
            print("BCW-THEME JS:", exception?.toString() ?? "?")
        }
        context.evaluateScript(library)
        context.evaluateScript(theme)
        return context
    }()

    private var swatches: [String: [String]] = [:]

    func build(signature: String) -> (light: SchemeValues, dark: SchemeValues)? {
        let parts = signature.split(separator: "|").map(String.init)
        guard parts.count == 3,
              let result = context?.evaluateScript("BCWTheme.build('\(parts[0])','\(parts[1])','\(parts[2])')")?.toString(),
              let data = result.data(using: .utf8),
              let json = try? JSONDecoder().decode([String: [String: String]].self, from: data),
              let light = json["light"], let dark = json["dark"] else { return nil }
        return (SchemeValues(roles: light), SchemeValues(roles: dark))
    }

    private var hueChromas: [String: (hue: Double, chroma: Double)] = [:]

    /// Tonalità e croma (HCT di Material) di un colore `#rrggbb`.
    func hueChroma(_ hex: String) -> (hue: Double, chroma: Double)? {
        if let cached = hueChromas[hex] { return cached }
        guard hex.count == 7, hex.dropFirst().allSatisfy(\.isHexDigit),
              let result = context?.evaluateScript(
                "(function(){var h=MCU.Hct.fromInt(MCU.argbFromHex('\(hex)'));return h.hue+','+h.chroma})()")?.toString()
        else { return nil }
        let parts = result.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        hueChromas[hex] = (parts[0], parts[1])
        return (parts[0], parts[1])
    }

    func swatch(accent: String, style: String, dark: Bool) -> [String] {
        let key = "\(accent)|\(style)|\(dark)"
        if let cached = swatches[key] { return cached }
        guard let result = context?.evaluateScript("BCWTheme.swatch('\(accent)','\(style)',\(dark))")?.toString(),
              let data = result.data(using: .utf8),
              let colors = try? JSONDecoder().decode([String].self, from: data) else { return [accent, accent, accent] }
        swatches[key] = colors
        return colors
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        self.init(uiColor: platformColor)
    }
}
