import SwiftUI

/// Voci del menu account nella barra laterale su macOS: gli account salvati (la demo non è un
/// account: compare solo quando è attiva), l'aggiunta di un account e la demo, sempre
/// disponibile anche con un account collegato.
struct AccountMenuItems: View {
    @Environment(AppModel.self) private var model
    let addAccount: () -> Void

    var body: some View {
        Section("Account") {
            ForEach(model.accounts) { account in
                let isActive = !model.isDemo && account.id == model.activeAccountID
                Button {
                    withAnimation { model.switchAccount(to: account.id) }
                } label: {
                    if isActive {
                        Label(account.name, systemImage: "checkmark")
                    } else {
                        Text(account.name)
                    }
                }
                .disabled(isActive)
            }
            if model.isDemo {
                Label("Demo", systemImage: "checkmark")
            }
        }
        Button(action: addAccount) {
            Label(Platform.isMac ? "Aggiungi account…" : "Aggiungi account", icon: "userPlus")
        }
        if !model.isDemo {
            // Uscendo dalla demo si torna a questo account.
            Button {
                withAnimation { model.startDemo() }
            } label: {
                Label("Prova la demo", icon: "sparkles")
            }
        }
    }
}

#if os(iOS)
/// Popup per cambiare account: sale dal basso con la stessa sezione "Account" della pagina
/// Account. Si apre dal pulsante account in Tu e tenendo premuta la scheda Tu.
/// Si chiude da solo quando cambia la sessione (altro account, demo o account aggiunto).
struct AccountSwitcherSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var addingAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                AccountsSection(showsHeader: false) { addingAccount = true }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            .sheetChrome("Account", leading: .close { dismiss() })
        }
        .m3Sheet()
        .presentationDetents([.medium, .large])
        // Si chiude appena comincia il cambio, prima della dissolvenza dell'app.
        .onChange(of: model.isChangingSession) { _, changing in if changing { dismiss() } }
        .onChange(of: model.sessionID) { dismiss() }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet { addingAccount = false }
        }
    }
}
#endif
