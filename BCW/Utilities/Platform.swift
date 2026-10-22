import SwiftUI
import UIKit

/// Piccoli adattatori verso UIKit, per non usarne le API direttamente nelle viste.
enum Platform {
    /// Copia un testo negli appunti.
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// Apre le impostazioni di sistema di BCW (notifiche, attività in diretta).
    static func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

typealias PlatformFont = UIFont
typealias PlatformColor = UIColor

extension PlatformColor {
    nonisolated convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Valore da conservare in `@State` senza che cambiarlo ridisegni la vista: per misure che
/// cambiano spesso (es. a ogni fotogramma di un'animazione) ma servono solo in certi momenti.
final class UnobservedValue<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Riga con una colonna fissa a sinistra (data, casella) e il resto a destra, allineati in alto:
/// come `HStack(alignment: .top, spacing:)`, ma la colonna di destra riceve subito la larghezza che
/// resta. L'`HStack` misura prima i figli con larghezze di prova (zero, infinita) per capire chi si
/// allarga: con testi su più righe e righe annidate (i giorni di "Nei prossimi giorni") quasi tutto
/// il tempo del cambio di giorno andava in queste misure.
struct LeadingColumnLayout: Layout {
    var spacing: CGFloat = 12

    private func leadingSize(_ subviews: Subviews, height: CGFloat?) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: nil, height: height)) ?? .zero
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lead = leadingSize(subviews, height: proposal.height)
        guard subviews.count > 1 else { return lead }
        let width = proposal.width.map { max(0, $0 - lead.width - spacing) }
        let rest = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: lead.width + spacing + rest.width, height: max(lead.height, rest.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lead = leadingSize(subviews, height: proposal.height)
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(lead))
        guard subviews.count > 1 else { return }
        let x = bounds.minX + lead.width + spacing
        subviews[1].place(at: CGPoint(x: x, y: bounds.minY),
                          proposal: ProposedViewSize(width: max(0, bounds.maxX - x), height: proposal.height))
    }
}

extension View {
    /// Titolo della pagina nella barra di navigazione.
    func screenTitle(_ title: String, subtitle: String? = nil) -> some View {
        navigationTitle(title)
    }

    /// Titolo piccolo al centro della barra.
    func inlineTitleDisplay() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    /// Margini laterali delle pagine: 16 punti (24 sull'iPad con la finestra larga).
    func pagePadding() -> some View {
        modifier(PagePadding())
    }

}

private struct PagePadding: ViewModifier {
    @Environment(\.pageGutter) private var gutter

    func body(content: Content) -> some View {
        content.padding(.horizontal, gutter)
    }
}

/// Elenco di card in una colonna; sull'iPad largo in colonne larghe almeno `minWidth`.
struct CardGrid<Content: View>: View {
    var minWidth: CGFloat = 340
    var spacing: CGFloat = 10
    @ViewBuilder let content: () -> Content
    @Environment(\.windowClass) private var windowClass

    var body: some View {
        if windowClass == .regular {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: spacing, alignment: .top)],
                      spacing: spacing, content: content)
        } else {
            LazyVStack(spacing: spacing, content: content)
        }
    }
}

/// Ricerca dentro una singola pagina (bacheca, agenda, materiale).
extension View {
    func localSearchable(text: Binding<String>, prompt: String) -> some View {
        modifier(GlassLocalSearch(text: text, prompt: prompt))
    }
}

/// Riga di filtri che scorre in orizzontale.
/// Arriva fino ai bordi della pagina (oltre il margine laterale), allineata al contenuto.
struct ChipRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.pageGutter) private var gutter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
                .padding(.vertical, 2)
                .padding(.horizontal, gutter)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -gutter)
    }
}

/// Separatore verticale tra gruppi di filtri (funziona anche dentro `FlowLayout`).
struct ChipDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.outlineVariant)
            .frame(width: 1, height: 24)
    }
}

/// Pila di navigazione delle schede principali.
struct PlatformNavigationStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .environment(\.isRootPage, true)
        }
    }
}
