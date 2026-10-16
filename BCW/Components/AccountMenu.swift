import SwiftUI

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
