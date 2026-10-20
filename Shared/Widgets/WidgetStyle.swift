import CoreText
import SwiftUI
import WidgetKit

// MARK: - Modalità di resa

/// Come iOS disegna il widget: a colori, con le icone colorate o trasparenti della schermata Home
/// (accented: il sistema toglie lo sfondo e ricolora i contenuti, tenendo solo l'opacità) o nella
/// schermata di blocco (vibrant: monocromatico). Fuori da WidgetKit (galleria di prova nell'app)
/// si sceglie a mano.
enum WidgetLook: String, CaseIterable, Identifiable {
    case fullColor, accented, vibrant
    var id: String { rawValue }

    init(_ mode: WidgetRenderingMode) {
        switch mode {
        case .accented: self = .accented
        case .vibrant: self = .vibrant
        default: self = .fullColor
        }
    }
}

// MARK: - Colori

/// Colori dei widget: i ruoli di Material 3 del tema dell'istantanea, risolti per il tema chiaro o
/// scuro. Nelle modalità accented e vibrant tutto diventa bianco con opacità diverse (gerarchia
/// senza grandi riempimenti, che il sistema trasformerebbe in macchie).
struct WidgetPalette {
    let look: WidgetLook
    let isDark: Bool
    /// Nella galleria di prova le parti `widgetAccentable` prendono un colore simile a quello del
    /// sistema (nei widget veri lo sceglie iOS).
    let simulated: Bool
    private let roles: [String: String]
    let rond: CGFloat
    let rondBody: CGFloat
    let radii: Radii

    /// Angoli (come `CornerRadii` dell'app, Impostazioni › Aspetto › Angoli).
    struct Radii {
        let xs, s, m, l, li, xl: CGFloat

        init(_ style: String) {
            switch style {
            case "square": (xs, s, m, l, li, xl) = (2, 4, 8, 10, 12, 16)
            case "round": (xs, s, m, l, li, xl) = (6, 12, 16, 22, 26, 34)
            default: (xs, s, m, l, li, xl) = (4, 8, 12, 16, 20, 28)
            }
        }
    }

    init(theme: WidgetSnapshot.ThemeSnapshot, colorScheme: ColorScheme, look: WidgetLook, simulated: Bool = false) {
        self.look = look
        isDark = colorScheme == .dark
        self.simulated = simulated
        roles = isDark ? theme.dark : theme.light
        rond = theme.rond
        rondBody = theme.rondBody
        radii = Radii(theme.corners)
    }

    var isFullColor: Bool { look == .fullColor }

    /// Colore di un ruolo (sempre a colori, es. per i riempimenti a colori).
    func role(_ name: String) -> Color {
        Color(rgb: ThemeDefaults.hexValue(roles[name]) ?? fallback(name))
    }

    private func fallback(_ name: String) -> Int {
        let defaults = isDark ? ThemeDefaults.dark : ThemeDefaults.light
        return ThemeDefaults.hexValue(defaults[name]) ?? (isDark ? 0xF0F0F0 : 0x202020)
    }

    private func hex(_ name: String) -> Int { ThemeDefaults.hexValue(roles[name]) ?? fallback(name) }

    // Testo e icone.
    var ink: Color { isFullColor ? role("on-surface") : .white }
    var secondaryInk: Color { isFullColor ? role("on-surface-variant") : .white.opacity(0.72) }
    var tertiaryInk: Color { isFullColor ? role("outline") : .white.opacity(0.5) }
    var primary: Color { isFullColor ? role("primary") : accent }

    /// Parti in evidenza (`widgetAccentable`): il primario a colori, il colore del sistema altrimenti.
    var accent: Color {
        switch look {
        case .fullColor: role("primary")
        case .accented: simulated ? Color(red: 0.62, green: 0.80, blue: 1.0) : .white
        case .vibrant: .white
        }
    }

    // Superfici.
    var background: Color { role("surface") }
    var card: Color { isFullColor ? role("surface-container") : .white.opacity(0.12) }
    var cardHigh: Color { isFullColor ? role("surface-container-high") : .white.opacity(0.16) }
    var separator: Color { isFullColor ? role("outline-variant") : .white.opacity(0.25) }

    /// Contenitore e testo sul contenitore di un ruolo (`primary`, `secondary`, `tertiary`…).
    func container(_ name: String) -> Color { isFullColor ? role("\(name)-container") : .white.opacity(0.14) }
    func onContainer(_ name: String) -> Color { isFullColor ? role("on-\(name)-container") : .white }

