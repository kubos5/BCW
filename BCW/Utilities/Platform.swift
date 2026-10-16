import SwiftUI
import UIKit

/// Piccoli adattatori verso UIKit, per non usarne le API direttamente nelle viste.
enum Platform {
    /// Copia un testo negli appunti.
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// Apre le impostazioni di sistema delle notifiche per BCW.
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

extension View {
    /// Titolo della pagina nella barra di navigazione.
    func screenTitle(_ title: String, subtitle: String? = nil) -> some View {
        navigationTitle(title)
    }

    /// Titolo piccolo al centro della barra.
    func inlineTitleDisplay() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    /// Margini laterali delle pagine.
    func pagePadding() -> some View {
        padding(.horizontal)
    }

}

/// Elenco di card in una colonna.
struct CardGrid<Content: View>: View {
    var minWidth: CGFloat = 340
    var spacing: CGFloat = 10
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVStack(spacing: spacing, content: content)
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

/// Ricerca dentro una singola pagina (bacheca, agenda, materiale).
extension View {
    func localSearchable(text: Binding<String>, prompt: String) -> some View {
        modifier(GlassLocalSearch(text: text, prompt: prompt))
    }
}

/// Riga di filtri che scorre in orizzontale.
struct ChipRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
                .padding(.vertical, 2)
                .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -16)
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
