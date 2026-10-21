#if DEBUG
import SwiftUI
import Compression

/// Generatore delle icone (solo DEBUG). Con `-BCWGenerateAppIcons /percorso/assoluto/BCW/Resources`
/// rende ogni combinazione di Impostazioni › Aspetto › Icona dell'app a 1024 × 1024 con lo stesso
/// disegno dell'anteprima (`AppIconArtwork`), scrive le icone piatte in `AppIcons.xcassets` (un
/// `.appiconset` per combinazione, con le immagini per le icone chiare, scure e colorate di iOS)
/// e l'icona principale a livelli `AppIcon.icon`, poi esce. iOS non sa disegnare le icone mentre
/// l'app gira: vanno tutte nel pacchetto.
///
/// I PNG sono a tavolozza (256 colori, con trasparenza): pesano un terzo di quelli di Core
/// Graphics nel repository; nel catalogo compilato actool li ricodifica comunque.
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

    private struct ImageKey: Hashable {
        let shape: AppIconShape
        let color: AppIconColor
        let rendition: AppIconRendition
    }

    static func generate(resources: URL) throws -> Int {
        let files = FileManager.default
        let catalog = resources.appendingPathComponent("AppIcons.xcassets", isDirectory: true)
        // Ogni volta da capo: le combinazioni tolte non restano nel catalogo.
        if files.fileExists(atPath: catalog.path) { try files.removeItem(at: catalog) }
        try files.createDirectory(at: catalog, withIntermediateDirectories: true)
        try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: catalog.appendingPathComponent("Contents.json"))

        var images: [ImageKey: Data] = [:]
        let choices = AppIconChoice.allAlternates
        for choice in choices {
            guard let name = choice.assetName else { continue }
            let folder = catalog.appendingPathComponent("\(name).appiconset", isDirectory: true)
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let slots: [(file: String, rendition: AppIconRendition, appearance: String?)] = [
                ("chiara.png", choice.variant.light, nil),
                ("scura.png", choice.variant.dark, "dark"),
                ("colorata.png", choice.variant.tinted, "tinted"),
            ]
            var entries: [String] = []
            for slot in slots {
                // La colorata non dipende dal colore; l'icona classica ha un solo colore.
                let color: AppIconColor = slot.rendition == .tinted || choice.shape == .classic ? .mattone : choice.color
                let key = ImageKey(shape: choice.shape, color: color, rendition: slot.rendition)
                let data: Data
                if let cached = images[key] {
                    data = cached
                } else {
                    data = try render(AppIconChoice(shape: choice.shape, color: color, variant: choice.variant), slot.rendition)
                    images[key] = data
                }
                try data.write(to: folder.appendingPathComponent(slot.file))
                let appearance = slot.appearance.map { #""appearances":[{"appearance":"luminosity","value":"\#($0)"}],"# } ?? ""
                entries.append(#"{\#(appearance)"filename":"\#(slot.file)","idiom":"universal","platform":"ios","size":"1024x1024"}"#)
            }
            let contents = #"{"images":[\#(entries.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
            try Data(contents.utf8).write(to: folder.appendingPathComponent("Contents.json"))
        }
        try writePrimaryIcon(resources.appendingPathComponent("AppIcon.icon", isDirectory: true))
        return choices.count
    }

    // MARK: Immagini

    private static func render(_ choice: AppIconChoice, _ rendition: AppIconRendition) throws -> Data {
        let size = 1024
        let renderer = ImageRenderer(content: AppIconArtwork(shape: choice.shape,
                                                             colors: AppIconPalette.colors(for: choice, rendition: rendition),
                                                             size: CGFloat(size)))
        renderer.scale = 1
        renderer.isOpaque = rendition.isOpaque
        guard let image = renderer.cgImage,
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let pixels = context.data else { throw CocoaError(.fileWriteUnknown) }
        let rgba = UnsafeMutableBufferPointer(start: pixels.assumingMemoryBound(to: UInt8.self), count: size * size * 4)
        // Da premoltiplicato a diretto (il PNG vuole i colori senza l'alfa applicata).
        var i = 0
        while i < rgba.count {
            let a = Int(rgba[i + 3])
            if a == 0 {
                rgba[i] = 0; rgba[i + 1] = 0; rgba[i + 2] = 0
            } else if a < 255 {
                for c in 0..<3 { rgba[i + c] = UInt8(min(255, (Int(rgba[i + c]) * 255 + a / 2) / a)) }
            }
            i += 4
        }
        return PalettePNG.encode(rgba: UnsafeBufferPointer(rgba), width: size, height: size, opaque: rendition.isOpaque)
    }

    // MARK: Icona principale (Icon Composer)

    /// `AppIcon.icon`: la combinazione predefinita (cerchio, Mattone, automatica, sfondo scuro
    /// Material) a livelli di vetro: sfondo pieno (chiaro e scuro), forma e barra come due lastre.
    private static func writePrimaryIcon(_ folder: URL) throws {
        let files = FileManager.default
        let assets = folder.appendingPathComponent("Assets", isDirectory: true)
        if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
        try files.createDirectory(at: assets, withIntermediateDirectories: true)
        let scheme = AppIconPalette.scheme(for: .mattone)
        func srgb(_ values: SchemeValues, _ role: String) -> String {
            let hex = values.color(role)
            let parts = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { String(format: "%.5f", Double($0) / 255) }
            return "srgb:\(parts.joined(separator: ",")),1.00000"
        }
        let shape = AppIconChoice.primary.shape.material ?? .circle
        // Tracciati in unità SVG con un margine di 1, scalati ai punti della tela (1024).
        let shapeSVG = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1 -1 102 102" width="102" height="102"><path fill="#000000" d="\##(shape.svg)"/></svg>"##
        let barSVG = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1 -1 66 10.73" width="66" height="10.73"><rect fill="#000000" x="0" y="0" width="64" height="8.73" rx="4.365"/></svg>"##
        try Data(shapeSVG.utf8).write(to: assets.appendingPathComponent("bcw-forma.svg"))
        try Data(barSVG.utf8).write(to: assets.appendingPathComponent("bcw-linea.svg"))
        let shapeScale = String(format: "%.4f", 1024 * AppIconGeometry.shape / 100)
        let barScale = String(format: "%.4f", 1024 * AppIconGeometry.shape * AppIconGeometry.bar / 64)
        let gray = String(format: "%.5f", AppIconPalette.tintedShapeWhite)
        let tintedShape = "srgb:\(gray),\(gray),\(gray),1.00000"
        let json = """
        {
          "fill-specializations" : [
            { "value" : { "solid" : "\(srgb(scheme.light, "surface"))" } },
            { "appearance" : "dark", "value" : { "solid" : "\(srgb(scheme.dark, "surface-dim"))" } }
          ],
          "groups" : [
            {
              "layers" : [
                {
                  "fill-specializations" : [
                    { "value" : { "solid" : "\(srgb(scheme.light, "on-primary"))" } },
                    { "appearance" : "dark", "value" : { "solid" : "\(srgb(scheme.dark, "primary"))" } },
                    { "appearance" : "tinted", "value" : { "solid" : "srgb:1.00000,1.00000,1.00000,1.00000" } }
                  ],
                  "glass" : true,
                  "image-name" : "bcw-linea.svg",
                  "name" : "bcw-linea",
                  "position" : { "scale" : \(barScale), "translation-in-points" : [ 0, 0 ] }
                }
              ],
              "name" : "Barra",
              "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
              "translucency" : { "enabled" : true, "value" : 0.3 }
            },
            {
              "layers" : [
                {
                  "fill-specializations" : [
                    { "value" : { "solid" : "\(srgb(scheme.light, "primary"))" } },
                    { "appearance" : "dark", "value" : { "solid" : "\(srgb(scheme.dark, "primary-container"))" } },
                    { "appearance" : "tinted", "value" : { "solid" : "\(tintedShape)" } }
                  ],
                  "glass" : true,
                  "image-name" : "bcw-forma.svg",
                  "name" : "bcw-forma",
                  "position" : { "scale" : \(shapeScale), "translation-in-points" : [ 0, 0 ] }
                }
              ],
              "name" : "Forma",
              "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
              "translucency" : { "enabled" : true, "value" : 0.3 }
            }
          ],
          "supported-platforms" : {
            "circles" : [ "watchOS" ],
            "squares" : "shared"
          }
        }

        """
        try Data(json.utf8).write(to: folder.appendingPathComponent("icon.json"))
    }
}

