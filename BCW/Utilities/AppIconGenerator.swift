#if DEBUG
import Foundation

/// Generatore delle icone (solo DEBUG). Con `-BCWGenerateAppIcons /percorso/assoluto/BCW/Resources`
/// scrive le icone di Icon Composer di Impostazioni › Aspetto › Icona dell'app, poi esce: la
/// principale `AppIcon.icon` (Mattone, automatica) e le altre in `AppIcons/<nome>.icon`. iOS non
/// sa disegnare le icone mentre l'app gira: vanno tutte nel pacchetto.
///
/// Ogni icona ha tre livelli: lo sfondo, il cerchio e la barra, questi ultimi in due gruppi
/// distinti con il vetro, così iOS li disegna come due lastre (ombra e riflessi per gruppo, come le
/// icone di sistema). Colori e proporzioni sono quelli dell'anteprima (`AppIconPalette`,
/// `AppIconGeometry`). Il risultato è deterministico: con un percorso di prova i file escono
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

    /// Una cartella `.icon`: `icon.json` e gli SVG del cerchio e della barra.
    private static func write(_ choice: AppIconChoice, to folder: URL) throws {
        let files = FileManager.default
        let assets = folder.appendingPathComponent("Assets", isDirectory: true)
        if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
        try files.createDirectory(at: assets, withIntermediateDirectories: true)
        // Tracciati in unità SVG con un margine di 1, scalati ai punti della tela (1024).
        let shapeSVG = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1 -1 102 102" width="102" height="102"><path fill="#000000" d="\##(MaterialShapeName.circle.svg)"/></svg>"##
        let barSVG = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1 -1 66 10.73" width="66" height="10.73"><rect fill="#000000" x="0" y="0" width="64" height="8.73" rx="4.365"/></svg>"##
        try Data(shapeSVG.utf8).write(to: assets.appendingPathComponent("bcw-forma.svg"))
        try Data(barSVG.utf8).write(to: assets.appendingPathComponent("bcw-linea.svg"))
        try json(for: choice).write(to: folder.appendingPathComponent("icon.json"))
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

    private static func json(for choice: AppIconChoice) throws -> Data {
        let tint = choice.color.tint ?? AppIconPalette.tints[.mattone]!
        let gray = String(format: "%.5f", AppIconPalette.tintedShapeWhite)
        let tintedShape: [String: Any] = ["solid": "srgb:\(gray),\(gray),\(gray),1.00000"]
        // Automatica: sfondo bianco caldo, e con le icone scure quello di iOS (`automatic`) con il
        // cerchio più chiaro. Sempre scura: lo sfondo scuro di iOS (`system-dark`) e il cerchio della
        // scura anche con le icone chiare. Con le icone colorate il cerchio è grigio (iOS tinge).
        let background: [[String: Any]]
        let shape: [[String: Any]]
        switch choice.appearance {
        case .automatic:
            background = [entry(nil, solid(AppIconPalette.lightBackground)), entry("dark", "automatic")]
            shape = [entry(nil, solid(tint.light)), entry("dark", solid(tint.dark)), entry("tinted", tintedShape)]
        case .dark:
            background = [entry(nil, "system-dark")]
            shape = [entry(nil, solid(tint.dark)), entry("tinted", tintedShape)]
        }
        func group(_ name: String, _ layer: String, _ fills: [[String: Any]], _ scale: CGFloat) -> [String: Any] {
            [
                "layers": [[
                    "fill-specializations": fills,
                    "glass": true,
                    "image-name": "\(layer).svg",
                    "name": layer,
                    "position": ["scale": decimal(scale), "translation-in-points": [0, 0]],
                ] as [String: Any]],
                "name": name,
                "shadow": ["kind": "neutral", "opacity": decimal(0.5)] as [String: Any],
                "translucency": ["enabled": true, "value": decimal(0.3)] as [String: Any],
            ]
        }
        let icon: [String: Any] = [
            "fill-specializations": background,
            // Il primo gruppo sta sopra.
            "groups": [
                group("Barra", "bcw-linea", [entry(nil, solid(AppIconPalette.bar))],
                      1024 * AppIconGeometry.shape * AppIconGeometry.bar / 64),
                group("Forma", "bcw-forma", shape, 1024 * AppIconGeometry.shape / 100),
            ],
            "supported-platforms": ["circles": ["watchOS"], "squares": "shared"] as [String: Any],
        ]
        var data = try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
#endif
