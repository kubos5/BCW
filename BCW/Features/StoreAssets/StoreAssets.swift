#if DEBUG
import SwiftUI
import WidgetKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Generatore

/// Immagini della pagina dell'App Store (solo DEBUG): screenshot composti per iPhone 6,9" e 6,3" e per
/// iPad 13", immagini dell'evento in-app. `-BCWGenerateStoreAssets <cartella>` legge le catture della demo
/// da `<cartella>/raw` (nomi in `StoreSlide`, vedi CLAUDE.md), scrive le immagini nelle sottocartelle
/// ed esce. `-BCWStoreAssetsOnly <testo>` rifà solo i file il cui percorso contiene quel testo.
/// Le immagini non hanno il canale alfa (App Store Connect lo rifiuta).
enum StoreAssets {
    /// Ora mostrata da widget e attività in diretta: il lunedì di questa settimana alle 10:20, a metà
    /// della terza ora (`FrozenClock` ferma lì i testi e le barre del tempo).
    static let now: Date = {
        let calendar = BCWShared.calendar
        let today = calendar.startOfDay(for: Date())
        let monday = calendar.date(byAdding: .day, value: -(BCWShared.weekday(of: today) - 1), to: today) ?? today
        return calendar.date(byAdding: .minute, value: 10 * 60 + 20, to: monday) ?? monday
    }()

    /// "10:20" e "Lunedì 9 novembre" per la schermata di blocco e la barra di stato.
    static var timeText: String { TimeOfDay.string(BCWShared.minutes(of: now)) }
    static var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = BCWShared.calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        let text = formatter.string(from: now)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func generateIfRequested() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "BCWGenerateStoreAssets") else { return }
        let root = URL(fileURLWithPath: path)
        let only = defaults.string(forKey: "BCWStoreAssetsOnly")
        FrozenClock.date = now
        let images = StoreImages(folder: root.appendingPathComponent("raw"))
        var written = 0
        for job in jobs() where only == nil || job.path.contains(only ?? "") {
            let url = root.appendingPathComponent(job.path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Disegnate a metà misura con densità 2: gli ingrandimenti con ombra o rotazione (che SwiftUI
            // disegna a parte alla misura della vista) restano nitidi.
            let half = CGSize(width: job.size.width / 2, height: job.size.height / 2)
            let ok = autoreleasepool { render(job.view(images, half), size: half, to: url) }
            print(ok ? "BCW-STOREASSETS \(job.path)" : "BCW-STOREASSETS FAIL \(job.path)")
            if ok { written += 1 }
        }
        print("BCW-STOREASSETS OK \(written)")
        exit(0)
    }

    private struct Job {
        let path: String
        let size: CGSize
        let view: (StoreImages, CGSize) -> AnyView
    }

    private static func jobs() -> [Job] {
        var jobs: [Job] = []
        let phones: [(String, CGSize)] = [
            ("iPhone 6,9 pollici", CGSize(width: 1320, height: 2868)),
            ("iPhone 6,3 pollici", CGSize(width: 1206, height: 2622)),
        ]
        for (folder, size) in phones {
            for (index, slide) in StoreSlide.phone.enumerated() {
                jobs.append(Job(path: "\(folder)/\(String(format: "%02d", index + 1))-\(slide.id).png", size: size) {
                    AnyView(StorePhoneSlide(slide: slide, size: $1, images: $0))
                })
            }
        }
        let pad = CGSize(width: 2064, height: 2752)
        for (index, slide) in StoreSlide.pad.enumerated() {
            jobs.append(Job(path: "iPad 13 pollici/\(String(format: "%02d", index + 1))-\(slide.id).png", size: pad) {
                AnyView(StorePadSlide(slide: slide, size: $1, images: $0))
            })
        }
        let card = CGSize(width: 1920, height: 1080), details = CGSize(width: 1080, height: 1920)
        jobs.append(Job(path: "Evento in-app/scheda-1920x1080.png", size: card) {
            AnyView(StoreEventArt(size: $1, images: $0))
        })
        jobs.append(Job(path: "Evento in-app/dettagli-1080x1920.png", size: details) {
            AnyView(StoreEventArt(size: $1, images: $0))
        })
        return jobs
    }

    /// Disegna la vista alla misura in pixel e la salva in PNG senza canale alfa.
    private static func render(_ view: AnyView, size: CGSize, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "it_IT")))
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { return false }
        return writeOpaquePNG(image, to: url)
    }

    /// PNG senza canale alfa (App Store Connect rifiuta le immagini con l'alfa).
    static func writeOpaquePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, flat, nil)
        return CGImageDestinationFinalize(destination)
    }
}

/// Le catture della demo (PNG in `raw`), caricate una volta.
final class StoreImages {
    private let folder: URL
    private var cache: [String: UIImage] = [:]

    init(folder: URL) { self.folder = folder }

    func image(_ name: String) -> UIImage {
        if let image = cache[name] { return image }
        let image = UIImage(contentsOfFile: folder.appendingPathComponent("\(name).png").path) ?? UIImage()
        if image.size == .zero { print("BCW-STOREASSETS manca raw/\(name).png") }
        cache[name] = image
        return image
    }
}

// MARK: - Contenuto

