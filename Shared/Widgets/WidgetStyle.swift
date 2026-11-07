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

// MARK: - Sfondo

/// Sfondo del widget, scelto per ogni widget (tieni premuto il widget › Modifica widget).
nonisolated enum WidgetBackgroundStyle: String, CaseIterable, Sendable {
    /// Quello di sempre: la superficie del tema, chiara o scura come iOS.
    case system
    /// Il colore del tema (il tono di "Tonale" in Aspetto), con il resto del widget in tinta.
    case theme
}

// MARK: - Colori

/// Colori dei widget: i ruoli di Material 3 del tema dell'istantanea, risolti per il tema chiaro o
/// scuro. Nelle modalità accented e vibrant tutto diventa bianco con opacità diverse (gerarchia
/// senza grandi riempimenti, che il sistema trasformerebbe in macchie).
struct WidgetPalette {
    let look: WidgetLook
    let isDark: Bool
    /// Sfondo nel colore del tema (Modifica widget).
    let hasThemeBackground: Bool
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

    init(theme: WidgetSnapshot.ThemeSnapshot, colorScheme: ColorScheme, look: WidgetLook, simulated: Bool = false,
         background: WidgetBackgroundStyle = .system) {
        self.look = look
        isDark = colorScheme == .dark
        hasThemeBackground = background == .theme
        self.simulated = simulated
        let roles = isDark ? theme.dark : theme.light
        self.roles = background == .theme ? Self.themed(roles, isDark: isDark) : roles
        rond = theme.rond
        rondBody = theme.rondBody
        radii = Radii(theme.corners)
    }

    var isFullColor: Bool { look == .fullColor }

    /// I ruoli con lo sfondo nel colore del tema. In chiaro la superficie diventa il contenitore
    /// secondario, il tono del pulsante "Tonale" in Impostazioni › Aspetto (scelta dell'utente: il
    /// primario era troppo acceso). Le card sono veli del colore del testo. Primario e contenitore primario
    /// restano, per la lezione in corso che deve staccarsi dallo sfondo; anche "Prossima verifica", nel
    /// contenitore terziario, prende questo sfondo. In scuro lo sfondo deve sembrare quello dell'app
    /// (scelta dell'utente: i contenitori e anche un loro tono mescolato con la superficie erano troppo
    /// chiari), ma sulla Home iOS schiarisce lo sfondo dei widget scuri: si scuriscono le superfici di
    /// quanto le schiarisce (`homeScreenLift`).
    private static func themed(_ roles: [String: String], isDark: Bool) -> [String: String] {
        if isDark { return compensatingHomeScreenLift(roles) }
        let defaults = ThemeDefaults.light
        func value(_ name: String) -> Int {
            ThemeDefaults.hexValue(roles[name]) ?? ThemeDefaults.hexValue(defaults[name]) ?? 0x808080
        }
        let tonal = value("secondary-container")
        let onTonal = value("on-secondary-container")
        func veil(_ amount: Double) -> Int { mix(onTonal, tonal, amount) }
        var result = roles
        let changes: [String: Int] = [
            "surface": tonal,
            "on-surface": onTonal,
            "on-surface-variant": veil(0.8),
            "outline": veil(0.6),
            "outline-variant": veil(0.25),
            "surface-container-low": veil(0.06),
            "surface-container": veil(0.1),
            "surface-container-high": veil(0.16),
            "surface-container-highest": veil(0.22),
            "secondary-container": veil(0.14),
            "tertiary-container": tonal,
            "on-tertiary-container": onTonal,
        ]
        for (name, color) in changes { result[name] = String(format: "#%06X", color) }
        return result
    }

    /// Quanto iOS schiarisce lo sfondo dei widget scuri sulla Home (iOS 26 e 27): circa 13 livelli per
    /// canale in basso e 30 in alto, come una luce dall'alto, misurati sul simulatore (lo sfondo nero
    /// diventa #0D0D0D in basso e #1F1E1F in alto) e visti anche sull'iPhone. Non si può spegnere:
    /// si toglie la parte in basso, così il widget ha il colore dell'app (in alto resta la luce di iOS).
    private static let homeScreenLift = 13

