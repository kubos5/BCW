import SwiftUI
import UIKit

/// Azione eseguita tenendo premuta una scheda della barra in basso.
/// `Tab.contextMenu` di SwiftUI su iPhone non fa nulla (vale solo per la barra laterale
/// dell'iPad): qui si aggiunge alla `UITabBar` un riconoscitore di pressione prolungata che
/// risponde solo sopra la scheda indicata. Quando scatta, gli altri gesti della barra vengono
/// annullati, quindi la scheda non viene selezionata; il resto della barra funziona come sempre.
struct TabBarItemLongPress: UIViewRepresentable {
    /// Posizione della scheda tra quelle della barra (le schede con ruolo `.search` contano).
    let index: Int
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.index = index
        context.coordinator.action = action
        // La barra esiste solo dopo che la vista è entrata nella finestra.
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var index = 0
        var action: () -> Void = {}
        private weak var tabBar: UITabBar?
        private var recognizer: UILongPressGestureRecognizer?

        func attach(from view: UIView) {
            guard let window = view.window, let bar = Self.tabBar(in: window) else { return }
            guard bar !== tabBar else { return }
            if let recognizer { tabBar?.removeGestureRecognizer(recognizer) }
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            recognizer.delegate = self
            bar.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            tabBar = bar
        }

        static func tabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for subview in view.subviews {
                if let bar = tabBar(in: subview) { return bar }
            }
            return nil
        }

        /// Vista della scheda nella barra: `UITabBarItem` la espone con la chiave `view`.
        private var itemView: UIView? {
            guard let items = tabBar?.items, items.indices.contains(index) else { return nil }
            return items[index].value(forKey: "view") as? UIView
        }

        @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            cancelOtherGestures(except: recognizer)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }

        /// Annulla i gesti della barra ancora in corso (selezione della scheda al rilascio,
        /// trascinamento tra le schede): disattivarli e riattivarli li interrompe.
        private func cancelOtherGestures(except own: UIGestureRecognizer) {
            guard let tabBar else { return }
            func visit(_ view: UIView) {
                for other in view.gestureRecognizers ?? [] where other !== own && other.isEnabled {
                    other.isEnabled = false
                    other.isEnabled = true
                }
                view.subviews.forEach(visit)
            }
            visit(tabBar)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let tabBar, let itemView, !itemView.isHidden else { return false }
            let frame = itemView.convert(itemView.bounds, to: tabBar)
            return frame.contains(gestureRecognizer.location(in: tabBar))
        }

        // La barra ha i suoi riconoscitori (selezione, trascinamento tra le schede): convivono.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Icone piene delle schede della barra di sistema (Liquid Glass) come `selectedImage` degli
/// elementi della `UITabBar`: la barra mostra l'aspetto selezionato dentro la bolla mentre si
/// sposta, quindi l'icona piena segue la bolla (come nelle app di sistema). Con un'icona scelta
/// nell'etichetta SwiftUI in base alla scheda aperta cambiava solo a selezione avvenuta.
struct TabBarSelectedImages: UIViewRepresentable {
    /// Nomi delle icone piene (senza `m.`), nell'ordine delle schede della barra.
    let names: [String]

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // La barra esiste solo dopo che la vista è entrata nella finestra (all'avvio si riprova);
        // SwiftUI può rifare gli elementi a ogni aggiornamento: si riapplicano ogni volta.
        apply(from: view, attempts: 10)
    }

    private func apply(from view: UIView, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempts == 10 ? 0 : 0.25)) {
            guard let window = view.window, let bar = TabBarItemLongPress.Coordinator.tabBar(in: window),
                  let items = bar.items, !items.isEmpty else {
                if attempts > 0 { apply(from: view, attempts: attempts - 1) }
                return
            }
            for (item, name) in zip(items, names) {
                guard let image = item.image, item.selectedImage?.accessibilityIdentifier != name,
                      let filled = UIImage(named: "m." + name) else { continue }
                // Alla stessa misura dell'icona normale, come modello da tingere.
                let size = image.size
                let selected = UIGraphicsImageRenderer(size: size).image { _ in
                    filled.draw(in: CGRect(origin: .zero, size: size))
                }.withRenderingMode(.alwaysTemplate)
                selected.accessibilityIdentifier = name
                item.selectedImage = selected
            }
        }
    }
}
