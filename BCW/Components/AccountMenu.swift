import SwiftUI

/// Popup per cambiare account: sale dal basso con la stessa sezione "Account" della pagina
/// Account e, con l'account BCW, "Esci da BCW". Si apre dall'avatar nella Dashboard, dal pulsante
/// account in Tu e tenendo premuta la scheda Tu.
/// Si chiude da solo quando cambia la sessione (altro account, demo o account aggiunto).
struct AccountSwitcherSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var addingAccount = false
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AccountsSection(showsHeader: false) { addingAccount = true }
                    // Con l'account BCW: l'uscita, come in Impostazioni › Account › Account BCW.
                    if let session = model.cloud {
                        ListGroup(footer: "Hai effettuato l'accesso con l'account BCW \(session.user.username).") {
                            ButtonRow("Esci da BCW", icon: "logout", destructive: true) { confirmingSignOut = true }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .sheetChrome("Account", leading: .close { dismiss() })
            // Dentro il foglio (sotto il suo `overlayHost`): fuori, il dialogo finirebbe dietro il foglio.
            .m3Dialog("Vuoi uscire dall'account BCW \(model.cloud?.user.username ?? "")?", isPresented: $confirmingSignOut,
                      message: "Gli account Classeviva abbinati e i loro dati verranno rimossi da questo dispositivo. Restano nel tuo account BCW: li ritroverai accedendo di nuovo.") {
                [.cancel(), DialogAction(title: "Esci", style: .destructive) { Task { await model.cloudSignOut() } }]
            }
        }
        .m3Sheet()
        .m3Detents([.medium, .large])
        // Si chiude appena comincia il cambio, prima della dissolvenza dell'app.
        .onChange(of: model.isChangingSession) { _, changing in if changing { dismiss() } }
        .onChange(of: model.sessionID) { dismiss() }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet { addingAccount = false }
        }
    }
}
