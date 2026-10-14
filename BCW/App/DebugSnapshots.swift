#if os(macOS) && DEBUG
import AppKit
import SwiftUI

/// Strumento di sviluppo: con `-BCWSnapshot YES` l'app visita le sezioni e salva un'immagine
/// della finestra per ciascuna nella cartella temporanea del contenitore.
/// Opzioni: `-BCWHover YES` porta anche il puntatore sulla barra della finestra e salva
/// `<sezione>-<larghezza>-hover.png`; `-BCWSearch testo` apre la ricerca e salva `search.png`, poi la chiude e salva `search-closed.png`
/// (e `search-empty.png`/`search-closed-empty.png` per il campo selezionato e lasciato vuoto);
/// `-BCWClickSearch YES` fa clic tre volte sul campo (o sulla lente) e salva `click-N.png`.
enum DebugSnapshots {
    static func runIfRequested(nav: MacNavigation, openSettings: OpenSettingsAction) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "BCWSnapshot") else { return }
        let sections = defaults.string(forKey: "BCWSections")?.split(separator: ",")
            .compactMap { MacSection(rawValue: String($0)) } ?? MacSection.allCases
        let sizes: [CGSize] = (defaults.string(forKey: "BCWSizes") ?? "1280x840").split(separator: ",").compactMap {
            let parts = $0.split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        }
        let folder = snapshotFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        print("BCWSnapshots:", folder.path)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            for (step, size) in sizes.enumerated() {
                mainWindow?.setContentSize(size)
                for section in sections {
                    nav.show(section)
                    try? await Task.sleep(for: .seconds(3))
                    guard let window = mainWindow else { continue }
                    // `-BCWScroll N`: scorre di N punti tutti gli scorrimenti verticali della pagina
                    // (con `-BCWWheel YES` come una rotella vera, con eventi della finestra).
                    let scroll = defaults.double(forKey: "BCWScroll")
                    if scroll > 0, let content = window.contentView {
                        if defaults.bool(forKey: "BCWWheel") {
                            // Come una rotella vera: passa dagli eventi della finestra.
                            for _ in 0..<Int(scroll / 20) {
                                wheel(window, at: NSPoint(x: content.bounds.width * 0.7, y: content.bounds.height * 0.5), by: -20)
                                try? await Task.sleep(for: .milliseconds(16))
                            }
                        } else {
                            scrollAll(in: content, by: scroll)
                        }
                        try? await Task.sleep(for: .seconds(1))
                    }
                    // Il numero del passo distingue le stesse dimensioni ripetute (prove di ridimensionamento).
                    let name = "\(section.rawValue)-\(Int(size.width))" + (sizes.count > 2 ? "-\(step)" : "")
                    capture(window, to: folder.appendingPathComponent("\(name).png"))
                    // Un foglio aperto (es. `-BCWTimetableSheet`) è una finestra a parte.
                    if let sheet = window.attachedSheet {
                        capture(sheet, to: folder.appendingPathComponent("\(name)-sheet.png"))
                    }
                    if defaults.bool(forKey: "BCWHover") {
                        for (index, fraction) in [0.3, 0.75].enumerated() {
                            hover(over: window, fraction: fraction)
                            try? await Task.sleep(for: .seconds(1.5))
                            capture(window, to: folder.appendingPathComponent("\(name)-hover\(index + 1).png"))
                        }
                        restorePointer()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }
            let toggles = defaults.integer(forKey: "BCWResizeToggle")
            if toggles > 0, let window = mainWindow {
                // Solo il passaggio tra due colonne e una, ripetuto (per `sample`).
                print("BCWResizeToggle pronto")
                try? await Task.sleep(for: .seconds(3))
                for index in 0..<toggles {
                    window.setContentSize(NSSize(width: index % 2 == 0 ? 1050 : 1150, height: 840))
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    await Task.yield()
                }
                print("BCWResizeToggle fine")
            }
            if defaults.bool(forKey: "BCWResizeBench"), let window = mainWindow {
                // Ridimensionamento come trascinando il bordo: 10 punti per passo, avanti e indietro
                // attraverso il passaggio da due colonne a una. Stampa il tempo medio per passo e il peggiore.
                for section in sections {
                    nav.show(section)
                    try? await Task.sleep(for: .seconds(2))
                    var times: [Double] = []
                    for round in 0..<3 {
                        let widths = Array(stride(from: 1300, through: 900, by: -10)) + Array(stride(from: 900, through: 1300, by: 10))
                        for width in widths {
                            let start = CACurrentMediaTime()
                            window.setContentSize(NSSize(width: CGFloat(width), height: 840))
                            window.contentView?.layoutSubtreeIfNeeded()
                            window.displayIfNeeded()
                            if round > 0 { times.append((CACurrentMediaTime() - start) * 1000) }
                        }
                    }
                    let average = times.reduce(0, +) / Double(times.count)
                    let slow = times.filter { $0 > 33 }.map { String(format: "%.0f", $0) }.joined(separator: " ")
                    print(String(format: "BCWResize %@: media %.2f ms, peggiore %.2f ms, lenti: %@", section.rawValue, average, times.max() ?? 0, slow))
                }
            }
            if defaults.bool(forKey: "BCWClickSearch") {
                // Clic sul campo di ricerca (o sulla lente, se è ridotto a icona), poi chiusura.
                let start = nav.section
                for step in 0..<3 {
                    if let window = mainWindow { click(searchFieldIn: window) }
                    try? await Task.sleep(for: .seconds(2))
                    if let window = mainWindow { capture(window, to: folder.appendingPathComponent("click-\(step).png")) }
                    // Si esce come con Esc, poi scegliendo la stessa sezione, poi tornando a quella
                    // di partenza da un'altra (Voti, o Tu se si partiva da Voti).
                    switch step {
                    case 0: mainWindow?.makeFirstResponder(nil)
                    case 1: nav.show(start)
                    default:
                        nav.show(start == .grades ? .you : .grades)
                        try? await Task.sleep(for: .seconds(1.5))
                        nav.show(start)
                    }
                    try? await Task.sleep(for: .seconds(2))
                    if let window = mainWindow { capture(window, to: folder.appendingPathComponent("click-\(step)-closed.png")) }
                }
            }
            if let text = defaults.string(forKey: "BCWSearch") {
                // Campo selezionato e poi abbandonato vuoto (come con Esc), poi una ricerca vera
                // chiusa allo stesso modo: la barra deve tornare com'era.
                nav.searchFocusRequest += 1
                try? await Task.sleep(for: .seconds(2))
                if let window = mainWindow { capture(window, to: folder.appendingPathComponent("search-empty.png")) }
                mainWindow?.makeFirstResponder(nil)
                try? await Task.sleep(for: .seconds(2))
                if let window = mainWindow { capture(window, to: folder.appendingPathComponent("search-closed-empty.png")) }
                nav.searchFocusRequest += 1
                try? await Task.sleep(for: .seconds(1))
                nav.searchQuery = text
                try? await Task.sleep(for: .seconds(2))
                if let window = mainWindow { capture(window, to: folder.appendingPathComponent("search.png")) }
                if defaults.bool(forKey: "BCWSearchClickAway"), let window = mainWindow, let content = window.contentView {
                    // Clic su un risultato e poi su un'area vuota a destra: solo il secondo deve
                    // togliere la selezione al campo. La finestra deve essere attiva, altrimenti il
                    // primo clic serve solo ad attivarla.
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    try? await Task.sleep(for: .seconds(1))
                    for (label, point) in [("risultato", NSPoint(x: content.bounds.width * 0.45, y: content.bounds.height - 150)),
                                           ("vuoto", NSPoint(x: content.bounds.width * 0.9, y: content.bounds.height * 0.5))] {
                        click(window, at: point)
                        try? await Task.sleep(for: .seconds(1))
                        print("BCWSearchClick \(label): primo risponditore \(String(describing: window.firstResponder.map { type(of: $0) })) ricerca aperta \(nav.isSearching)")
                    }
                    capture(window, to: folder.appendingPathComponent("search-clicked.png"))
                }
                nav.searchQuery = ""
                mainWindow?.makeFirstResponder(nil)
                try? await Task.sleep(for: .seconds(2))
                if let window = mainWindow { capture(window, to: folder.appendingPathComponent("search-closed.png")) }
            }
            if defaults.bool(forKey: "BCWSettings") {
                openSettings()
                try? await Task.sleep(for: .seconds(2))
                let main = mainWindow
                if let settings = NSApp.windows.first(where: { $0.isVisible && $0 !== main && !($0 is NSPanel) }) {
                    capture(settings, to: folder.appendingPathComponent("settings.png"))
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// Per la schermata di accesso, dove `MacRootView` non c'è.
    static func captureLogin() {
        guard UserDefaults.standard.bool(forKey: "BCWSnapshot") else { return }
        let folder = snapshotFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if let window = mainWindow { capture(window, to: folder.appendingPathComponent("login.png")) }
            NSApp.terminate(nil)
        }
    }

    /// Cartella delle immagini: `-BCWSnapshotDir` (build senza sandbox) o la cartella temporanea.
    private static var snapshotFolder: URL {
        if let path = UserDefaults.standard.string(forKey: "BCWSnapshotDir") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("BCWSnapshots", isDirectory: true)
    }

    private static func click(_ window: NSWindow, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
        }
    }

    private static func wheel(_ window: NSWindow, at point: NSPoint, by delta: Int32) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
        let screenPoint = window.convertPoint(toScreen: point)
        let height = NSScreen.screens.first?.frame.height ?? 0
        cg.location = CGPoint(x: screenPoint.x, y: height - screenPoint.y)
        if let event = NSEvent(cgEvent: cg) { window.sendEvent(event) }
    }

    private static func scrollAll(in view: NSView, by amount: CGFloat) {
        if let scrollView = view as? NSScrollView, let document = scrollView.documentView,
           document.frame.height > scrollView.contentView.bounds.height {
            let top = -scrollView.contentInsets.top
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: (document.isFlipped ? top + amount : document.frame.height - scrollView.contentView.bounds.height - amount)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        for subview in view.subviews { scrollAll(in: subview, by: amount) }
    }

    private static var savedPointer: CGPoint?

    /// Porta il puntatore sulla barra della finestra, a una frazione della larghezza.
    private static func hover(over window: NSWindow, fraction: CGFloat) {
        guard let screen = NSScreen.screens.first else { return }
        if savedPointer == nil {
            let location = NSEvent.mouseLocation
            savedPointer = CGPoint(x: location.x, y: screen.frame.maxY - location.y)
        }
        let frame = window.frame
        let point = CGPoint(x: frame.minX + frame.width * fraction, y: screen.frame.maxY - (frame.maxY - 26))
        CGWarpMouseCursorPosition(point)
        // Il solo spostamento non genera eventi: se ne invia uno perché la finestra se ne accorga.
        let local = window.convertPoint(fromScreen: NSPoint(x: point.x, y: screen.frame.maxY - point.y))
        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: local, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 0, pressure: 0) {
            window.sendEvent(event)
        }
    }

    private static func restorePointer() {
        if let savedPointer { CGWarpMouseCursorPosition(savedPointer) }
        savedPointer = nil
    }

    /// Clic simulato al centro del campo di ricerca della barra.
    private static func click(searchFieldIn window: NSWindow) {
        guard let search = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first,
              search.searchField.window != nil else { return }
        let field = search.searchField
        let center = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: center, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
        }
    }

    /// Elementi della barra della finestra con la loro posizione: per controllare ordine e
    /// allineamento anche quando la finestra non si può catturare (es. schermo bloccato).
    private static func logToolbar(of window: NSWindow, label: String) {
        guard let toolbar = window.toolbar else { return }
        print("BCWToolbar \(label): finestra larga \(Int(window.frame.width))")
        for item in toolbar.items {
            let view = (item as? NSSearchToolbarItem)?.searchField ?? (item.value(forKey: "view") as? NSView)
            var position = "fuori dalla barra"
            if let view, view.window != nil, !view.isHiddenOrHasHiddenAncestor {
                let frame = view.convert(view.bounds, to: nil)
                position = "x \(Int(frame.minX))–\(Int(frame.maxX))"
            }
            let name = "\(item.itemIdentifier.rawValue) [\(item.label)] \(type(of: item))"
            print("  \(name): \(position)")
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil }
    }

    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// `CGWindowListCreateImage` non è più esposta dall'SDK, ma per le finestre della
    /// propria app funziona senza il permesso di registrazione dello schermo.
    private static func capture(_ window: NSWindow, to url: URL) {
        logToolbar(of: window, label: url.deletingPathExtension().lastPathComponent)
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return }
        let function = unsafeBitCast(symbol, to: WindowImageFunction.self)
        // kCGWindowListOptionIncludingWindow = 8, kCGWindowImageBoundsIgnoreFraming = 1
        guard let image = function(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
