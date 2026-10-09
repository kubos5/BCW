import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Piccoli adattatori tra iOS e macOS: il resto dell'app usa questi invece delle API
/// specifiche di UIKit o AppKit, così le viste restano le stesse su entrambe le piattaforme.
enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Copia un testo negli appunti.
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// Apre le impostazioni di sistema delle notifiche per BCW.
    static func openNotificationSettings() {
        #if os(macOS)
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}

#if os(macOS)
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    nonisolated convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension PlatformFont {
    #if os(macOS)
    static func newYork(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
    #else
    static func newYork(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
    #endif
}

extension View {
    /// Su macOS: distanziatore e pulsante Aggiorna nella barra della finestra (vedi
    /// `macWindowActions` in `MacRootView`). Da applicare alle pagine aperte da un'altra.
    @ViewBuilder
    func pushedPageActions() -> some View {
        #if os(macOS)
        macWindowActions()
        #else
        self
        #endif
    }
}

/// Valore da conservare in `@State` senza che cambiarlo ridisegni la vista: per misure che
/// cambiano spesso (es. a ogni fotogramma di un'animazione) ma servono solo in certi momenti.
final class UnobservedValue<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

extension ToolbarItemPlacement {
    /// Lato destro della barra (su macOS `.primaryAction` starebbe invece a sinistra).
    static var trailingBar: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .topBarTrailing
        #endif
    }
}

extension View {
    /// Titolo della pagina. Su iOS è il titolo della barra di navigazione; su macOS la
    /// finestra mostrerebbe il titolo con il font di sistema, quindi lo si sostituisce
    /// con un'etichetta in New York all'inizio della barra degli strumenti.
    func screenTitle(_ title: String, subtitle: String? = nil) -> some View {
        #if os(macOS)
        navigationTitle(title)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    MacToolbarTitle(title: title, subtitle: subtitle)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .macToolbarBackground()
        #else
        navigationTitle(title)
        #endif
    }

    /// Titolo piccolo al centro della barra (solo iOS: su macOS non esiste la distinzione).
    func inlineTitleDisplay() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Margini laterali delle pagine: più ampi su macOS, dove c'è più spazio.
    func pagePadding() -> some View {
        #if os(macOS)
        padding(.horizontal, 28)
            .padding(.top, 8)
        #else
        padding(.horizontal)
        #endif
    }

    /// Su macOS un `Menu` con un'etichetta personalizzata verrebbe chiuso in un pulsante
    /// di sistema: così mostra l'etichetta così com'è, come su iOS.
    func plainMenuOnMac() -> some View {
        #if os(macOS)
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        #else
        self
        #endif
    }

    /// Barra della finestra sopra il contenuto con lo sfondo fisso della pagina. macOS 27, al
    /// passaggio del cursore sulla barra, schiarisce (e sottolinea) la parte sopra ogni area
    /// scorrevole che vi passa sotto: nelle pagine a due colonne solo sopra una delle due.
    /// Qui il contenuto comincia appena sotto la barra, così nessuna area scorrevole la tocca,
    /// e sotto la barra resta il colore della pagina. Vale solo per il contenuto, non per la
    /// barra laterale.
    func macToolbarBackground() -> some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Color.clear.frame(height: 1)
            self
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        self
        #endif
    }

    /// Su macOS i controlli segmentati restano della loro misura invece di allargarsi.
    func compactOnMac() -> some View {
        #if os(macOS)
        fixedSize()
        #else
        self
        #endif
    }

    /// Dimensioni di un foglio: su macOS i fogli non hanno una misura propria.
    func sheetFrame(width: CGFloat = 460, height: CGFloat = 520) -> some View {
        #if os(macOS)
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct MacToolbarTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .contentTransition(.numericText())
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 6)
        .fixedSize()
        .accessibilityAddTraits(.isHeader)
    }
}
#endif

/// Elenco di card: una colonna su iOS, griglia adattiva su macOS.
struct CardGrid<Content: View>: View {
    var minWidth: CGFloat = 340
    var spacing: CGFloat = 10
    /// Su macOS le card della stessa riga prendono l'altezza della più alta
    /// (vanno costruite con `.frame(maxHeight: .infinity)` prima di `.card()`).
    var equalRowHeights = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        if equalRowHeights {
            EqualRowGrid(minWidth: minWidth, spacing: 14) { content() }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 14, content: content)
        }
        #else
        LazyVStack(spacing: spacing, content: content)
        #endif
    }
}

#if os(macOS)
/// Griglia adattiva (come `GridItem.adaptive`) in cui ogni riga è alta quanto la sua card
/// più alta: le altre ricevono quell'altezza e, se flessibili, la riempiono.
struct EqualRowGrid: Layout {
    var minWidth: CGFloat
    var spacing: CGFloat

