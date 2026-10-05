#if os(macOS) && DEBUG
import AppKit
import SwiftUI

/// Strumento di sviluppo: con `-BCWSnapshot YES` l'app visita le sezioni e salva un'immagine
/// della finestra per ciascuna nella cartella temporanea del contenitore.
/// Opzioni: `-BCWHover YES` porta anche il puntatore sulla barra della finestra e salva
/// `<sezione>-<larghezza>-hover.png`; `-BCWSearch testo` apre la ricerca e salva `search.png`.
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
                    // Il numero del passo distingue le stesse dimensioni ripetute (prove di ridimensionamento).
                    let name = "\(section.rawValue)-\(Int(size.width))" + (sizes.count > 2 ? "-\(step)" : "")
                    capture(window, to: folder.appendingPathComponent("\(name).png"))
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
            if let text = defaults.string(forKey: "BCWSearch") {
                nav.searchFocusRequest += 1
                try? await Task.sleep(for: .seconds(2))
                if let window = mainWindow { capture(window, to: folder.appendingPathComponent("search-empty.png")) }
                nav.searchQuery = text
                try? await Task.sleep(for: .seconds(2))
                if let window = mainWindow { capture(window, to: folder.appendingPathComponent("search.png")) }
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

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil }
    }

    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// `CGWindowListCreateImage` non è più esposta dall'SDK, ma per le finestre della
    /// propria app funziona senza il permesso di registrazione dello schermo.
    private static func capture(_ window: NSWindow, to url: URL) {
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
