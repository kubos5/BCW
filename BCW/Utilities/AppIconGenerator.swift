#if DEBUG
import CoreGraphics
import Foundation

/// Generatore delle icone (solo DEBUG). Con `-BCWGenerateAppIcons /percorso/assoluto/BCW/Resources`
/// scrive le icone di Icon Composer di Impostazioni › Aspetto › Icona dell'app, poi esce: la
/// principale `AppIcon.icon` (Mattone) e le altre nove in `AppIcons/<nome>.icon`. iOS non
/// sa disegnare le icone mentre l'app gira: vanno tutte nel pacchetto.
///
/// Ogni icona ha lo sfondo e il logo dell'introduzione: la scritta "BCW" e la barra, in due gruppi
/// distinti con il vetro, così iOS li disegna come due lastre (ombra e riflessi per gruppo, come le
/// icone di sistema). Colori e tracciati sono quelli dell'anteprima (`AppIconPalette`,
/// `AppIconLogo`). Il risultato è deterministico: con un percorso di prova i file escono
/// identici a quelli del repository.
enum AppIconGenerator {
    static func runIfRequested() {
        guard let root = UserDefaults.standard.string(forKey: "BCWGenerateAppIcons") else { return }
        do {
            let count = try generate(resources: URL(fileURLWithPath: root, isDirectory: true))
            print("BCW-APPICONS OK \(count)")
        } catch {
            print("BCW-APPICONS FAIL \(error)")
        }
        exit(0)
    }

    static func generate(resources: URL) throws -> Int {
        let files = FileManager.default
        let alternates = resources.appendingPathComponent("AppIcons", isDirectory: true)
        // Ogni volta da capo: le combinazioni tolte non restano.
        if files.fileExists(atPath: alternates.path) { try files.removeItem(at: alternates) }
        try files.createDirectory(at: alternates, withIntermediateDirectories: true)
        let choices = AppIconChoice.all
        for choice in choices {
            let folder = choice.assetName.map { alternates.appendingPathComponent("\($0).icon", isDirectory: true) }
                ?? resources.appendingPathComponent("AppIcon.icon", isDirectory: true)
            try write(choice, to: folder)
        }
        return choices.count
    }

    /// Una cartella `.icon`: `icon.json` e gli SVG della scritta e della barra, in punti della tela
    /// (1024) con un margine di 2 attorno alla forma: Icon Composer mette il centro dell'immagine al
    /// centro della tela più lo spostamento (`translation`).
    private static func write(_ choice: AppIconChoice, to folder: URL) throws {
        let files = FileManager.default
        let assets = folder.appendingPathComponent("Assets", isDirectory: true)
        if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
        try files.createDirectory(at: assets, withIntermediateDirectories: true)
        let canvas = CGAffineTransform(scaleX: 1024, y: 1024)
        let text = AppIconLogo.shapes.text.copy(using: [canvas]) ?? AppIconLogo.shapes.text
        let bar = AppIconLogo.shapes.bar.applying(canvas)
        try Data(svg(svgPath(text), bounds: text.boundingBoxOfPath).utf8).write(to: assets.appendingPathComponent("bcw-scritta.svg"))
        let barPath = CGPath(roundedRect: bar, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2, transform: nil)
        try Data(svg(svgPath(barPath), bounds: bar).utf8).write(to: assets.appendingPathComponent("bcw-linea.svg"))
        try json(for: choice, text: text.boundingBoxOfPath, bar: bar).write(to: folder.appendingPathComponent("icon.json"))
    }

    private static func number(_ value: CGFloat) -> String {
        let text = String(format: "%.2f", value)
        return text == "-0.00" ? "0.00" : text
    }

    private static func svg(_ path: String, bounds: CGRect) -> String {
        let box = bounds.insetBy(dx: -2, dy: -2)
        let size = "width=\"\(number(box.width))\" height=\"\(number(box.height))\""
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(number(box.minX)) \(number(box.minY)) \(number(box.width)) \(number(box.height))\" \(size)><path fill=\"#000000\" d=\"\(path)\"/></svg>"
    }

    /// Il tracciato in sintassi SVG.
    private static func svgPath(_ path: CGPath) -> String {
        var parts: [String] = []
        func point(_ p: CGPoint) -> String { "\(number(p.x)) \(number(p.y))" }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: parts.append("M\(point(points[0]))")
            case .addLineToPoint: parts.append("L\(point(points[0]))")
            case .addQuadCurveToPoint: parts.append("Q\(point(points[0])) \(point(points[1]))")
            case .addCurveToPoint: parts.append("C\(point(points[0])) \(point(points[1])) \(point(points[2]))")
            case .closeSubpath: parts.append("Z")
            @unknown default: break
            }
        }
        return parts.joined()
    }

    private static func srgb(_ hex: Int) -> String {
        let parts = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { String(format: "%.5f", Double($0) / 255) }
        return "srgb:\(parts.joined(separator: ",")),1.00000"
    }

    private static func solid(_ hex: Int) -> [String: Any] { ["solid": srgb(hex)] }

    /// Una voce di `fill-specializations` (`appearance` nil = quella predefinita).
    private static func entry(_ appearance: String?, _ value: Any) -> [String: Any] {
        var entry: [String: Any] = ["value": value]
        if let appearance { entry["appearance"] = appearance }
        return entry
    }

    /// Numero scritto con al massimo quattro decimali, senza le cifre spurie dei Double
    /// (`JSONSerialization` scriveva 0.29999999999999999).
    private static func decimal(_ value: CGFloat) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.4f", value))
    }

    private static func json(for choice: AppIconChoice, text: CGRect, bar: CGRect) throws -> Data {
        let light = AppIconPalette.scheme(for: choice.color, dark: false)
        let dark = AppIconPalette.scheme(for: choice.color, dark: true)
        func gray(_ white: CGFloat) -> [String: Any] {
            let value = String(format: "%.5f", white)
            return ["solid": "srgb:\(value),\(value),\(value),1.00000"]
        }
        // Sfondo nel contenitore primario del tema chiaro e, con le icone scure, quello scuro di iOS
        // (`automatic`). Con le icone colorate iOS tinge la scala di grigi: scritta bianca, barra grigia.
        let background = [entry(nil, solid(light.background)), entry("dark", "automatic")]
        func group(_ name: String, _ layer: String, _ fills: [[String: Any]], _ frame: CGRect) -> [String: Any] {
            [
                "layers": [[
                    "fill-specializations": fills,
                    "glass": true,
                    "image-name": "\(layer).svg",
                    "name": layer,
                    "position": ["scale": decimal(1), "translation-in-points": [decimal(frame.midX), decimal(frame.midY)]] as [String: Any],
                ] as [String: Any]],
                "name": name,
                "shadow": ["kind": "neutral", "opacity": decimal(0.5)] as [String: Any],
                "translucency": ["enabled": true, "value": decimal(0.3)] as [String: Any],
            ]
        }
        let icon: [String: Any] = [
            "fill-specializations": background,
            // Il primo gruppo sta sopra: la barra e la scritta non si toccano, l'ordine conta solo per le ombre.
            "groups": [
                group("Barra", "bcw-linea", [entry(nil, solid(light.bar)), entry("dark", solid(dark.bar)),
                                             entry("tinted", gray(AppIconPalette.tintedBar))], bar),
                group("Scritta", "bcw-scritta", [entry(nil, solid(light.text)), entry("dark", solid(dark.text)),
                                                 entry("tinted", gray(AppIconPalette.tintedText))], text),
            ],
            "supported-platforms": ["circles": ["watchOS"], "squares": "shared"] as [String: Any],
        ]
        var data = try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
#endif