// MARK: - PNG a tavolozza

/// Codifica PNG a tavolozza (fino a 256 colori, trasparenza con `tRNS`) di pixel RGBA diretti.
/// I colori oltre i 256 più frequenti (pochi, sui bordi sfumati) prendono il più vicino.
private enum PalettePNG {
    static func encode(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, opaque: Bool) -> Data {
        let count = width * height
        func pixel(_ i: Int) -> UInt32 {
            let o = i * 4
            let alpha: UInt32 = opaque ? 255 : UInt32(rgba[o + 3])
            return UInt32(rgba[o]) << 24 | UInt32(rgba[o + 1]) << 16 | UInt32(rgba[o + 2]) << 8 | alpha
        }
        // Colori per frequenza (le file di pixel uguali si contano in blocco).
        var counts: [UInt32: Int] = [:]
        var last = pixel(0), run = 0
        for i in 0..<count {
            let p = pixel(i)
            if p == last { run += 1 } else { counts[last, default: 0] += run; last = p; run = 1 }
        }
        counts[last, default: 0] += run
        let palette = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(256).map(\.key)
        var index: [UInt32: UInt8] = [:]
        for (i, color) in palette.enumerated() { index[color] = UInt8(i) }
        func lookup(_ color: UInt32) -> UInt8 {
            if let i = index[color] { return i }
            var best = 0, bestDistance = Int.max
            for (i, candidate) in palette.enumerated() {
                var distance = 0
                for shift in [24, 16, 8, 0] as [UInt32] {
                    let d = Int((color >> shift) & 0xFF) - Int((candidate >> shift) & 0xFF)
                    distance += d * d
                }
                if distance < bestDistance { bestDistance = distance; best = i }
            }
            index[color] = UInt8(best)
            return UInt8(best)
        }
        // Righe con il filtro 0 (le righe uguali si comprimono in un rimando).
        var raw = [UInt8](repeating: 0, count: (width + 1) * height)
        var lastColor = pixel(0), lastIndex = lookup(lastColor)
        raw.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let row = y * (width + 1)
                for x in 0..<width {
                    let p = pixel(y * width + x)
                    if p != lastColor { lastColor = p; lastIndex = lookup(p) }
                    out[row + 1 + x] = lastIndex
                }
            }
        }
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.append(bigEndian: UInt32(width))
        header.append(bigEndian: UInt32(height))
        header.append(contentsOf: [8, 3, 0, 0, 0])
        png.append(chunk("IHDR", header))
        png.append(chunk("PLTE", Data(palette.flatMap { [UInt8($0 >> 24), UInt8(($0 >> 16) & 0xFF), UInt8(($0 >> 8) & 0xFF)] })))
        let alphas = palette.map { UInt8($0 & 0xFF) }
        if let lastTransparent = alphas.lastIndex(where: { $0 != 255 }) {
            png.append(chunk("tRNS", Data(alphas[0...lastTransparent])))
        }
        png.append(chunk("IDAT", zlib(raw)))
        png.append(chunk("IEND", Data()))
        return png
    }

    private static func zlib(_ input: [UInt8]) -> Data {
        let capacity = input.count + 1024
        var output = [UInt8](repeating: 0, count: capacity)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_encode_buffer(destination.baseAddress!, capacity, source.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        var data = Data([0x78, 0x5E])
        data.append(contentsOf: output[0..<written])
        // Adler-32 (modulo ogni 5552 byte, come zlib).
        var a: UInt32 = 1, b: UInt32 = 0
        input.withUnsafeBufferPointer { bytes in
            var start = 0
            while start < bytes.count {
                let end = min(start + 5552, bytes.count)
                for i in start..<end { a += UInt32(bytes[i]); b += a }
                a %= 65521; b %= 65521
                start = end
            }
        }
        data.append(bigEndian: b << 16 | a)
        return data
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func chunk(_ type: String, _ body: Data) -> Data {
        var data = Data()
        data.append(bigEndian: UInt32(body.count))
        let typed = Data(type.utf8) + body
        data.append(typed)
        var crc: UInt32 = 0xFFFFFFFF
        for byte in typed { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        data.append(bigEndian: crc ^ 0xFFFFFFFF)
        return data
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
#endif