    // Eventi dell'orario.
    func tint(_ tint: WidgetSnapshot.Tint) -> Color {
        isFullColor ? Color(rgb: isDark ? tint.dark : tint.light) : accent
    }

    /// Sfondo pastello di un evento, come `EntryFill` nell'app: la tinta al 18% sul contenitore basso.
    func eventFill(_ tint: WidgetSnapshot.Tint, amount: Double = 0.18) -> Color {
        guard isFullColor else { return .white.opacity(amount > 0.2 ? 0.2 : 0.1) }
        return Color(rgb: Self.mix(isDark ? tint.dark : tint.light, hex("surface-container-low"), amount))
    }

    func mixed(_ a: String, _ b: String, _ amount: Double) -> Color {
        Color(rgb: Self.mix(hex(a), hex(b), amount))
    }

    // Toni delle medie (bene, sufficiente, insufficiente, neutro), come `Theme.tone`.
    static func toneName(_ value: Double?) -> String {
        guard let value else { return "neutral" }
        if value >= 6 { return "good" }
        if value >= 5.5 { return "fair" }
        return "poor"
    }

    func tone(_ value: Double?) -> Color { isFullColor ? role(Self.toneName(value)) : accent }
    func toneContainer(_ value: Double?) -> Color {
        isFullColor ? role("\(Self.toneName(value))-container") : .white.opacity(0.22)
    }

    /// Mescola due colori RGB come `color-mix(in srgb, a p%, b)`.
    static func mix(_ a: Int, _ b: Int, _ amount: Double) -> Int {
        var result = 0
        for shift in [16, 8, 0] {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            result |= Int((x * amount + y * (1 - amount)).rounded()) << shift
        }
        return result
    }

    // MARK: Caratteri

    /// Google Sans Flex, con l'arrotondamento dei titoli (`rounded`) o del testo.
    func font(_ size: CGFloat, weight: CGFloat = 400, rounded: Bool = false) -> Font {
        WidgetFonts.font(size: size, weight: weight, rond: rounded ? rond : rondBody)
    }

    /// Cifre allineate per orari e conti alla rovescia.
    func numeral(_ size: CGFloat, weight: CGFloat = 600, rounded: Bool = false) -> Font {
        font(size, weight: weight, rounded: rounded).monospacedDigit()
    }
}

extension Color {
    /// Colore da un valore RGB esadecimale.
    init(rgb: Int) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

// MARK: - Caratteri

/// Google Sans Flex per i widget. Nell'estensione il file sta nel bundle dell'app che la contiene
/// (`BCW.app/PlugIns/BCWWidgets.appex`), così non va copiato; nell'app (galleria) nel suo bundle.
enum WidgetFonts {
    private static let wghtAxis = 0x7767_6874 // 'wght'
    private static let opszAxis = 0x6F70_737A // 'opsz'
    private static let rondAxis = 0x524F_4E44 // 'ROND'

    /// Dove si trova il file del carattere (`nil` se non si trova: si usa quello di sistema).
    static let fontURL: URL? = {
        if let url = Bundle.main.url(forResource: "GoogleSansFlex", withExtension: "ttf") { return url }
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app", let app = Bundle(url: appURL) else { return nil }
        return app.url(forResource: "GoogleSansFlex", withExtension: "ttf")
    }()

    private static let base: CTFontDescriptor? = {
        guard let url = fontURL else { return nil }
        // Nell'app è già registrato da `Typography`: il secondo tentativo fallisce senza danni.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
    }()

    private struct Key: Hashable {
        let size: CGFloat
        let weight: CGFloat
        let rond: CGFloat
    }

    private static var cache: [Key: Font] = [:]

    static var isAvailable: Bool { base != nil }

    static func font(size: CGFloat, weight: CGFloat, rond: CGFloat) -> Font {
        let key = Key(size: size, weight: weight, rond: rond)
        if let font = cache[key] { return font }
        let font: Font
        if let base {
            let variation: [Int: CGFloat] = [wghtAxis: weight, opszAxis: min(max(size, 6), 144), rondAxis: rond]
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: variation] as CFDictionary)
            font = Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        } else {
            font = .system(size: size, weight: weight >= 650 ? .bold : (weight >= 550 ? .semibold : .regular),
                           design: rond > 50 ? .rounded : .default)
        }
        cache[key] = font
        return font
    }
}

// MARK: - Elementi comuni

/// Icona di Material Symbols (stessi nomi `m.<nome>` del catalogo dell'app; l'estensione ha una
/// copia di quelle che usa).
struct WidgetIcon: View {
    let name: String
    var size: CGFloat = 16

