import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// `true` quando si aggiunge un altro account da dentro l'app (presentata come foglio).
    let isAddingAccount: Bool
    /// Solo l'accesso con l'account BCW (foglio aperto da Impostazioni › Account).
    let cloudOnly: Bool

    enum Mode: Hashable { case classeviva, bcw }

    @State private var mode: Mode
    @State private var registering: Bool
    @State private var username = ""
    @State private var password = ""
    @State private var bcwUsername = ""
    @State private var bcwPassword = ""
    @State private var bcwConfirm = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var choices: [LoginChoice] = []
    @State private var editingServer = false
    @State private var confirmingCloudSignOut = false
    /// Tastiera visibile (dalle notifiche di UIKit, non dal campo attivo: cambiando tra Classeviva e
    /// Account BCW il campo attivo cambia ma la tastiera resta).
    @State private var keyboardVisible = false
    @FocusState private var focused: Field?

    private enum Field { case username, password, bcwUsername, bcwPassword, bcwConfirm }

    init(isAddingAccount: Bool = false, cloudOnly: Bool = false, startsRegistering: Bool = false) {
        self.isAddingAccount = isAddingAccount
        self.cloudOnly = cloudOnly
        _mode = State(initialValue: cloudOnly ? .bcw : .classeviva)
        _registering = State(initialValue: startsRegistering)
    }

    /// Tastiera aperta: disposizione compatta, in alto, con logo piccolo accanto al titolo, il gruppo
    /// Classeviva/Account BCW, campi e "Accedi" subito sotto; demo e note tornano chiudendo la tastiera.
    private var compact: Bool { keyboardVisible }

    /// Con l'account BCW ma senza account abbinati: si abbina il primo.
    private var linkingFirst: Bool { !isAddingAccount && !cloudOnly && model.isCloud }

    /// Il gruppo di pulsanti tra Classeviva e Account BCW c'è solo nella schermata di accesso.
    private var showsModePicker: Bool { !isAddingAccount && !cloudOnly && !model.isCloud }

    private var currentMode: Mode {
        if cloudOnly { return .bcw }
        return isAddingAccount || model.isCloud ? .classeviva : mode
    }

    private var title: String {
        if cloudOnly { return registering ? "Crea un account BCW" : "Accedi con un account BCW" }
        if isAddingAccount { return model.isCloud ? "Abbina un account Classeviva" : "Aggiungi un account" }
        if linkingFirst { return "Ciao, \(model.cloud?.user.username ?? "")" }
        return "Better ClasseViVa"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: compact ? 20 : 24) {
                if compact { compactHeader } else { header }

                if showsModePicker {
                    SegmentedButtons(selection: $mode, options: [(Mode.classeviva, "Classeviva", nil), (Mode.bcw, "Account BCW", nil)],
                                     height: 48)
                }

                if linkingFirst && !compact {
                    Text("Abbina il tuo primo account Classeviva: con il tuo account BCW entrerai in tutti gli account abbinati, su ogni dispositivo.")
                        .font(.m3(15))
                        .foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                if currentMode == .bcw {
                    cloudForm
                } else {
                    classevivaForm
                }

                if !compact {
                    footerArea
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, compact ? 16 : 32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: compact ? .top : .center) { length, _ in length }
            // Un tocco nello spazio vuoto chiude la tastiera (campi e pulsanti hanno i loro tocchi).
            .background {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { focused = nil }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .themedBackground()
        .animation(Motion.spatial, value: errorMessage)
        .animation(Motion.spatial, value: focused)
        .animation(Motion.spatial, value: registering)
        .animation(Motion.spatial, value: mode)
        .onAppear {
            // Dopo una sessione BCW scaduta si riparte dall'accesso con l'account BCW.
            if showsModePicker, model.cloudNotice != nil { mode = .bcw }
            if bcwUsername.isEmpty { bcwUsername = model.lastCloudUsername ?? "" }
        }
        .onChange(of: mode) { _, mode in
            errorMessage = nil
            // Con la tastiera aperta il cursore passa al campo corrispondente dell'altro modulo, al giro
            // dopo (quando c'è): la tastiera resta e niente si sposta.
            guard let field = focused else { return }
            let target: Field = switch (mode, field) {
            case (.bcw, .username): .bcwUsername
            case (.bcw, .password): .bcwPassword
            case (.classeviva, .bcwUsername): .username
            case (.classeviva, _): .password
            default: field
            }
            DispatchQueue.main.async { focused = target }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(Motion.spatial) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Motion.spatial) { keyboardVisible = false }
        }
        .sheet(isPresented: Binding(get: { !choices.isEmpty }, set: { if !$0 { choices = [] } })) {
            ProfileChoiceSheet(choices: choices) { choice in
                choices = []
                signIn(ident: choice.ident)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $editingServer) {
            CloudServerSheet()
        }
        .m3Dialog("Vuoi uscire dall'account BCW \(model.cloud?.user.username ?? "")?", isPresented: $confirmingCloudSignOut,
                  message: "Gli account Classeviva abbinati e i loro dati verranno rimossi da questo dispositivo. Restano nel tuo account BCW: li ritroverai accedendo di nuovo.") {
            [.cancel(), DialogAction(title: "Esci", style: .destructive) { Task { await model.cloudSignOut() } }]
        }
    }

    // MARK: Moduli

    private var classevivaForm: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                LoginField(icon: "person", focused: focused == .username) {
                    TextField("Codice utente o email", text: $username)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                }
                LoginField(icon: "key", focused: focused == .password) {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                }
            }
            .padding(.bottom, 4)

            errorBox

            Button(action: submit) {
                // L'indicatore è sovrapposto al testo: non cambia l'altezza del pulsante.
                Text(model.isCloud ? "Abbina" : "Accedi")
                    .opacity(isLoading ? 0 : 1)
                    .overlay {
                        if isLoading { LoadingIndicator(size: 24, color: Theme.onPrimary) }
                    }
            }
            .buttonStyle(.m3(.filled, size: .m, wide: true))
            .disabled(username.isEmpty || password.isEmpty || isLoading)

            if !isAddingAccount && !compact {
                Button {
                    model.startDemo()
                } label: {
                    Label { Text("Prova la demo") } icon: { Icon("sparkles") }
                }
                .buttonStyle(.m3(.tonal, size: .m, wide: true))
                .transition(.opacity)
            }

            if linkingFirst && !compact {
                Button {
                    confirmingCloudSignOut = true
                } label: {
                    Label { Text("Esci da BCW") } icon: { Icon("logout") }
                }
                .buttonStyle(.m3(.text, size: .m, wide: true))
                .transition(.opacity)
            }
        }
    }

    private var cloudForm: some View {
        VStack(spacing: 12) {
            if let notice = model.cloudNotice, errorMessage == nil {
                HStack(spacing: 10) {
                    Icon("info", size: 20)
                    Text(notice)
                        .font(.m3(14))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.onSecondaryContainer)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.secondaryContainer, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
            }

            VStack(spacing: 10) {
                LoginField(icon: "person", focused: focused == .bcwUsername) {
                    TextField("Nome utente BCW", text: $bcwUsername)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .bcwUsername)
                        .submitLabel(.next)
                        .onSubmit { focused = .bcwPassword }
                }
                LoginField(icon: "key", focused: focused == .bcwPassword) {
                    SecureField("Password", text: $bcwPassword)
                        .textContentType(registering ? UITextContentType.newPassword : UITextContentType.password)
                        .focused($focused, equals: .bcwPassword)
                        .submitLabel(registering ? SubmitLabel.next : SubmitLabel.go)
                        .onSubmit { if registering { focused = .bcwConfirm } else { submitCloud() } }
                }
                if registering {
                    LoginField(icon: "key", focused: focused == .bcwConfirm) {
                        SecureField("Ripeti la password", text: $bcwConfirm)
                            .textContentType(.newPassword)
                            .focused($focused, equals: .bcwConfirm)
                            .submitLabel(.go)
                            .onSubmit(submitCloud)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 4)

            if registering && !compact {
                Text("Da 3 a 32 caratteri tra lettere, cifre, punto, trattino e trattino basso. La password deve avere almeno 8 caratteri.")
                    .font(.m3(12))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            errorBox

            Button(action: submitCloud) {
                Text(registering ? "Crea account" : "Accedi")
                    .opacity(isLoading ? 0 : 1)
                    .overlay {
                        if isLoading { LoadingIndicator(size: 24, color: Theme.onPrimary) }
                    }
            }
            .buttonStyle(.m3(.filled, size: .m, wide: true))
            .disabled(bcwUsername.isEmpty || bcwPassword.isEmpty || (registering && bcwConfirm.isEmpty) || isLoading)

            if !compact {
                Button {
                    registering.toggle()
                    errorMessage = nil
                    bcwConfirm = ""
                } label: {
                    if registering {
                        Text("Hai già un account? Accedi")
                    } else {
                        Label { Text("Crea un account BCW") } icon: { Icon("userPlus") }
                    }
                }
                .buttonStyle(.m3(.tonal, size: .m, wide: true))
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var errorBox: some View {
        if let errorMessage {
            HStack(spacing: 10) {
                Icon("alertTriangleFill", size: 20)
                Text(errorMessage)
                    .font(.m3(14))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.onPoorContainer)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.poorContainer, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Intestazione e note

    private var header: some View {
        VStack(spacing: 10) {
            BCWLogo(size: 64)
            Text(title)
                .font(.m3(16, weight: 500))
                .foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: isAddingAccount || cloudOnly ? 0 : 200)
        .background {
            if !isAddingAccount && !cloudOnly { LoginArt() }
        }
        .accessibilityElement(children: .combine)
    }

    /// Intestazione con la tastiera aperta: logo piccolo e titolo su una riga, centrati tra loro
    /// sulle maiuscole (con le linee di base allineate il titolo, più piccolo, stava in basso).
    private var compactHeader: some View {
        let logoCaps = Typography.platformFont(size: 30, weight: 800, rounded: true).capHeight
        let titleCaps = Typography.platformFont(size: 16, weight: 500).capHeight
        return HStack(alignment: .capCenter, spacing: 14) {
            BCWLogo(size: 30)
                .alignmentGuide(.capCenter) { $0[.firstTextBaseline] - logoCaps / 2 }
            Text(title)
                .font(.m3(16, weight: 500))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1)
                .alignmentGuide(.capCenter) { $0[.firstTextBaseline] - titleCaps / 2 }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    /// Note in basso. Con il gruppo Classeviva/Account BCW occupano sempre l'altezza delle più lunghe
    /// e sono allineate in alto: cambiando scelta il resto della pagina (centrato) non si sposta.
    @ViewBuilder
    private var footerArea: some View {
        if showsModePicker {
            ZStack(alignment: .top) {
                footer(for: .classeviva).hidden()
                footer(for: .bcw).hidden()
                footer(for: currentMode)
            }
        } else {
            footer(for: currentMode)
        }
    }

    private func footer(for mode: Mode) -> some View {
        VStack(spacing: 8) {
            if mode == .bcw {
                Text("Con un account BCW entri in tutti i tuoi account Classeviva abbinati e ritrovi impostazioni e orario su ogni dispositivo. Le credenziali di Classeviva sono salvate cifrate sul server di BCW.")
            } else if model.isCloud {
                Text("Usa le credenziali di Classeviva. Il server di BCW le verifica e le salva cifrate nel tuo account BCW.")
            } else {
                Text("Usa le stesse credenziali di Classeviva. Restano solo su questo dispositivo, nel Portachiavi, e vengono inviate esclusivamente ai server di Classeviva.")
            }
            if !isAddingAccount {
                Text("BCW non è affiliata a Gruppo Spaggiari Parma.")
            }
            if mode == .bcw || linkingFirst {
                HStack(spacing: 6) {
                    Icon("cloud", size: 16)
                    Text("Server BCW: \(BCWServer.host)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("·")
                    Button("Modifica") { editingServer = true }
                        .buttonStyle(LinkButtonStyle())
                }
                if linkingFirst, let username = model.cloud?.user.username {
                    Text("Account BCW: \(username)")
                }
            }
        }
        .font(.m3(12))
        .foregroundStyle(Theme.secondaryInk)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    // MARK: Azioni

    private func submit() {
        signIn(ident: nil)
    }

    private func signIn(ident: String?) {
        guard !username.isEmpty, !password.isEmpty else { return }
        focused = nil
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await model.signIn(username: username, password: password, ident: ident)
                if isAddingAccount { dismiss() }
            } catch APIError.needsProfileChoice(let options) {
                choices = options
            } catch let error as URLError {
                errorMessage = error.code == .notConnectedToInternet
                    ? "Nessuna connessione a Internet."
                    : "Impossibile contattare Classeviva."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submitCloud() {
        let name = bcwUsername.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !bcwPassword.isEmpty else { return }
        if registering {
            guard bcwPassword.count >= 8 else {
                errorMessage = "La password deve avere almeno 8 caratteri."
                return
            }
            guard bcwPassword == bcwConfirm else {
                errorMessage = "Le due password non coincidono."
                return
            }
        }
        focused = nil
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await model.cloudSignIn(username: name, password: bcwPassword, register: registering)
                bcwPassword = ""
                bcwConfirm = ""
                if cloudOnly { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Indirizzo del server BCW (BCW-api): si cambia solo senza un account BCW aperto.
struct CloudServerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = BCWServer.isCustom ? BCWServer.baseURL.absoluteString : ""
    @State private var invalid = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Il server BCW (BCW-api) conserva gli account BCW, gli account Classeviva abbinati e le impostazioni e gli orari sincronizzati.")
                        .font(.m3(15))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isCloud {
                        Text("Stai usando \(BCWServer.baseURL.absoluteString). Per cambiare server esci prima dall'account BCW.")
                            .font(.m3(13))
                            .foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Lascia vuoto per usare quello predefinito (\(BCWServer.defaultURL.absoluteString)), oppure inserisci l'indirizzo di un altro server.")
                            .font(.m3(13))
                            .foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        ListGroup(footer: invalid ? "Questo non è un indirizzo valido." : nil) {
                            TextFieldRow("https://bcw-api.esempio.workers.dev", text: $address, icon: "server")
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .sheetChrome("Server BCW", leading: .cancel { dismiss() },
                         trailing: model.isCloud ? [] : [.confirm("Salva") { save() }])
        }
        .m3Sheet()
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard BCWServer.set(address) else {
            invalid = true
            return
        }
        dismiss()
    }
}

/// Campo dell'accesso: pieno, con l'icona; quando è attivo ha il bordo primario e gli angoli più stretti.
private struct LoginField<Content: View>: View {
    let icon: String
    let focused: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: focused ? Theme.radii.m : Theme.radii.l, style: .continuous)
        HStack(spacing: 12) {
            Icon(icon)
                .foregroundStyle(Theme.onSurfaceVariant)
            content()
                .textFieldStyle(.plain)
                .font(.m3(16))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.surfaceContainerHighest, in: shape)
        .overlay(shape.strokeBorder(Theme.primary, lineWidth: focused ? 2 : 0))
    }
}

/// Forme di Material 3 Expressive che ruotano lentamente dietro al logo.
private struct LoginArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || ThemeStore.shared.motion == .reduced)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let mid = proxy.size.width / 2
                ZStack(alignment: .topLeading) {
                    MaterialShape(.softBurst)
                        .fill(Theme.primaryContainer)
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(t / 40 * 360))
                        .offset(x: mid - 190, y: 4)
                    MaterialShape(.cookie9Sided)
                        .fill(Theme.tertiaryContainer)
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(-t / 32 * 360))
                        .offset(x: mid + 112, y: 92)
                    MaterialShape(.pill)
                        .fill(Theme.secondaryContainer)
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(t / 24 * 360))
                        .offset(x: mid + 64, y: 6)
                }
                .opacity(0.9)
            }
        }
        .accessibilityHidden(true)
    }
}

private extension VerticalAlignment {
    /// Metà altezza delle maiuscole della prima riga: centra tra loro testi di dimensioni diverse.
    enum CapCenter: AlignmentID {
        nonisolated static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    static let capCenter = VerticalAlignment(CapCenter.self)
}

private struct ProfileChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let choices: [LoginChoice]
    let onSelect: (LoginChoice) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                ListGroup {
                    ForEach(choices) { choice in
                        Button {
                            onSelect(choice)
                        } label: {
                            NavigationRow(choice.name.nameCased, subtitle: choice.school.nameCased)
                        }
                        .buttonStyle(.listRow)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .sheetChrome("Scegli il profilo", leading: .cancel { dismiss() })
        }
        .m3Sheet()
    }
}