/// Una schermata della pagina: etichetta, titolo, sottotitolo e ciò che mostra.
struct StoreSlide {
    enum Art {
        /// Una cattura nel telefono (o nell'iPad).
        case screen(String)
        /// I widget sulla schermata Home.
        case homeScreen
        /// L'attività in diretta sulla schermata di blocco.
        case lockScreen
        /// Tre telefoni con temi diversi.
        case themes(center: String, left: String, right: String)
    }

    var id: String
    var chip: String
    var icon: String
    var title: String
    var subtitle: String
    var plus = false
    var tone: StoreTone
    var art: Art
    var decor: [StoreDecor] = []
    var callouts: [StoreCallout] = []

    static let phone: [StoreSlide] = [
        StoreSlide(
            id: "dashboard", chip: "Dashboard", icon: "dashboardFill",
            title: "Il tuo registro,\nfinalmente bello",
            subtitle: "Compiti, verifiche ed eventi dei prossimi giorni a colpo d'occhio",
            tone: .primary, art: .screen("dashboard"),
            decor: [
                StoreDecor(shape: .cookie12Sided, x: 0.0, y: 0.64, size: 0.78, angle: 12, fill: .soft),
                StoreDecor(shape: .sunny, x: 1.0, y: 0.86, size: 0.56, angle: -8, fill: .container),
                StoreDecor(shape: .clover4Leaf, x: 0.9, y: 0.075, size: 0.1, angle: -12, fill: .strong),
            ],
            callouts: [StoreCallout(crop: CGRect(x: 44, y: 520, width: 1232, height: 215), radius: 0.05)]),
        StoreSlide(
            id: "voti", chip: "Voti", icon: "gradesFill",
            title: "Le medie, sempre\nsotto controllo",
            subtitle: "Media generale, periodi e andamento di ogni materia",
            tone: .tertiary, art: .screen("grades"),
            decor: [
                StoreDecor(shape: .flower, x: 1.0, y: 0.56, size: 0.78, angle: 10, fill: .soft),
                StoreDecor(shape: .cookie7Sided, x: 0.0, y: 0.88, size: 0.56, angle: -14, fill: .container),
                StoreDecor(shape: .softBurst, x: 0.1, y: 0.075, size: 0.1, angle: 15, fill: .strong),
            ],
            callouts: [StoreCallout(crop: CGRect(x: 44, y: 1335, width: 1232, height: 205), radius: 0.06)]),
        StoreSlide(
            id: "e-se-prendessi", chip: "E se prendessi…", icon: "wand",
            title: "E se prendessi\nun 9?",
            subtitle: "Prova i voti che non hai ancora preso e scopri come cambiano le medie",
            tone: .vivid, art: .screen("subject"),
            decor: [
                StoreDecor(shape: .clover8Leaf, x: 0.0, y: 0.5, size: 0.78, angle: 8, fill: .soft),
                StoreDecor(shape: .pentagon, x: 1.0, y: 0.82, size: 0.56, angle: 18, fill: .container),
                StoreDecor(shape: .gem, x: 0.9, y: 0.075, size: 0.1, angle: -12, fill: .strong),
            ],
            callouts: [StoreCallout(crop: CGRect(x: 50, y: 1206, width: 1220, height: 440), radius: 0.05)]),
        StoreSlide(
            id: "orario", chip: "Orario", icon: "timetableFill",
            title: "Il tuo orario,\nsempre con te",
            subtitle: "La lezione in corso, intervalli, note e file per ogni ora",
            plus: true, tone: .secondary, art: .screen("timetable"),
            decor: [
                StoreDecor(shape: .verySunny, x: 1.0, y: 0.5, size: 0.78, angle: 6, fill: .soft),
                StoreDecor(shape: .puffy, x: 0.0, y: 0.86, size: 0.56, angle: 0, fill: .container),
                StoreDecor(shape: .cookie4Sided, x: 0.1, y: 0.075, size: 0.1, angle: 15, fill: .strong),
            ],
            callouts: [StoreCallout(crop: CGRect(x: 50, y: 1188, width: 1222, height: 568), width: 0.92, radius: 0.085)]),
        StoreSlide(
            id: "widget", chip: "Widget", icon: "widgets",
            title: "La giornata\nsulla Home",
            subtitle: "Orario, lezione in corso, compiti e medie nei widget",
            plus: true, tone: .deep, art: .homeScreen,
            decor: [
                StoreDecor(shape: .cookie9Sided, x: 0.0, y: 0.6, size: 0.78, angle: 0, fill: .soft),
                StoreDecor(shape: .burst, x: 1.0, y: 0.9, size: 0.56, angle: 14, fill: .soft),
                StoreDecor(shape: .heart, x: 0.9, y: 0.075, size: 0.1, angle: -12, fill: .strong),
            ]),
        StoreSlide(
            id: "attivita-in-diretta", chip: "Attività in diretta", icon: "timer",
            title: "La lezione in corso,\nin diretta",
            subtitle: "Sulla schermata di blocco e nella Dynamic Island",
            plus: true, tone: .primary, art: .lockScreen,
            decor: [
                StoreDecor(shape: .softBoom, x: 1.0, y: 0.5, size: 0.78, angle: 0, fill: .soft),
                StoreDecor(shape: .cookie6Sided, x: 0.0, y: 0.86, size: 0.56, angle: 20, fill: .container),
                StoreDecor(shape: .flower, x: 0.1, y: 0.075, size: 0.1, angle: 15, fill: .strong),
            ]),
        StoreSlide(
            id: "tu", chip: "Tu", icon: "youFill",
            title: "Tutto il registro\nin un'app",
            subtitle: "Bacheca, assenze, note, scrutini, materiale didattico e altro",
            tone: .tertiary, art: .screen("you"),
            decor: [
                StoreDecor(shape: .sunny, x: 0.0, y: 0.56, size: 0.78, angle: 10, fill: .soft),
                StoreDecor(shape: .clover4Leaf, x: 1.0, y: 0.86, size: 0.56, angle: 30, fill: .container),
                StoreDecor(shape: .pill, x: 0.9, y: 0.075, size: 0.1, angle: -12, fill: .strong),
            ],
            callouts: [StoreCallout(crop: CGRect(x: 50, y: 1210, width: 1222, height: 512), width: 0.92, radius: 0.075)]),
        StoreSlide(
            id: "aspetto", chip: "Aspetto", icon: "palette",
            title: "Colori e stile\ncome vuoi tu",
            subtitle: "Material 3 Expressive o Liquid Glass, chiaro o scuro, dieci temi",
            tone: .surface, art: .themes(center: "dashboard", left: "dash-green-dark", right: "dash-blue-glass"),
            decor: [
                StoreDecor(shape: .cookie12Sided, x: 0.5, y: 0.8, size: 1.3, angle: 0, fill: .soft),
            ]),
    ]

