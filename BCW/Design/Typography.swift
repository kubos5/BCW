import SwiftUI
import CoreText

/// Caratteri di BCW: Google Sans Flex (lo stesso della versione web), un font variabile di cui si
/// usano gli assi del peso (`wght`), della dimensione ottica (`opsz`) e dell'arrotondamento
/// (`ROND`, pieno nei titoli e leggero nel testo, come in `css/bcw.css`).
enum Typography {
    /// Descrittore di base del font incorporato (registrato alla prima richiesta).
    private static let base: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "GoogleSansFlex", withExtension: "ttf") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        return descriptors?.first
    }()

    private static let wghtAxis = 0x7767_6874 // 'wght'
    private static let opszAxis = 0x6F70_737A // 'opsz'
    private static let rondAxis = 0x524F_4E44 // 'ROND'

    private struct Key: Hashable {
        let size: CGFloat
        let weight: CGFloat
        let rond: CGFloat
    }

    // Creare un font variabile costa: si tengono quelli già usati (pochi, sono i token della scala).
    private static var cache: [Key: CTFont] = [:]

    /// Font di Core Text con peso e arrotondamento dati (anche per UIKit e AppKit).
    static func ctFont(size: CGFloat, weight: CGFloat, rond: CGFloat) -> CTFont {
        let key = Key(size: size, weight: weight, rond: rond)
        if let font = cache[key] { return font }
        let font: CTFont
        if let base {
            let variation: [Int: CGFloat] = [wghtAxis: weight, opszAxis: min(max(size, 6), 144), rondAxis: rond]
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(
                base, [kCTFontVariationAttribute: variation] as CFDictionary)
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        } else {
            font = CTFontCreateUIFontForLanguage(.system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        cache[key] = font
        return font
    }

    /// Font di UIKit o AppKit (barre di sistema con Liquid Glass).
    static func platformFont(size: CGFloat, weight: CGFloat, rounded: Bool = false) -> PlatformFont {
        let rond = rounded ? ThemeStore.shared.rond : ThemeStore.shared.rondBody
        return ctFont(size: size, weight: weight, rond: rond) as PlatformFont
    }
}

/// Stili della scala tipografica di M3 (le varianti "em" sono quelle enfatizzate di Expressive).
enum TextRole {
    case displayS, headlineL, headlineM, headlineS, titleL, titleM, titleS
    case bodyL, bodyM, bodyS, labelL, labelM, labelS

    var size: CGFloat {
        switch self {
        case .displayS: 36
        case .headlineL: 32
        case .headlineM: 28
        case .headlineS: 24
        case .titleL: 22
        case .titleM, .bodyL: 16
        case .titleS, .bodyM, .labelL: 14
        case .bodyS, .labelM: 12
        case .labelS: 11
        }
    }

    var weight: CGFloat {
        switch self {
        case .displayS, .headlineL, .headlineM, .headlineS, .titleL: 450
        case .titleM, .titleS, .labelL, .labelM, .labelS: 550
        case .bodyL, .bodyM, .bodyS: 400
        }
    }

    /// Titoli con l'asse ROND pieno, il resto con quello del testo.
    var rounded: Bool {
        switch self {
        case .displayS, .headlineL, .headlineM, .headlineS, .titleL: true
        default: false
        }
    }

    var tracking: CGFloat {
        switch self {
        case .titleM: 0.15
        case .titleS, .labelL: 0.1
        case .bodyL, .bodyS: 0.3
        case .bodyM: 0.2
        case .labelM, .labelS: 0.4
        default: 0
        }
    }
}

extension Font {
    /// Google Sans Flex a una dimensione e un peso (100–1000). `rounded` usa l'arrotondamento
    /// dei titoli (scelto in Impostazioni › Aspetto), altrimenti quello del testo.
    static func m3(_ size: CGFloat, weight: CGFloat = 400, rounded: Bool = false) -> Font {
        let store = ThemeStore.shared
        return Font(Typography.ctFont(size: size, weight: weight, rond: rounded ? store.rond : store.rondBody))
    }

    static func m3(_ role: TextRole, emphasized: Bool = false) -> Font {
        m3(role.size, weight: emphasized ? 700 : role.weight, rounded: role.rounded)
    }

    /// Numeri grandi per medie e voti (cifre allineate, peso 650, arrotondati).
    static func numeral(_ size: CGFloat, weight: CGFloat = 650) -> Font {
        m3(size, weight: weight, rounded: true).monospacedDigit()
    }
}

extension View {
    /// Applica uno stile della scala tipografica (font e spaziatura tra le lettere).
    func textRole(_ role: TextRole, emphasized: Bool = false) -> some View {
        font(.m3(role, emphasized: emphasized))
            .tracking(role.tracking)
    }
}
