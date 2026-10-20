import Foundation

/// Colori predefiniti di BCW, comuni all'app (`ThemeStore`, `Theme`) e ai widget: i ruoli di
/// Material 3 dello schema Tonal Spot dal rosso mattone (gli stessi di `css/bcw.css`) e i toni
/// fissi degli stati (bene, sufficiente, insufficiente, neutro).
nonisolated enum ThemeDefaults {
    static let light: [String: String] = [
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
    ]

    static let dark: [String: String] = [
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
    ]

    /// Colore chiaro e scuro (RGB esadecimale).
    typealias Pair = (light: Int, dark: Int)

    // Stati (come `--good`, `--fair`, `--poor`, `--neutral` della versione web).
    static let good: Pair = (0x2B6A45, 0x94D5A7)
    static let onGood: Pair = (0xFFFFFF, 0x00391D)
    static let goodContainer: Pair = (0xAFF2C2, 0x0D512F)
    static let onGoodContainer: Pair = (0x00210F, 0xAFF2C2)
    static let fair: Pair = (0x855300, 0xFFB95F)
    static let onFair: Pair = (0xFFFFFF, 0x472A00)
    static let fairContainer: Pair = (0xFFDDB8, 0x653E00)
    static let onFairContainer: Pair = (0x2A1700, 0xFFDDB8)
    static let poor: Pair = (0xAB3429, 0xFFB4A9)
    static let onPoor: Pair = (0xFFFFFF, 0x690002)
    static let poorContainer: Pair = (0xFFDAD5, 0x8A1C14)
    static let onPoorContainer: Pair = (0x410001, 0xFFDAD5)
    static let neutral: Pair = (0x426182, 0xAAC9EF)
    static let onNeutral: Pair = (0xFFFFFF, 0x0F3251)
    static let neutralContainer: Pair = (0xD1E4FF, 0x2A4969)
    static let onNeutralContainer: Pair = (0x001D35, 0xD1E4FF)

    /// Toni degli stati come ruoli (`good`, `good-container`, `on-good-container`…), aggiunti ai
    /// ruoli del tema nell'istantanea dei widget.
    static var toneRoles: (light: [String: String], dark: [String: String]) {
        let tones: [(String, Pair)] = [
            ("good", good), ("on-good", onGood), ("good-container", goodContainer), ("on-good-container", onGoodContainer),
            ("fair", fair), ("on-fair", onFair), ("fair-container", fairContainer), ("on-fair-container", onFairContainer),
            ("poor", poor), ("on-poor", onPoor), ("poor-container", poorContainer), ("on-poor-container", onPoorContainer),
            ("neutral", neutral), ("on-neutral", onNeutral), ("neutral-container", neutralContainer),
            ("on-neutral-container", onNeutralContainer),
        ]
        var light: [String: String] = [:]
        var dark: [String: String] = [:]
        for (name, pair) in tones {
            light[name] = hexString(pair.light)
            dark[name] = hexString(pair.dark)
        }
        return (light, dark)
    }

    static func hexString(_ value: Int) -> String { String(format: "#%06x", value & 0xFFFFFF) }

    static func hexValue(_ string: String?) -> Int? {
        guard let string else { return nil }
        let digits = string.hasPrefix("#") ? String(string.dropFirst()) : string
        return Int(digits, radix: 16)
    }
}
