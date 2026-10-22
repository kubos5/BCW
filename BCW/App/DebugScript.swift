#if DEBUG
import SwiftUI
import UIKit

/// Prove sul simulatore senza tocchi (solo sviluppo): `-BCWScript "3:glass=NO;6:tab=timetable"`
/// esegue i comandi ai secondi indicati dall'avvio e li scrive nella console (`BCW-SCRIPT`).
/// Comandi: `glass=YES|NO`, `tab=dashboard|timetable|grades|you|search|<sezione di -BCWOpenPage>`,
/// `class=compact|regular|auto` (classe della finestra), `orientation=landscape|portrait`,
/// `sidebar=open|close` (barra laterale di sistema), `action=<nome>` (azioni delle pagine:
/// `settings`, `rail`, `search`; Dashboard e Orario: `next`, `prev`; Dashboard: `scroll`, `top`;
/// Orario: `nextweek`, `editing`, `mode`).
@Observable
final class DebugScript {
    static let shared = DebugScript()

    /// Scheda da aprire (`MainTabView` la consuma).
    var tab: String?
    /// Classe della finestra forzata (nil: quella misurata).
    var windowClass: WindowClass?
    /// Azione per le pagine, con un numero che cambia a ogni richiesta (anche se ripetuta).
    private(set) var action: (name: String, serial: Int)?
    @ObservationIgnored private var started = false

    func start() {
        guard !started, let script = UserDefaults.standard.string(forKey: "BCWScript") else { return }
        started = true
        for step in script.split(separator: ";") {
            let parts = step.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let seconds = Double(parts[0]) else { continue }
            let command = parts[1]
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                self.run(command)
            }
        }
    }

    private func run(_ command: String) {
        let pair = command.split(separator: "=", maxSplits: 1).map(String.init)
        let key = pair[0]
        let value = pair.count > 1 ? pair[1] : ""
        print("BCW-SCRIPT \(command)")
        switch key {
        case "glass": ThemeStore.shared.liquidGlass = value == "YES"
        case "tab": tab = value
        case "class": windowClass = value == "compact" ? .compact : (value == "regular" ? .regular : nil)
        case "orientation": DebugOrientation.apply(value)
        case "sidebar": TabSidebar.setHidden(value != "open")
        case "action": action = (value, (action?.serial ?? 0) + 1)
        default: print("BCW-SCRIPT comando sconosciuto: \(command)")
        }
    }
}

extension View {
    /// Esegue `perform` quando lo script di prova chiede l'azione `name`.
    func debugAction(_ name: String, perform: @escaping () -> Void) -> some View {
        onChange(of: DebugScript.shared.action?.serial) {
            if DebugScript.shared.action?.name == name { perform() }
        }
    }
}
#endif

import UIKit

/// Barra laterale della `TabView` di sistema sull'iPad (`UITabBarController.sidebar`): SwiftUI non
/// ha un'API per aprirla, chiuderla o toglierla.
enum TabSidebar {
    static func setHidden(_ hidden: Bool) {
        for controller in controllers() where controller.sidebar.isHidden != hidden {
            controller.sidebar.isHidden = hidden
        }
    }

    /// Senza Liquid Glass la barra laterale di sistema non deve mai comparire (c'è quella di
    /// Material): la `TabView` passa alla sola barra delle schede (nascosta), dove la barra laterale
    /// non esiste. Con la barra laterale soltanto nascosta UIKit la riapriva da solo allargando la
    /// finestra (verificato riducendo la barra di Material in orizzontale).
    static func setAvailable(_ available: Bool) {
        let mode: UITabBarController.Mode = available ? .tabSidebar : .tabBar
        for controller in controllers() where controller.mode != mode {
            controller.mode = mode
        }
    }

    private static func controllers() -> [UITabBarController] {
        var found: [UITabBarController] = []
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                if let controller = tabBarController(in: window.rootViewController) { found.append(controller) }
            }
        }
        return found
    }

    private static func tabBarController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let found = tabBarController(in: child) { return found }
        }
        return tabBarController(in: controller.presentedViewController)
    }
}

#if DEBUG
/// Per le prove: `-BCWFakeWindow 1180x820` disegna l'app in una finestra finta di quella misura,
/// rimpicciolita per stare nello schermo. Sull'iPad di iPadOS 26 con le finestre l'orientamento
/// non si cambia da codice e `simctl` non ruota il simulatore: così si prova l'iPad in orizzontale.
struct FakeWindow: ViewModifier {
    private let size: CGSize? = {
        guard let value = UserDefaults.standard.string(forKey: "BCWFakeWindow") else { return nil }
        let parts = value.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }()

    func body(content: Content) -> some View {
        if let size {
            GeometryReader { proxy in
                let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
                content
                    // La barra di stato dello schermo vero sta sopra la finestra finta.
                    .safeAreaPadding(.top, 24)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }
}
#endif