    private func columns(for width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (minWidth + spacing)))
    }

    private func rows(width: CGFloat, subviews: Subviews) -> (columnWidth: CGFloat, heights: [CGFloat]) {
        let count = columns(for: width)
        let columnWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let heights = stride(from: 0, to: subviews.count, by: count).map { start in
            subviews[start..<min(start + count, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
        return (columnWidth, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minWidth
        let layout = rows(width: width, subviews: subviews)
        let height = layout.heights.reduce(0, +) + spacing * CGFloat(max(0, layout.heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columns(for: bounds.width)
        let layout = rows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in layout.heights.enumerated() {
            for column in 0..<count {
                let index = row * count + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (layout.columnWidth + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y),
                                      proposal: ProposedViewSize(width: layout.columnWidth, height: height))
            }
            y += height + spacing
        }
    }
}
#endif

/// Indicatore di caricamento dentro righe e pulsanti: su macOS la misura normale è più
/// alta della riga, quindi si usa quella piccola.
struct InlineProgress: View {
    var tint: Color?

    var body: some View {
        ProgressView()
            .tint(tint)
            #if os(macOS)
            .controlSize(.small)
            #endif
    }
}

/// Cerchio centrato nel riquadro, di diametro fisso: area cliccabile dei giorni del calendario.
struct CenteredCircle: Shape {
    var diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2,
                               width: diameter, height: diameter))
    }
}

/// Ricerca dentro una singola pagina (bacheca, agenda, materiale). Su iOS è il campo nella
/// barra di navigazione; su macOS la barra della finestra ha già la ricerca generale, quindi
/// la pagina mostra il campo `LocalSearchField` nel proprio contenuto.
extension View {
    func localSearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(macOS)
        self
        #else
        searchable(text: text, prompt: prompt)
        #endif
    }
}

#if os(macOS)
struct LocalSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryInk)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryInk)
                }
                .buttonStyle(.plain)
                .help("Cancella")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 360)
        .background(Theme.surface, in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 0.5) }
    }
}
#endif

/// Riga di filtri: scorre in orizzontale su iOS, va a capo su macOS.
struct ChipRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        FlowLayout(spacing: 8) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
                .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        #endif
    }
}

/// Separatore verticale tra gruppi di filtri (funziona anche dentro `FlowLayout`).
struct ChipDivider: View {
    var body: some View {
        #if os(macOS)
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 22)
        #else
        Divider().frame(height: 22)
        #endif
    }
}

/// Pila di navigazione delle schede principali. Su macOS la pila è già fornita dalla
/// colonna di dettaglio della finestra, quindi qui non se ne crea un'altra.
struct PlatformNavigationStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        content()
        #else
        NavigationStack(root: content)
        #endif
    }
}

#if os(macOS)
extension EnvironmentValues {
    /// `true` quando `SplitColumns` ha impilato le colonne perché la finestra è stretta.
    @Entry var columnsStacked = false
}

/// Contenuto che cambia a seconda che le colonne di `SplitColumns` siano affiancate o impilate.
struct StackAware<Content: View>: View {
    @Environment(\.columnsStacked) private var stacked
    @ViewBuilder let content: (Bool) -> Content

    var body: some View { content(stacked) }
}

/// Pagina a due colonne per macOS: una colonna laterale stretta e una principale, ognuna
/// con il proprio scorrimento, così la colonna laterale resta visibile mentre si legge.
/// Se la finestra è troppo stretta le colonne si impilano come su iPhone.
struct SplitColumns<Side: View, Main: View>: View {
    var sideWidth: CGFloat = 340
    /// Larghezza minima della pagina per affiancare le colonne.
    var minWidth: CGFloat = 780
    var spacing: CGFloat = 20
    @ViewBuilder let side: () -> Side
    @ViewBuilder let main: () -> Main
    @State private var width: CGFloat = 1000

    var body: some View {
        Group {
            if width >= minWidth {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: spacing) { side() }
                            .environment(\.columnsStacked, false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 28)
                            .padding(.trailing, 10)
                            .padding(.top, 8)
                            .padding(.bottom, Theme.bottomInset)
                    }
                    .frame(width: sideWidth + 38)
                    ScrollView {
                        VStack(alignment: .leading, spacing: spacing) { main() }
                            .environment(\.columnsStacked, false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 10)
                            .padding(.trailing, 28)
                            .padding(.top, 8)
                            .padding(.bottom, Theme.bottomInset)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing) {
                        side()
                        main()
                    }
                    .environment(\.columnsStacked, true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pagePadding()
                    .padding(.bottom, Theme.bottomInset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedBackground()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
#endif

extension View {
    /// Pulsante di vetro neutro con il testo nel colore d'accento. Su macOS `.glass` riempie
    /// il pulsante con la tinta dell'app: qui si ricrea l'aspetto di iOS.
    func glassButton() -> some View {
        #if os(macOS)
        buttonStyle(MacGlassButtonStyle())
        #else
        buttonStyle(.glass)
        #endif
    }
}

#if os(macOS)
struct MacGlassButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, small ? 7 : 14)
            .padding(.vertical, small ? 5 : (controlSize == .large ? 9 : 7))
            .frame(minWidth: small ? 24 : 30, minHeight: small ? 24 : 30)
            .contentShape(.capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}
#endif