    init(_ name: String, size: CGFloat = 16) {
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

/// Etichetta in maiuscoletto sopra a un contenuto (es. "ADESSO", "DOMANI").
struct WidgetEyebrow: View {
    let text: String
    let color: Color
    let palette: WidgetPalette
    var size: CGFloat = 11

    var body: some View {
        Text(text.uppercased())
            .font(palette.font(size, weight: 750))
            .tracking(0.8)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Chip di stato (come `StatusChip` nell'app), piccola pillola con icona.
struct WidgetChip: View {
    let text: String
    var icon: String?
    let container: Color
    let foreground: Color
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            if let icon { WidgetIcon(icon, size: 12) }
            Text(text)
                .font(palette.font(11, weight: 650))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(foreground)
        .padding(.leading, icon == nil ? 8 : 6)
        .padding(.trailing, 8)
        .frame(height: 20)
        .background(container, in: .capsule)
    }
}

/// Stato vuoto di un widget: icona in una forma di M3 Expressive, titolo e invito.
struct WidgetEmptyState: View {
    let icon: String
    let title: String
    var message: String?
    let palette: WidgetPalette
    var compact = false
    /// Ruolo del contenitore che fa da sfondo al widget (es. `primary` per "Lezione in corso"):
    /// la forma prende il colore pieno del ruolo e il testo quello sul contenitore.
    var onContainer: String?

    var body: some View {
        let shapeFill: Color = if let onContainer, palette.isFullColor { palette.role(onContainer) } else { palette.container("primary") }
        let iconColor: Color = if !palette.isFullColor { palette.accent } else if let onContainer { palette.role("on-\(onContainer)") } else { palette.onContainer("primary") }
        let titleColor = onContainer.map(palette.onContainer) ?? palette.ink
        let messageColor = onContainer.map { palette.onContainer($0).opacity(0.85) } ?? palette.secondaryInk
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            ZStack {
                MaterialShape(.cookie9Sided)
                    .fill(shapeFill)
                WidgetIcon(icon, size: compact ? 18 : 22)
                    .foregroundStyle(iconColor)
            }
            .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
            .widgetAccentable()
            Spacer(minLength: 0)
            Text(title)
                .font(palette.font(compact ? 15 : 17, weight: 600, rounded: true))
                .foregroundStyle(titleColor)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let message {
                Text(message)
                    .font(palette.font(12))
                    .foregroundStyle(messageColor)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Date

/// Nomi dei giorni in italiano, come nell'app ("Oggi", "Domani", "Lunedì 26 ottobre").
enum WidgetDates {
    private static func style() -> Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "it_IT"), calendar: BCWShared.calendar,
                         timeZone: BCWShared.calendar.timeZone)
    }

    static func offset(of day: Date, from now: Date) -> Int {
        let calendar = BCWShared.calendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
    }

    /// "Oggi", "Domani", "Ieri" o il nome del giorno ("Lunedì").
    static func relativeName(_ day: Date, now: Date) -> String {
        switch offset(of: day, from: now) {
        case 0: return "Oggi"
        case 1: return "Domani"
        case -1: return "Ieri"
        default: return weekday(day)
        }
    }

    /// "Oggi", "Domani" o "Lun 26".
    static func relativeShort(_ day: Date, now: Date) -> String {
        switch offset(of: day, from: now) {
        case 0: return "Oggi"
        case 1: return "Domani"
        default: return "\(weekdayShort(day)) \(BCWShared.calendar.component(.day, from: day))"
        }
    }

    static func weekday(_ day: Date) -> String {
        day.formatted(style().weekday(.wide)).capitalizedFirstLetter
    }

    static func weekdayShort(_ day: Date) -> String {
        day.formatted(style().weekday(.abbreviated)).replacingOccurrences(of: ".", with: "").capitalizedFirstLetter
    }

    /// "26 ottobre".
    static func dayMonth(_ day: Date) -> String {
        day.formatted(style().day().month(.wide))
    }

    /// "26 ott".
    static func dayMonthShort(_ day: Date) -> String {
        day.formatted(style().day().month(.abbreviated)).replacingOccurrences(of: ".", with: "")
    }

    /// "Lunedì 26 ottobre".
    static func long(_ day: Date) -> String {
        "\(weekday(day)) \(dayMonth(day))"
    }

    static func time(_ date: Date) -> String {
        TimeOfDay.string(BCWShared.minutes(of: date))
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// Formato delle medie, come `GradeFormat` nell'app ("7,42", "–").
enum WidgetGradeFormat {
    static func average(_ value: Double?, digits: Int = 2) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "it_IT")))
    }
}
