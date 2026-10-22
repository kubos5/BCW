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
        // I comandi dell'accessibilità vogliono l'albero dell'accessibilità, che SwiftUI costruisce
        // solo con un servizio di accessibilità attivo (come fa Accessibility Inspector).
        if script.contains("press=") || script.contains("custom=") || script.contains("ax=") {
            DebugAccessibility.enableRuntime()
        }
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
        case "press": DebugAccessibility.press(value)
        case "custom": DebugAccessibility.customAction(value)
        case "type": DebugAccessibility.type(value)
        case "ax": DebugAccessibility.dump(filter: value)
        case "views": DebugAccessibility.views(minWidth: Double(value) ?? 300)
        default: print("BCW-SCRIPT comando sconosciuto: \(command)")
        }
    }
}

/// Tocchi senza tocchi (solo sviluppo): attiva gli elementi dell'interfaccia attraverso
/// l'accessibilità, come VoiceOver. `press=Etichetta` (o `press=Etichetta#2` per la seconda con
/// la stessa etichetta), `custom=Etichetta|Azione` (azione personalizzata, es. la pressione
/// prolungata), `type=testo` (nel campo con il fuoco), `ax=filtro` (elenca le etichette).
enum DebugAccessibility {
    static func enableRuntime() {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSApplicationAccessibilitySetEnabled") else {
            print("BCW-SCRIPT accessibilità non disponibile")
            return
        }
        typealias Enable = @convention(c) (Bool) -> Void
        unsafeBitCast(symbol, to: Enable.self)(true)
    }

    private static func elements() -> [NSObject] {
        var found: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 80, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
            if object.isAccessibilityElement { found.append(object) }
            if let children = object.accessibilityElements as? [NSObject] {
                for child in children { visit(child, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound, count > 0 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject { visit(child, depth: depth + 1) }
                    }
                }
            }
            if let view = object as? UIView {
                for subview in view.subviews { visit(subview, depth: depth + 1) }
            }
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            // Prima le finestre in primo piano (fogli e menu stanno nei controller presentati).
            for window in scene.windows.reversed() where !window.isHidden { visit(window, depth: 0) }
        }
        return found
    }

    private static func visible(_ object: NSObject) -> Bool {
        let frame = object.accessibilityFrame
        let screens = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.bounds }
        return !frame.isEmpty && screens.contains { frame.intersects($0) }
    }

    private static func find(_ query: String) -> NSObject? {
        let parts = query.split(separator: "#", maxSplits: 1)
        let label = String(parts.first ?? "")
        let index = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        let all = elements().filter(visible)
        let exact = all.filter { $0.accessibilityLabel == label }
        let matches = exact.isEmpty
            ? all.filter { ($0.accessibilityLabel ?? "").localizedCaseInsensitiveContains(label) } : exact
        return matches.count >= index ? matches[index - 1] : nil
    }

    static func press(_ query: String) {
        guard let element = find(query) else {
            print("BCW-SCRIPT press: nessun elemento \"\(query)\"")
            return
        }
        let done = element.accessibilityActivate()
        print("BCW-SCRIPT press \"\(element.accessibilityLabel ?? "")\" → \(done ? "ok" : "non attivato") \(element.accessibilityFrame)")
    }

    static func customAction(_ value: String) {
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let element = find(parts[0]) else {
            print("BCW-SCRIPT custom: nessun elemento \"\(value)\"")
            return
        }
        guard let action = element.accessibilityCustomActions?.first(where: { $0.name == parts[1] }) else {
            print("BCW-SCRIPT custom: azioni di \"\(parts[0])\": \(element.accessibilityCustomActions?.map(\.name) ?? [])")
            return
        }
        if let handler = action.actionHandler {
            print("BCW-SCRIPT custom \(parts[1]) → \(handler(action) ? "ok" : "non eseguita")")
        } else if let target = action.target as? NSObject {
            target.perform(action.selector, with: action)
            print("BCW-SCRIPT custom \(parts[1]) → inviata")
        }
    }

    static func type(_ text: String) {
        func responder(in view: UIView) -> UIView? {
            if view.isFirstResponder { return view }
            for subview in view.subviews { if let found = responder(in: subview) { return found } }
            return nil
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                if let input = responder(in: window) as? UIKeyInput {
                    input.insertText(text)
                    print("BCW-SCRIPT type → ok")
                    return
                }
            }
        }
        print("BCW-SCRIPT type: nessun campo con il fuoco")
    }

    /// Viste UIKit con uno sfondo, larghe almeno `minWidth` (per trovare chi disegna uno sfondo).
    static func views(minWidth: Double) {
        func visit(_ view: UIView, depth: Int) {
            let frame = view.convert(view.bounds, to: nil)
            if frame.width >= minWidth, let color = view.backgroundColor, color.cgColor.alpha > 0 {
                print("BCW-VIEW \(String(repeating: " ", count: depth))\(Swift.type(of: view)) \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)) \(color)")
            }
            for subview in view.subviews where !subview.isHidden { visit(subview, depth: depth + 1) }
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where !window.isHidden { visit(window, depth: 0) }
        }
    }

    static func dump(filter: String) {
        for element in elements() where visible(element) {
            let label = element.accessibilityLabel ?? ""
            guard filter.isEmpty || label.localizedCaseInsensitiveContains(filter) else { continue }
            let frame = element.accessibilityFrame
            print("BCW-AX \"\(label)\" [\(element.accessibilityValue ?? "")] \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
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
