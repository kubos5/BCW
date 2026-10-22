import SwiftUI
import UIKit

// MARK: - Account BCW

/// Sezione "Account BCW" della pagina Account: chi ha effettuato l'accesso, la
/// sincronizzazione e le azioni sull'account; senza account BCW, l'invito ad accedere o a crearne uno.
struct CloudAccountSection: View {
    @Environment(AppModel.self) private var model
    @State private var signingIn = false
    @State private var registering = false
    @State private var editingServer = false
    @State private var changingPassword = false
    @State private var deleting = false
    @State private var confirmingSignOut = false

    var body: some View {
        Group {
            if let session = model.cloud {
                signedIn(session)
            } else {
                ListGroup("Account BCW", footer: "Con un account BCW abbini i tuoi account Classeviva e ritrovi impostazioni, aspetto e orario su ogni dispositivo, anche nella versione web. Dopo l'accesso potrai abbinare gli account salvati su questo dispositivo.") {
                    ButtonRow("Accedi con un account BCW", icon: "cloud") { signingIn = true }
                    ButtonRow("Crea un account BCW", icon: "userPlus") { registering = true }
                    serverRow
                }
            }
        }
        .sheet(isPresented: $signingIn) { CloudLoginSheet(registering: false) }
        .sheet(isPresented: $registering) { CloudLoginSheet(registering: true) }
        .sheet(isPresented: $editingServer) { CloudServerSheet() }
        .sheet(isPresented: $changingPassword) { CloudPasswordSheet() }
        .sheet(isPresented: $deleting) { CloudDeleteSheet() }
        .m3Dialog("Vuoi uscire dall'account BCW \(model.cloud?.user.username ?? "")?", isPresented: $confirmingSignOut,
                  message: "Gli account Classeviva abbinati e i loro dati verranno rimossi da questo dispositivo. Restano nel tuo account BCW: li ritroverai accedendo di nuovo.") {
            [.cancel(), DialogAction(title: "Esci", style: .destructive) { Task { await model.cloudSignOut() } }]
        }
    }

    private func signedIn(_ session: BCWSession) -> some View {
        let sync = model.cloudSync
        return ListGroup("Account BCW", footer: "Si sincronizzano le impostazioni (tranne blocco, promemoria e notifiche, che valgono solo su questo dispositivo), l'aspetto e l'orario di ogni account abbinato, con i file allegati.") {
            ListRow(session.user.username, subtitle: "Account BCW") {
                Avatar(initials: String(session.user.username.prefix(1)).uppercased(), size: 40, shape: .cookie9Sided)
            } trailing: {
                EmptyView()
            }
            ListRow("Sincronizzazione", subtitle: syncDetail(sync)) {
                FormIcon("cloud")
            } trailing: {
                HStack(spacing: 8) {
                    if sync.status == .syncing { InlineProgress(size: 18) }
                    Text(syncStatus(sync))
                        .font(.m3(14))
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
            }
            ButtonRow("Sincronizza ora", icon: "refresh") {
                Task {
                    await sync.flush()
                    await model.refreshCloud(force: true)
                }
            }
            .disabled(sync.status == .syncing)
            ButtonRow("Cambia password…", icon: "key") { changingPassword = true }
            serverRow
            ButtonRow("Esci da BCW", icon: "logout", destructive: true) { confirmingSignOut = true }
            ButtonRow("Elimina l'account BCW…", icon: "trash", destructive: true) { deleting = true }
        }
    }

    private var serverRow: some View {
        Button {
            editingServer = true
        } label: {
            NavigationRow("Server BCW", subtitle: BCWServer.host, icon: "server")
        }
        .buttonStyle(.listRow)
    }

    private func syncStatus(_ sync: CloudSync) -> String {
        switch sync.status {
        case .syncing: "In corso…"
        case .ok: sync.lastSync.map { "Aggiornata alle \($0.time)" } ?? "Aggiornata"
        case .offline: "Offline"
        case .failed: "Non riuscita"
        case .idle: "Attiva"
        }
    }

    private func syncDetail(_ sync: CloudSync) -> String? {
        switch sync.status {
        case .offline, .failed: sync.message
        default: sync.fileWarning
        }
    }
}

/// Accesso o creazione dell'account BCW da Impostazioni › Account.
struct CloudLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    let registering: Bool

