#if DEBUG
import SwiftUI
import WidgetKit

/// Galleria di prova dei widget (solo DEBUG, `-BCWWidgetGallery YES`): gli stessi widget
/// dell'estensione (viste di `Shared/Widgets`) alle loro dimensioni sull'iPhone, con i dati
/// dell'istantanea che l'app scrive per i widget (o con quelli di esempio), in chiaro o scuro e
/// nelle modalità di resa. Argomenti: `-BCWWidgetGalleryScheme light|dark`,
/// `-BCWWidgetGalleryLook fullColor|accented|vibrant`, `-BCWWidgetGalleryKind timetable|now|…`,
/// `-BCWWidgetGallerySource app|sample|signedOut|empty` (dati, esempio o stati vuoti);
/// `-BCWNowMinute N` sposta l'ora.
struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme

    @State private var scheme: ColorScheme? = WidgetGalleryView.argument("BCWWidgetGalleryScheme")
        .flatMap { $0 == "dark" ? .dark : ($0 == "light" ? .light : nil) }
    @State private var look = WidgetGalleryView.argument("BCWWidgetGalleryLook").flatMap(WidgetLook.init(rawValue:)) ?? .fullColor
    @State private var source = WidgetGalleryView.argument("BCWWidgetGallerySource").flatMap(Source.init(rawValue:))
        ?? (UserDefaults.standard.bool(forKey: "BCWWidgetGallerySample") ? .sample : .app)
    private let only = WidgetGalleryView.argument("BCWWidgetGalleryKind").flatMap(BCWWidgetKind.init(rawValue:))

    static func argument(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }

    /// Dati mostrati: quelli dell'app, l'esempio della galleria di iOS o gli stati vuoti.
    enum Source: String, CaseIterable {
        case app, sample, signedOut, empty

        var title: String {
            switch self {
            case .app: "App"
            case .sample: "Esempio"
            case .signedOut: "Senza account"
            case .empty: "Vuoto"
            }
        }

        func snapshot(model: AppModel, now: Date) -> WidgetSnapshot {
            switch self {
            case .app: model.widgets.current ?? .sample(now: now)
            case .sample: .sample(now: now)
            case .signedOut: WidgetSnapshot(generatedAt: now, signedIn: false, theme: model.widgets.current?.theme ?? .init())
            case .empty:
                // Con l'account ma senza orario, compiti, verifiche e voti.
                WidgetSnapshot(generatedAt: now, signedIn: true, accountName: "Prova",
                               theme: model.widgets.current?.theme ?? .init())
            }
        }
    }

    /// Adesso, o il minuto di `-BCWNowMinute` di oggi.
    private var now: Date {
        let date = Date()
        guard UserDefaults.standard.object(forKey: "BCWNowMinute") != nil else { return date }
        return BCWShared.date(date, minute: TimeOfDay.nowMinutes(of: date))
    }

    var body: some View {
        let now = now
        let snapshot = source.snapshot(model: model, now: now)
        let colorScheme = scheme ?? systemScheme
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls
                ForEach(BCWWidgetKind.allCases.filter { only == nil || $0 == only }) { kind in
                    section(kind, snapshot: snapshot, now: now, colorScheme: colorScheme)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(background(colorScheme).ignoresSafeArea())
        .environment(\.colorScheme, colorScheme)
        .overlay(alignment: .topTrailing) {
            IconButton("x", label: "Chiudi") { dismiss() }
                .padding(.trailing, 12)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Widget")
                .font(.m3(34, weight: 500, rounded: true))
                .padding(.top, 8)
            SegmentedButtons(selection: Binding(get: { scheme ?? systemScheme }, set: { scheme = $0 }),
                             options: [(ColorScheme.light, "Chiaro", "sun"), (ColorScheme.dark, "Scuro", "contrast")])
            SegmentedButtons(selection: $look, options: [(WidgetLook.fullColor, "Colori", nil),
                                                          (WidgetLook.accented, "Colorate", nil),
                                                          (WidgetLook.vibrant, "Blocco", nil)])
            SegmentedButtons(selection: $source, options: Source.allCases.map { ($0, $0.title, nil) })
        }
    }

    /// Sfondo della pagina come lo schermo dietro i widget: Home chiara o scura, icone colorate
    /// (scure con la tinta del sistema) o schermata di blocco.
    private func background(_ colorScheme: ColorScheme) -> Color {
        switch look {
        case .fullColor: colorScheme == .dark ? Color(rgb: 0x1C2430) : Color(rgb: 0xC9D6E6)
        case .accented: Color(rgb: 0x101A2A)
        case .vibrant: Color(rgb: 0x23304A)
        }
    }

    @ViewBuilder
    private func section(_ kind: BCWWidgetKind, snapshot: WidgetSnapshot, now: Date, colorScheme: ColorScheme) -> some View {
        // Nella schermata di blocco ci sono solo gli accessori, nella Home gli altri.
        let families = kind.families.filter { look == .vibrant ? $0.isAccessory : !$0.isAccessory }
        if !families.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(kind.displayName)
                    .font(.m3(16, weight: 650))
                    .foregroundStyle(look == .fullColor && colorScheme == .light ? Color(rgb: 0x1C2430) : Color(rgb: 0xE8EEF6))
                FlowLayout(spacing: 12) {
                    ForEach(families, id: \.self) { family in
                        WidgetFrame(kind: kind, family: family, snapshot: snapshot, now: now,
                                    palette: WidgetPalette(theme: snapshot.theme, colorScheme: colorScheme,
                                                           look: family.isAccessory ? .vibrant : look, simulated: true))
                    }
                }
            }
        }
    }
}

/// Un widget alle dimensioni dell'iPhone 17 (402 × 874 punti, misurate sulla Home del simulatore),
/// con i margini del contenuto e gli angoli della schermata Home.
private struct WidgetFrame: View {
    let kind: BCWWidgetKind
    let family: WidgetFamily
    let snapshot: WidgetSnapshot
    let now: Date
    let palette: WidgetPalette

    static func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 164, height: 164)
        case .systemMedium: CGSize(width: 350, height: 164)
        case .systemLarge: CGSize(width: 350, height: 365)
        case .accessoryCircular: CGSize(width: 76, height: 76)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        case .accessoryInline: CGSize(width: 257, height: 26)
        default: CGSize(width: 164, height: 164)
        }
    }

    var body: some View {
        let size = Self.size(family)
        let content = kind.content(snapshot: snapshot, now: now, family: family, palette: palette)
        if family.isAccessory {
            content
                .foregroundStyle(.white)
                .frame(width: size.width, height: size.height, alignment: family == .accessoryInline ? .leading : .center)
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1) }
        } else {
            content
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background {
                    if palette.look == .fullColor {
                        kind.background(palette)
                    } else {
                        // Icone colorate o trasparenti: al posto dello sfondo il vetro del sistema.
                        Color.white.opacity(0.08)
                    }
                }
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
        }
    }
}
#endif