    static let pad: [StoreSlide] = [
        StoreSlide(
            id: "dashboard", chip: "Dashboard", icon: "dashboardFill",
            title: "Il tuo registro, finalmente bello",
            subtitle: "Settimana, prossimi giorni e giorno scelto, fianco a fianco",
            tone: .primary, art: .screen("pad-dashboard"),
            decor: [
                StoreDecor(shape: .cookie12Sided, x: 0.02, y: 0.62, size: 0.5, angle: 12, fill: .soft),
                StoreDecor(shape: .sunny, x: 0.99, y: 0.9, size: 0.42, angle: -8, fill: .container),
                StoreDecor(shape: .clover4Leaf, x: 0.945, y: 0.27, size: 0.075, angle: 20, fill: .strong),
            ]),
        StoreSlide(
            id: "orario", chip: "Orario", icon: "timetableFill",
            title: "Tutta la settimana in una vista",
            subtitle: "Lezioni, intervalli e verifiche, da modificare trascinando",
            plus: true, tone: .tertiary, art: .screen("pad-timetable"),
            decor: [
                StoreDecor(shape: .verySunny, x: 0.98, y: 0.6, size: 0.5, angle: 6, fill: .soft),
                StoreDecor(shape: .puffy, x: 0.02, y: 0.9, size: 0.4, angle: 0, fill: .container),
                StoreDecor(shape: .cookie4Sided, x: 0.055, y: 0.27, size: 0.075, angle: 15, fill: .strong),
            ]),
        StoreSlide(
            id: "voti", chip: "Voti", icon: "gradesFill",
            title: "Le medie, sempre sotto controllo",
            subtitle: "Medie, periodi, andamento e voti filtrabili per materia",
            tone: .vivid, art: .screen("pad-grades"),
            decor: [
                StoreDecor(shape: .flower, x: 0.98, y: 0.55, size: 0.52, angle: 10, fill: .soft),
                StoreDecor(shape: .cookie7Sided, x: 0.02, y: 0.88, size: 0.42, angle: -14, fill: .container),
                StoreDecor(shape: .softBurst, x: 0.055, y: 0.27, size: 0.075, angle: 0, fill: .strong),
            ]),
        StoreSlide(
            id: "bacheca", chip: "Bacheca", icon: "megaphone",
            title: "Le comunicazioni, come la posta",
            subtitle: "L'elenco a sinistra, la comunicazione aperta accanto",
            tone: .secondary, art: .screen("pad-noticeboard"),
            decor: [
                StoreDecor(shape: .clover8Leaf, x: 0.02, y: 0.58, size: 0.5, angle: 8, fill: .soft),
                StoreDecor(shape: .pentagon, x: 0.99, y: 0.9, size: 0.4, angle: 18, fill: .container),
                StoreDecor(shape: .gem, x: 0.945, y: 0.27, size: 0.075, angle: -12, fill: .strong),
            ]),
        StoreSlide(
            id: "tu", chip: "Tu", icon: "youFill",
            title: "Tutto il registro in un'app",
            subtitle: "Bacheca, assenze, note, scrutini, materiale didattico e altro",
            tone: .deep, art: .screen("pad-you"),
            decor: [
                StoreDecor(shape: .sunny, x: 0.02, y: 0.6, size: 0.5, angle: 10, fill: .soft),
                StoreDecor(shape: .clover4Leaf, x: 0.99, y: 0.9, size: 0.4, angle: 30, fill: .container),
                StoreDecor(shape: .pill, x: 0.945, y: 0.27, size: 0.075, angle: 0, fill: .strong),
            ]),
    ]
}

