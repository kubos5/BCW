#if os(macOS) && DEBUG
import AppKit
import SwiftUI

/// Strumento di sviluppo: con `-BCWSnapshot YES` l'app visita le sezioni e salva un'immagine
/// della finestra per ciascuna nella cartella temporanea del contenitore.
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
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BCWSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        print("BCWSnapshots:", folder.path)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            for size in sizes {
                mainWindow?.setContentSize(size)
                for section in sections {
                    nav.section = section
                    try? await Task.sleep(for: .seconds(3))
                    if let window = mainWindow {
                        capture(window, to: folder.appendingPathComponent("\(section.rawValue)-\(Int(size.width)).png"))
                    }
                }
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
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BCWSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if let window = mainWindow { capture(window, to: folder.appendingPathComponent("login.png")) }
            NSApp.terminate(nil)
        }
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
