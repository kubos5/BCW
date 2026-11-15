import SwiftUI
import WidgetKit

/// Widget nella build dell'App Store senza BCW+ (richiesta dell'utente, 4.0): al posto del contenuto
/// solo una scritta che dice che i widget non sono disponibili senza il pagamento di 2,99 €. Si vede
/// anche nella galleria dei widget di iOS (l'istantanea bloccata vale anche per le anteprime) e un
/// tocco apre la schermata dell'acquisto (`bcw://plus`).
struct LockedWidgetView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    let palette: WidgetPalette

    private var price: String { snapshot.plusPrice ?? "2,99\u{00A0}€" }

    var body: some View {
        content
            .widgetURL(DeepLink.plus.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label { Text("Widget con BCW+") } icon: { Image("m.lock").renderingMode(.template) }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                WidgetIcon("lock", size: 22)
                    .widgetAccentable()
            }
            .accessibilityLabel("Widget non disponibili senza BCW+")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    WidgetIcon("lock", size: 13)
                        .widgetAccentable()
                    Text("BCW+")
                        .font(palette.font(15, weight: 650, rounded: true))
                }
                Text("Widget non disponibili senza il pagamento di \(price)")
                    .font(palette.font(12))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            let large = family == .systemLarge
            VStack(alignment: large ? .center : .leading, spacing: large ? 10 : 6) {
                WidgetIcon("lock", size: large ? 26 : 18)
                    .foregroundStyle(palette.isFullColor ? palette.role("primary") : palette.accent)
                    .widgetAccentable()
                Text("Widget non disponibili")
                    .font(palette.font(large ? 20 : 15, weight: 650, rounded: true))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("I widget di BCW richiedono BCW+, con un pagamento unico di \(price). Tocca per scoprirla.")
                    .font(palette.font(large ? 14 : 12))
                    .foregroundStyle(palette.secondaryInk)
                    .lineLimit(large ? 4 : (family == .systemSmall ? 5 : 3))
                    .minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(large ? .center : .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: large ? .center : .leading)
        }
    }
}