/// Una forma di Material dietro il contenuto: centro e misura in frazioni della tela.
struct StoreDecor {
    enum Fill { case soft, container, strong }
    var shape: MaterialShapeName
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var angle: Double
    var fill: Fill
}

/// Un dettaglio della cattura ingrandito sopra il telefono, centrato dove sta nella cattura: ritaglio in
/// pixel della cattura, larghezza in frazioni della tela, raggio in frazioni della larghezza.
struct StoreCallout {
    var crop: CGRect
    var width: CGFloat = 0.93
    var radius: CGFloat
}

/// Colori di una schermata, dai ruoli del tema (Mattone chiaro).
enum StoreTone {
    case primary, secondary, tertiary, surface, vivid, deep

    struct Colors {
        var background: Color
        var ink: Color
        var soft: Color
        var container: Color
        var strong: Color
        var onStrong: Color
        var light: Color
        var onLight: Color
    }

    var colors: Colors {
        switch self {
        case .primary:
            Colors(background: Theme.primaryContainer, ink: Theme.onPrimaryContainer,
                   soft: Theme.primaryContainer.mix(with: Theme.primary, by: 0.2),
                   container: Theme.tertiaryContainer, strong: Theme.primary, onStrong: Theme.onPrimary,
                   light: Theme.surfaceContainerLowest, onLight: Theme.onSurface)
        case .secondary:
            Colors(background: Theme.secondaryContainer, ink: Theme.onSecondaryContainer,
                   soft: Theme.secondaryContainer.mix(with: Theme.secondary, by: 0.22),
                   container: Theme.primaryContainer, strong: Theme.primary, onStrong: Theme.onPrimary,
                   light: Theme.surfaceContainerLowest, onLight: Theme.onSurface)
        case .tertiary:
            Colors(background: Theme.tertiaryContainer, ink: Theme.onTertiaryContainer,
                   soft: Theme.tertiaryContainer.mix(with: Theme.tertiary, by: 0.2),
                   container: Theme.primaryContainer, strong: Theme.tertiary, onStrong: Theme.onTertiary,
                   light: Theme.surfaceContainerLowest, onLight: Theme.onSurface)
        case .surface:
            Colors(background: Theme.surfaceContainer, ink: Theme.onSurface,
                   soft: Theme.surfaceContainerHighest.mix(with: Theme.primary, by: 0.08),
                   container: Theme.primaryContainer, strong: Theme.primary, onStrong: Theme.onPrimary,
                   light: Theme.surfaceContainerLowest, onLight: Theme.onSurface)
        case .vivid:
            Colors(background: Theme.primary, ink: Theme.onPrimary,
                   soft: Theme.primary.mix(with: .white, by: 0.12),
                   container: Theme.inversePrimary, strong: Theme.primaryContainer, onStrong: Theme.onPrimaryContainer,
                   light: Theme.surfaceContainerLowest, onLight: Theme.onSurface)
        case .deep:
            Colors(background: Theme.onPrimaryContainer, ink: Theme.primaryContainer,
                   soft: Theme.onPrimaryContainer.mix(with: Theme.primary, by: 0.4),
                   container: Theme.primary, strong: Theme.inversePrimary, onStrong: Theme.onPrimaryContainer,
                   light: Theme.primaryContainer, onLight: Theme.onPrimaryContainer)
        }
    }

    func fill(_ fill: StoreDecor.Fill) -> Color {
        let c = colors
        return switch fill {
        case .soft: c.soft
        case .container: c.container
        case .strong: c.strong
        }
    }
}

// MARK: - Schermate

/// Schermata per iPhone: etichetta, titolo e sottotitolo in alto, telefono sotto, forme dietro.
struct StorePhoneSlide: View {
    let slide: StoreSlide
    let size: CGSize
    let images: StoreImages