    /// Le superfici scure scurite di `homeScreenLift` (fino al nero).
    private static func compensatingHomeScreenLift(_ roles: [String: String]) -> [String: String] {
        var result = roles
        let names = ["surface", "surface-dim", "surface-container-lowest", "surface-container-low", "surface-container",
                     "surface-container-high", "surface-container-highest"]
        for name in names {
            guard let value = ThemeDefaults.hexValue(roles[name] ?? ThemeDefaults.dark[name]) else { continue }
            var darker = 0
            for shift in [16, 8, 0] {
                darker |= max(((value >> shift) & 0xFF) - homeScreenLift, 0) << shift
            }
            result[name] = String(format: "#%06X", darker)
        }
        return result
    }

    /// Sfondo dei widget che stanno in un contenitore ("Lezione in corso", "Prossima verifica"). Con il
    /// colore del tema è quello di tutti; in scuro il contenitore (tono 30) è troppo chiaro per uno sfondo,
    /// quindi è la superficie (con il colore del tema, scurita come per gli altri widget).
    func containerBackground(_ name: String) -> Color {
        if hasThemeBackground || isDark { return background }
        return role("\(name)-container")
    }

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

    /// Per `Text(timerInterval:)`: il carattere di sistema arrotondato (`WidgetFonts.timer`).
    func timer(_ size: CGFloat, weight: CGFloat = 650) -> Font {
        WidgetFonts.timer(size: size, weight: weight)
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
            font = .system(size: size, weight: systemWeight(weight), design: rond > 50 ? .rounded : .default)
        }
        cache[key] = font
        return font
    }

    /// Carattere dell'attività in diretta: le istanze con nome di Google Sans Flex, non il carattere
    /// variabile di `font(size:weight:rond:)`. Con quello l'estensione va in crash circa una volta su
    /// 10 mentre archivia l'attività (`KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS` in
    /// `CodableAttributedString`, iPhone 15 con iOS 27.0.1: 4 prove su 40; con le istanze con nome 0 su
    /// 40, con il carattere di sistema 0 su 24; sul simulatore non succede). Il file non ha istanze
    /// arrotondate: l'asse ROND qui non c'è.
    static func activity(size: CGFloat, weight: CGFloat) -> Font {
        guard isAvailable else {
            return .system(size: size, weight: systemWeight(weight), design: .rounded)
        }
        let name = switch weight {
        case 675...: "GoogleSansFlex-Bold"
        case 575...: "GoogleSansFlex-SemiBold"
        case 475...: "GoogleSansFlex-Medium"
        default: "GoogleSansFlex-Regular"
        }
        return .custom(name, fixedSize: size)
    }

    /// Carattere dei testi del tempo che iOS aggiorna da solo (`Text(timerInterval:)`): quello di
    /// sistema arrotondato con le cifre allineate, mai Google Sans Flex. Su iOS 27.0.1 (iPhone 15,
    /// verificato) un testo del tempo con un carattere personalizzato manda in crash l'estensione
    /// mentre archivia la vista (`KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS` in
    /// `CodableAttributedString`): l'attività in diretta veniva chiusa appena avviata, prima ancora
    /// mostrava la rotella. Succede con `Font(CTFont)`, con `Font.custom` e con il formato
    /// `.timer` di iOS 18; con il carattere di sistema no. Sul simulatore non succede.
    static func timer(size: CGFloat, weight: CGFloat) -> Font {
        .system(size: size, weight: systemWeight(weight), design: .rounded).monospacedDigit()
    }

    private static func systemWeight(_ weight: CGFloat) -> Font.Weight {
        switch weight {
        case 700...: .bold
        case 600...: .semibold
        case 500...: .medium
        default: .regular
        }
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

#if DEBUG
/// Contatori per provare i widget sul telefono (`-BCWWidgetProbe N`, `WidgetSelfTest`): dicono se
/// iOS ha davvero ridisegnato i widget, altrimenti "nessun crash" non vorrebbe dire nulla.
nonisolated enum WidgetProbe {
    static func bump(_ key: String) {
        let defaults = UserDefaults(suiteName: BCWShared.appGroup)
        defaults?.set((defaults?.integer(forKey: key) ?? 0) + 1, forKey: key)
    }

    static func count(_ key: String) -> Int {
        let defaults = UserDefaults(suiteName: BCWShared.appGroup)
        defaults?.synchronize()
        return defaults?.integer(forKey: key) ?? 0
    }
}
#endif