    var body: some View {
        NavigationStack {
            LoginView(cloudOnly: true, startsRegistering: registering)
                .sheetChrome("Account BCW", leading: .cancel { dismiss() })
        }
        .m3Sheet()
    }
}

/// Cambio della password dell'account BCW (le altre sessioni vengono chiuse).
struct CloudPasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cambiando la password dell'account BCW \(model.cloud?.user.username ?? "") uscirai da BCW sugli altri dispositivi.")
                        .font(.m3(15))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ListGroup(footer: errorMessage) {
                        SecureFieldRow("Password attuale", text: $current, contentType: .password)
                        SecureFieldRow("Nuova password (almeno 8 caratteri)", text: $new, contentType: .newPassword)
                        SecureFieldRow("Ripeti la nuova password", text: $confirm, contentType: .newPassword)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .sheetChrome("Cambia password", leading: .cancel { dismiss() },
                         trailing: [.confirm("Salva", disabled: isSaving || current.isEmpty || new.isEmpty) { save() }])
        }
        .m3Sheet()
        .m3Detents([.medium, .large])
    }

    private func save() {
        guard new.count >= 8 else {
            errorMessage = "La nuova password deve avere almeno 8 caratteri."
            return
        }
        guard new == confirm else {
            errorMessage = "Le due password nuove non coincidono."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await model.changeCloudPassword(current: current, new: new)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Eliminazione dell'account BCW, con la password e una conferma.
struct CloudDeleteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isDeleting = false
    @State private var confirming = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Verranno eliminati l'account BCW \(model.cloud?.user.username ?? ""), gli abbinamenti con gli account Classeviva, le impostazioni sincronizzate e gli orari salvati sul server, con i loro file. Da questo dispositivo spariranno gli account abbinati.")
                        .font(.m3(15))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    ListGroup(footer: errorMessage) {
                        SecureFieldRow("Password dell'account BCW", text: $password, contentType: .password)
                    }
                    Button {
                        confirming = true
                    } label: {
                        Text("Elimina l'account BCW")
                            .opacity(isDeleting ? 0 : 1)
                            .overlay {
                                if isDeleting { LoadingIndicator(size: 24, color: Theme.onError) }
                            }
                    }
                    .buttonStyle(.m3(.danger, size: .m, wide: true))
                    .disabled(password.isEmpty || isDeleting)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .sheetChrome("Elimina l'account BCW", leading: .cancel { dismiss() })
            // Dentro il foglio: il dialogo usa il livello delle sovrapposizioni del foglio.
            .m3Dialog("Eliminare l'account BCW \(model.cloud?.user.username ?? "")?", isPresented: $confirming,
                      message: "L'account BCW, gli abbinamenti con gli account Classeviva, le impostazioni sincronizzate e gli orari salvati sul server verranno eliminati definitivamente. Gli account Classeviva non cambiano.") {
                [.cancel(), DialogAction(title: "Elimina", style: .destructive) { delete() }]
            }
        }
        .m3Sheet()
        .m3Detents([.medium, .large])
    }

    private func delete() {
        isDeleting = true
        errorMessage = nil
        Task {
            defer { isDeleting = false }
            do {
                try await model.deleteCloudAccount(password: password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Voce con un campo per una password.
private struct SecureFieldRow: View {
    let prompt: String
    @Binding var text: String
    let contentType: UITextContentType

    init(_ prompt: String, text: Binding<String>, contentType: UITextContentType) {
        self.prompt = prompt
        _text = text
        self.contentType = contentType
    }

    var body: some View {
        HStack(spacing: 16) {
            FormIcon("key")
            SecureField(prompt, text: $text)
                .textContentType(contentType)
                .textFieldStyle(.plain)
                .font(.m3(16))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}

// MARK: - Lato Classeviva

/// Account BCW a cui è abbinato il profilo Classeviva attivo, con lo scollegamento. Funziona
/// anche entrando con l'account Classeviva: basta l'accesso a Classeviva, non la password di
/// quegli account BCW. Senza account BCW l'elenco si carica solo a richiesta, perché il server
/// BCW riceve il token della sessione di Classeviva per verificare l'accesso.
struct ClassevivaLinksSection: View {
    @Environment(AppModel.self) private var model
    @State private var requested = false
    @State private var links: [BCWLink]?
    @State private var errorMessage: String?
    @State private var round = 0
    @State private var removing: BCWLink?
    @State private var removingAll = false
    @State private var actionError: String?

    private var shouldLoad: Bool { model.isCloud || requested }

    var body: some View {
        if !model.isDemo, let account = model.activeAccount {
            ListGroup("Account BCW abbinati", footer: footer(account)) {
                if !shouldLoad {
                    ButtonRow("Mostra gli account BCW abbinati", icon: "cloud") { requested = true }
                } else if let errorMessage {
                    ListRow("Elenco non disponibile", subtitle: errorMessage) {
                        FormIcon("alertTriangle", color: Theme.error)
                    } trailing: {
                        EmptyView()
                    }
                    ButtonRow("Riprova", icon: "refresh") { reload() }
                } else if let links {
                    if links.isEmpty {
                        ListRow("Nessun account BCW", subtitle: "Questo account Classeviva non è abbinato a nessun account BCW.") {
                            FormIcon("cloud")
                        } trailing: {
                            EmptyView()
                        }
                    } else {
                        ForEach(links) { link in
                            linkRow(link)
                        }
                        if links.count > 1 {
                            ButtonRow("Scollega da tutti", icon: "trash", destructive: true) { removingAll = true }
                        }
                    }
                } else {
                    ListRow("Caricamento…") {
                        FormIcon("cloud")
                    } trailing: {
                        InlineProgress(size: 18)
                    }
                }
            }
            .task(id: "\(account.id)-\(round)-\(shouldLoad)") {
                if shouldLoad { await load() }
            }
            .m3Dialog("Scollegare da \(removing?.username ?? "")?",
                      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                      message: removing.map(removalMessage)) {
                let link = removing
                return [.cancel(), DialogAction(title: "Scollega", style: .destructive) {
                    if let link { remove(link.id) }
                }]
            }
            .m3Dialog("Scollegare da tutti gli account BCW?", isPresented: $removingAll,
                      message: "Nessun account BCW potrà più entrare in \(account.name)\(model.isCloud ? ", compreso quello con cui hai effettuato l'accesso" : ""). Gli orari sincronizzati per questo account verranno eliminati dal server.") {
                [.cancel(), DialogAction(title: "Scollega da tutti", style: .destructive) { remove(nil) }]
            }
            .m3Dialog("Scollegamento non riuscito", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } }),
                      message: actionError) {
                [.cancel("OK")]
            }
        }
    }

    private func footer(_ account: SavedAccount) -> String {
        guard shouldLoad else {
            return "Puoi vedere a quali account BCW è abbinato \(account.name) e scollegarlo da ognuno. Per verificare l'accesso, il server BCW riceve il token della sessione di Classeviva (non la password)."
        }
        return "Gli account BCW con cui si entra in \(account.name). Scollegandolo da uno, quell'account BCW non potrà più entrarci e l'orario sincronizzato per questo account viene eliminato dal server. Per toglierli basta l'accesso a Classeviva."
    }

    private func linkRow(_ link: BCWLink) -> some View {
        let mine = model.isCloud && link.id == model.activeAccountID
        return HStack(spacing: 0) {
            ListRow(link.username, subtitle: "Abbinato il \(link.date.shortDayWithYear)\(mine ? " · questo account BCW" : "")") {
                FormIcon("cloud", color: mine ? Theme.primary : nil)
            } trailing: {
                EmptyView()
            }
            IconButton("minusCircle", label: "Scollega") { removing = link }
                .padding(.trailing, 8)
                .help("Scollega da questo account BCW")
        }
    }

    private func removalMessage(_ link: BCWLink) -> String {
        let name = model.activeAccount?.name ?? "questo account Classeviva"
        if model.isCloud && link.id == model.activeAccountID {
            return "È l'account BCW con cui hai effettuato l'accesso: \(name) non sarà più disponibile con esso e il suo orario verrà eliminato dal server."
        }
        return "L'account BCW \(link.username) non potrà più entrare in \(name) e l'orario che ha sincronizzato per questo account verrà eliminato dal server."
    }

    private func load() async {
        do {
            let result = try await model.classevivaLinks()
            links = result
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        links = nil
        errorMessage = nil
        round += 1
    }

    private func remove(_ id: String?) {
        Task {
            do {
                try await model.removeClassevivaLink(id)
            } catch {
                actionError = error.localizedDescription
            }
            reload()
        }
    }
}