    var body: some View {
        let u = size.width / 440
        let colors = slide.tone.colors
        ZStack(alignment: .top) {
            colors.background
            StoreDecorLayer(decor: slide.decor, tone: slide.tone, size: size)
            StoreHeader(slide: slide, u: u, titleSize: 39, subtitleSize: 18.5, width: size.width)
                .padding(.top, 58 * u)
            art(u: u, colors: colors)
            if case .screen(let name) = slide.art {
                let image = images.image(name)
                let bezel = StoreDevice<EmptyView>.bezel(model: .phone, width: phoneWidth(u))
                let screenHeight = (phoneWidth(u) - 2 * bezel) * StoreDevice<EmptyView>.aspect(.phone)
                ForEach(slide.callouts.indices, id: \.self) { index in
                    let callout = slide.callouts[index]
                    let y = phoneTop(u) + bezel + callout.crop.midY / max(image.size.height, 1) * screenHeight
                    StoreCalloutView(callout: callout, image: image, canvas: size, shadow: colors.ink)
                        .position(x: size.width / 2, y: y)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func phoneTop(_ u: CGFloat) -> CGFloat { 290 * u }
    private func phoneWidth(_ u: CGFloat) -> CGFloat { 304 * u }

    @ViewBuilder private func art(u: CGFloat, colors: StoreTone.Colors) -> some View {
        let top = phoneTop(u)
        let width = phoneWidth(u)
        switch slide.art {
        case .screen(let name):
            StoreDevice(model: .phone, width: width, shadow: colors.ink) {
                Image(uiImage: images.image(name)).resizable().interpolation(.high)
            }
            .position(x: size.width / 2, y: top + StoreDevice<EmptyView>.height(model: .phone, width: width) / 2)
        case .homeScreen:
            StoreDevice(model: .phone, width: width, shadow: .black) {
                StoreNativeScreen { StoreHomeScreen() }
            }
            .position(x: size.width / 2, y: top + StoreDevice<EmptyView>.height(model: .phone, width: width) / 2)
        case .lockScreen:
            let bezel = StoreDevice<EmptyView>.bezel(model: .phone, width: width)
            let screen = CGSize(width: width - 2 * bezel, height: (width - 2 * bezel) * StoreDevice<EmptyView>.aspect(.phone))
            let center = CGPoint(x: size.width / 2, y: top + StoreDevice<EmptyView>.height(model: .phone, width: width) / 2)
            StoreDevice(model: .phone, width: width, shadow: colors.ink) {
                StoreNativeScreen { StoreLockScreen() }
            }
            .position(center)
            // Isola e attività ingrandite sopra l'originale, fuori dallo schermo.
            StoreNativeScreen { StoreLockScreen.Callouts(shadow: colors.ink) }
                .frame(width: screen.width, height: screen.height)
                .position(center)
        case .themes(let center, let left, let right):
            let side = 236 * u
            let main = 268 * u
            let sideTop = 372 * u
            let mainTop = 330 * u
            StoreAccentRow(u: u)
                .position(x: size.width / 2, y: 292 * u)
            StoreDevice(model: .phone, width: side, shadow: colors.ink) {
                Image(uiImage: images.image(left)).resizable().interpolation(.high)
            }
            .rotationEffect(.degrees(-9))
            .position(x: size.width * 0.27, y: sideTop + StoreDevice<EmptyView>.height(model: .phone, width: side) / 2)
            StoreDevice(model: .phone, width: side, shadow: colors.ink) {
                Image(uiImage: images.image(right)).resizable().interpolation(.high)
            }
            .rotationEffect(.degrees(9))
            .position(x: size.width * 0.73, y: sideTop + StoreDevice<EmptyView>.height(model: .phone, width: side) / 2)
            StoreDevice(model: .phone, width: main, shadow: colors.ink) {
                Image(uiImage: images.image(center)).resizable().interpolation(.high)
            }
            .position(x: size.width / 2, y: mainTop + StoreDevice<EmptyView>.height(model: .phone, width: main) / 2)
        }
    }
}

/// Schermata per iPad: come quella per iPhone, con l'iPad in verticale.
struct StorePadSlide: View {
    let slide: StoreSlide
    let size: CGSize
    let images: StoreImages

    var body: some View {
        let u = size.width / 1032
        let colors = slide.tone.colors
        ZStack(alignment: .top) {
            colors.background
            StoreDecorLayer(decor: slide.decor, tone: slide.tone, size: size)
            StoreHeader(slide: slide, u: u * 1.45, titleSize: 34, subtitleSize: 17, width: size.width)
                .padding(.top, 64 * u)
            if case .screen(let name) = slide.art {
                let width = 800 * u
                StoreDevice(model: .pad, width: width, shadow: colors.ink) {
                    Image(uiImage: images.image(name)).resizable().interpolation(.high)
                }
                .position(x: size.width / 2, y: 292 * u + StoreDevice<EmptyView>.height(model: .pad, width: width) / 2)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// Etichetta (con BCW+ per le funzioni a pagamento), titolo e sottotitolo, centrati.
struct StoreHeader: View {
    let slide: StoreSlide
    let u: CGFloat
    let titleSize: CGFloat
    let subtitleSize: CGFloat
    let width: CGFloat

    var body: some View {
        let colors = slide.tone.colors
        VStack(spacing: 0) {
            HStack(spacing: 8 * u) {
                HStack(spacing: 7 * u) {
                    Icon(slide.icon, size: 19 * u)
                    Text(slide.chip)
                        .font(.m3(16.5 * u, weight: 650))
                }
                .padding(.leading, 13 * u)
                .padding(.trailing, 16 * u)
                .frame(height: 36 * u)
                .foregroundStyle(colors.onStrong)
                .background(colors.strong, in: .capsule)
                if slide.plus {
                    StorePlusChip(u: u, colors: colors)
                }
            }
            Text(slide.title)
                .font(.m3(titleSize * u, weight: 780, rounded: true))
                .tracking(-0.016 * titleSize * u)
                .multilineTextAlignment(.center)
                .foregroundStyle(colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20 * u)
                .padding(.horizontal, 22 * u)
            Text(slide.subtitle)
                .font(.m3(subtitleSize * u, weight: 450))
                .multilineTextAlignment(.center)
                .foregroundStyle(colors.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12 * u)
                .padding(.horizontal, 44 * u)
        }
        .frame(width: width)
    }
}

/// "BCW+" con il "+" nella forma, come il marchio dell'acquisto.
struct StorePlusChip: View {
    let u: CGFloat
    let colors: StoreTone.Colors

    var body: some View {
        HStack(spacing: 6 * u) {
            Text("BCW")
                .font(.m3(16.5 * u, weight: 800, rounded: true))
                .foregroundStyle(colors.onLight)
            Shaped(shape: .cookie9Sided, fill: Theme.primary, size: 23 * u) {
                Icon("plus", size: 16 * u)
                    .foregroundStyle(Theme.onPrimary)
            }
        }
        .padding(.leading, 14 * u)
        .padding(.trailing, 7 * u)
        .frame(height: 36 * u)
        .background(colors.light, in: .capsule)
    }
}

/// Le forme dietro il contenuto.
struct StoreDecorLayer: View {
    let decor: [StoreDecor]
    let tone: StoreTone
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(decor.indices, id: \.self) { index in
                let item = decor[index]
                MaterialShape(item.shape)
                    .fill(tone.fill(item.fill))
                    .frame(width: item.size * size.width, height: item.size * size.width)
                    .rotationEffect(.degrees(item.angle))
                    .position(x: item.x * size.width, y: item.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Un dettaglio della cattura ingrandito, con gli angoli della card e un'ombra.
struct StoreCalloutView: View {
    let callout: StoreCallout
    let image: UIImage
    let canvas: CGSize
    let shadow: Color

    var body: some View {
        let width = callout.width * canvas.width
        let scale = width / callout.crop.width
        let height = callout.crop.height * scale
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: image.size.width * scale, height: image.size.height * scale)
            .offset(x: -callout.crop.minX * scale, y: -callout.crop.minY * scale)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: callout.radius * width, style: .continuous))
            .shadow(color: shadow.opacity(0.3), radius: 0.04 * canvas.width, y: 0.02 * canvas.width)
    }
}

/// I dieci colori d'accento proposti, ognuno in una forma diversa.
struct StoreAccentRow: View {
    let u: CGFloat
    private let shapes: [MaterialShapeName] = [
        .cookie9Sided, .clover4Leaf, .sunny, .pentagon, .flower, .cookie6Sided, .gem, .puffy, .softBurst, .heart,
    ]

    static func color(_ hex: String) -> Color {
        Color(hex: Int(hex.dropFirst(), radix: 16) ?? 0x808080)
    }

    var body: some View {
        HStack(spacing: 7 * u) {
            ForEach(accentPresets.indices, id: \.self) { index in
                MaterialShape(shapes[index % shapes.count])
                    .fill(Self.color(accentPresets[index].hex))
                    .frame(width: 28 * u, height: 28 * u)
            }
        }
    }
}

// MARK: - Dispositivi

/// Un iPhone o un iPad: cornice scura con il bordo chiaro, schermo con gli angoli continui, Dynamic
/// Island e tasti laterali (iPhone), ombra morbida.
struct StoreDevice<Screen: View>: View {
    enum Model { case phone, pad }
    let model: Model
    let width: CGFloat
    let shadow: Color
    @ViewBuilder let screen: () -> Screen

    static func bezel(model: Model, width: CGFloat) -> CGFloat { width * (model == .phone ? 0.031 : 0.02) }
    static func aspect(_ model: Model) -> CGFloat { model == .phone ? 2868.0 / 1320 : 2752.0 / 2064 }
    static func height(model: Model, width: CGFloat) -> CGFloat {
        let bezel = bezel(model: model, width: width)
        return (width - 2 * bezel) * aspect(model) + 2 * bezel
    }

    var body: some View {
        let bezel = Self.bezel(model: model, width: width)
        let screenWidth = width - 2 * bezel
        let screenHeight = screenWidth * Self.aspect(model)
        let radius = screenWidth * (model == .phone ? 0.141 : 0.03)
        let outer = RoundedRectangle(cornerRadius: radius + bezel, style: .continuous)
        ZStack {
            outer.fill(Color(red: 0.07, green: 0.065, blue: 0.08))
            outer.strokeBorder(
                LinearGradient(colors: [Color(white: 0.62), Color(white: 0.26), Color(white: 0.5), Color(white: 0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: bezel * 0.28)
            screen()
                .frame(width: screenWidth, height: screenHeight)
                .clipShape(.rect(cornerRadius: radius, style: .continuous))
            if model == .phone {
                let unit = screenWidth / 440
                Capsule()
                    .fill(Color.black)
                    .frame(width: 125 * unit, height: 37 * unit)
                    .position(x: width / 2, y: bezel + (11 + 18.5) * unit)
            }
        }
        .frame(width: width, height: screenHeight + 2 * bezel)
        .background { if model == .phone { buttons(bezel: bezel, height: screenHeight + 2 * bezel) } }
        .shadow(color: shadow.opacity(0.3), radius: width * 0.07, y: width * 0.04)
    }

    /// Tasto Azione, volume, tasto laterale e Controllo fotocamera, che sporgono appena.
    private func buttons(bezel: CGFloat, height: CGFloat) -> some View {
        let thickness = bezel * 0.5
        func key(_ x: CGFloat, _ y: CGFloat, _ length: CGFloat) -> some View {
            RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
                .fill(Color(white: 0.3))
                .frame(width: thickness, height: length * height)
                .position(x: x, y: (y + length / 2) * height)
        }
        return ZStack {
            key(0, 0.165, 0.04)
            key(0, 0.235, 0.07)
            key(0, 0.325, 0.07)
            key(width, 0.255, 0.11)
            key(width, 0.53, 0.07)
        }
        .frame(width: width, height: height)
    }
}

/// Contenuto disegnato a misura di schermo (440 × 956 punti, iPhone 6,9") e scalato nello schermo.
struct StoreNativeScreen<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 440
            content()
                .frame(width: 440, height: 956)
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}

// MARK: - Home e schermata di blocco

/// Sfondo di Home e schermata di blocco: il colore di BCW, vivace, con grandi forme.
struct StoreWallpaper: View {
    var body: some View {
        let brand = Theme.brand
        ZStack {
            LinearGradient(colors: [brand.mix(with: .black, by: 0.08), brand.mix(with: Theme.tertiaryContainer, by: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            MaterialShape(.flower)
                .fill(brand.mix(with: .white, by: 0.18))
                .frame(width: 520, height: 520)
                .rotationEffect(.degrees(12))
                .position(x: 420, y: 230)
            MaterialShape(.cookie9Sided)
                .fill(brand.mix(with: .black, by: 0.16))
                .frame(width: 560, height: 560)
                .rotationEffect(.degrees(-8))
                .position(x: 30, y: 760)
            MaterialShape(.sunny)
                .fill(brand.mix(with: Theme.tertiaryContainer, by: 0.6))
                .frame(width: 260, height: 260)
                .position(x: 400, y: 900)
        }
        .frame(width: 440, height: 956)
        .clipped()
    }
}

/// Barra di stato finta, come nelle catture (09:41, campo, Wi-Fi, batteria).
struct StoreStatusBar: View {
    var body: some View {
        HStack {
            Text(StoreAssets.timeText)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 140)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                    .font(.system(size: 22, weight: .regular))
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 140)
        }
        .foregroundStyle(.white)
        .frame(height: 37)
        .padding(.top, 11)
    }
}

/// Dati di esempio dei widget all'ora di `StoreAssets.now`, nei colori del tema.
enum StoreWidgets {
    static var snapshot: WidgetSnapshot {
        var snapshot = WidgetSnapshot.sample(now: StoreAssets.now)
        snapshot.theme = WidgetExporter.themeSnapshot()
        // Due ore in più oggi, così l'orario grande è pieno come una giornata vera.
        let key = BCWShared.dayKey(StoreAssets.now)
        if let index = snapshot.days.firstIndex(where: { $0.key == key }) {
            snapshot.days[index].events += [
                WidgetSnapshot.Event(id: "store-5", title: "Filosofia", room: "2B", teacher: "Conti Elena",
                                     start: 13 * 60 + 10, end: 14 * 60 + 10,
                                     tint: WidgetSnapshot.Tint(light: 0x854A78, dark: 0xF8B0E4)),
                WidgetSnapshot.Event(id: "store-6", title: "Fisica", room: "Lab 2", teacher: "Neri Paola",
                                     start: 14 * 60 + 10, end: 15 * 60 + 10,
                                     tint: WidgetSnapshot.Tint(light: 0x306388, dark: 0x9CCCF6)),
            ]
        }
        return snapshot
    }

    static func widget(_ kind: BCWWidgetKind, _ family: WidgetFamily, snapshot: WidgetSnapshot) -> some View {
        let palette = WidgetPalette(theme: snapshot.theme, colorScheme: .light, look: .fullColor)
        let size: CGSize = switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        default: CGSize(width: 364, height: 382)
        }
        return kind.content(snapshot: snapshot, now: StoreAssets.now, family: family, palette: palette)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(kind.background(palette))
            .clipShape(.rect(cornerRadius: 26, style: .continuous))
            .environment(\.colorScheme, .light)
    }
}

/// La Home con i widget di BCW.
struct StoreHomeScreen: View {
    var body: some View {
        let snapshot = StoreWidgets.snapshot
        ZStack(alignment: .top) {
            StoreWallpaper()
            VStack(spacing: 26) {
                StoreWidgets.widget(.timetable, .systemLarge, snapshot: snapshot)
                HStack(spacing: 24) {
                    StoreWidgets.widget(.now, .systemSmall, snapshot: snapshot)
                    StoreWidgets.widget(.average, .systemSmall, snapshot: snapshot)
                }
                StoreWidgets.widget(.agenda, .systemMedium, snapshot: snapshot)
            }
            .padding(.top, 76)
            StoreStatusBar()
        }
        .frame(width: 440, height: 956)
    }
}

/// La schermata di blocco con l'attività in diretta.
struct StoreLockScreen: View {
    static var theme: TimetableActivityTheme { TimetableActivityTheme(WidgetExporter.themeSnapshot()) }
    static var state: TimetableActivityState? {
        let start = StoreAssets.now.addingTimeInterval(-20 * 60)
        return TimetableActivityPlan(day: start, items: TimetableActivityPlan.sampleItems(start: start, unit: 1800))?
            .content(at: StoreAssets.now, theme: theme, compactTime: false)?.state
    }
    static let cardTop: CGFloat = 540

    /// L'attività ingrandita sopra quella sulla schermata e la Dynamic Island compatta, ingrandita sopra
    /// la fotocamera: stesse coordinate dello schermo (440 × 956), senza ritaglio.
    struct Callouts: View {
        let shadow: Color

        var body: some View {
            let theme = StoreLockScreen.theme
            if let state = StoreLockScreen.state {
                let island = TimetableActivityIsland(state: state, isStale: false)
                ZStack(alignment: .top) {
                    Color.clear
                    HStack(spacing: 0) {
                        island.compactLeading
                        Color.clear.frame(width: 126)
                        island.compactTrailing
                    }
                    .padding(.leading, TimetableActivityIsland.compactMargin)
                    .padding(.trailing, TimetableActivityIsland.compactTextMargin)
                    .frame(height: TimetableActivityIsland.compactHeight)
                    .background(Color.black, in: .capsule)
                    .environment(\.colorScheme, .dark)
                    .scaleEffect(1.3)
                    .shadow(color: shadow.opacity(0.35), radius: 18, y: 10)
                    .padding(.top, 11)
                    TimetableActivityLockView(state: state, isStale: false)
                        .background(ActivityPalette(theme: theme, dark: false).background)
                        .clipShape(.rect(cornerRadius: 26, style: .continuous))
                        .frame(width: 410)
                        .environment(\.colorScheme, .light)
                        .scaleEffect(1.32)
                        .shadow(color: shadow.opacity(0.3), radius: 22, y: 12)
                        .padding(.top, StoreLockScreen.cardTop)
                }
                .frame(width: 440, height: 956)
            }
        }
    }

    var body: some View {
        let theme = Self.theme
        let state = Self.state
        ZStack(alignment: .top) {
            StoreWallpaper()
            VStack(spacing: 0) {
                Text(StoreAssets.dateText)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(StoreAssets.timeText)
                    .font(.system(size: 104, weight: .semibold, design: .rounded))
                    .tracking(-2)
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.top, 74)
            if let state {
                TimetableActivityLockView(state: state, isStale: false)
                    .background(ActivityPalette(theme: theme, dark: false).background)
                    .clipShape(.rect(cornerRadius: 26, style: .continuous))
                    .frame(width: 410)
                    .environment(\.colorScheme, .light)
                    .padding(.top, Self.cardTop)
            }
            HStack {
                lockButton("flashlight.off.fill")
                Spacer()
                lockButton("camera.fill")
            }
            .padding(.horizontal, 46)
            .padding(.top, 846)
            Capsule()
                .fill(.white.opacity(0.9))
                .frame(width: 146, height: 5)
                .padding(.top, 940)
        }
        .frame(width: 440, height: 956)
    }

    private func lockButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(.black.opacity(0.28), in: .circle)
    }
}

// MARK: - Evento in-app

/// Immagine dell'evento in-app (scheda 16:9 e pagina dei dettagli 9:16): forme, telefono con l'orario e
/// widget, marchio di BCW+. Niente testo in basso: lì l'App Store scrive nome e descrizione dell'evento.
struct StoreEventArt: View {
    let size: CGSize
    let images: StoreImages

    var body: some View {
        let wide = size.width > size.height
        let u = min(size.width, size.height) / 540
        let colors = StoreTone.tertiary.colors
        let snapshot = StoreWidgets.snapshot
        let phone: CGFloat = wide ? 210 : 280
        ZStack {
            colors.background
            MaterialShape(.cookie12Sided)
                .fill(colors.soft)
                .frame(width: 560 * u, height: 560 * u)
                .rotationEffect(.degrees(10))
                .position(x: size.width * (wide ? 0.62 : 0.5), y: size.height * (wide ? 0.5 : 0.42))
            MaterialShape(.sunny)
                .fill(colors.container)
                .frame(width: 210 * u, height: 210 * u)
                .position(x: size.width * (wide ? 0.06 : 0.04), y: size.height * (wide ? 0.95 : 0.93))
            MaterialShape(.clover4Leaf)
                .fill(colors.strong)
                .frame(width: 62 * u, height: 62 * u)
                .rotationEffect(.degrees(18))
                .position(x: size.width * (wide ? 0.93 : 0.88), y: size.height * (wide ? 0.14 : 0.06))
            PlusWordmark(size: 62 * u, color: colors.ink)
                .position(x: wide ? size.width * 0.24 : size.width / 2, y: wide ? size.height * 0.42 : size.height * 0.085)
            StoreDevice(model: .phone, width: phone * u, shadow: colors.ink) {
                Image(uiImage: images.image("timetable")).resizable().interpolation(.high)
            }
            .rotationEffect(.degrees(wide ? -6 : 0))
            .position(x: size.width * (wide ? 0.6 : 0.5),
                      y: wide ? size.height * 0.64 : size.height * 0.16 + StoreDevice<EmptyView>.height(model: .phone, width: phone * u) / 2)
            StoreWidgets.widget(.now, .systemSmall, snapshot: snapshot)
                .scaleEffect(0.78 * u)
                .shadow(color: colors.ink.opacity(0.25), radius: 15 * u, y: 8 * u)
                .rotationEffect(.degrees(7))
                .position(x: size.width * (wide ? 0.84 : 0.82), y: size.height * (wide ? 0.42 : 0.3))
            StoreWidgets.widget(.average, .systemSmall, snapshot: snapshot)
                .scaleEffect(0.66 * u)
                .shadow(color: colors.ink.opacity(0.25), radius: 15 * u, y: 8 * u)
                .rotationEffect(.degrees(-8))
                .position(x: size.width * (wide ? 0.38 : 0.17), y: size.height * (wide ? 0.74 : 0.66))
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
#endif
