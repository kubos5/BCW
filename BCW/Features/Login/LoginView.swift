import CoreText
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
    /// Altezza della tastiera, come margine in fondo animato con la stessa molla della disposizione.
    @State private var keyboardHeight: CGFloat = 0
    /// Larghezza dell'intestazione (cambia solo ruotando o ridimensionando la finestra): dice se il titolo
    /// sta su una riga accanto al logo piccolo.
    @State private var headerWidth: CGFloat = 0
    /// iPad largo con la pagina larga almeno 760 punti: accesso in una card a due colonne.
    @State private var wideCard = false
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
    /// Non nella card larga dell'iPad: lì c'è spazio e lo scorrimento porta in vista il campo.
    private var compact: Bool { keyboardVisible && !wideCard }

    /// Card a due colonne (solo nella schermata di accesso: aggiungendo un account, in un foglio,
    /// resta la disposizione del telefono).
    private var showsWideCard: Bool { wideCard && !isAddingAccount && !cloudOnly }

    /// Con l'account BCW ma senza account abbinati: si abbina il primo.
    private var linkingFirst: Bool { !isAddingAccount && !cloudOnly && model.isCloud }

    /// Il gruppo di pulsanti tra Classeviva e Account BCW c'è solo nella schermata di accesso.
    private var showsModePicker: Bool { !isAddingAccount && !cloudOnly && !model.isCloud }

    private var currentMode: Mode {
        if cloudOnly { return .bcw }
        return isAddingAccount || model.isCloud ? .classeviva : mode
    }

    private var title: String {
        #if DEBUG
        // Per provare i titoli lunghi: `-BCWLoginTitle testo`.
        if let title = UserDefaults.standard.string(forKey: "BCWLoginTitle") { return title }
        #endif
        if cloudOnly { return registering ? "Crea un account BCW" : "Accedi con un account BCW" }
        if isAddingAccount { return model.isCloud ? "Abbina un account Classeviva" : "Aggiungi un account" }
        if linkingFirst { return "Ciao, \(model.cloud?.user.username ?? "")" }
        return "Better ClasseViVa"
    }

    var body: some View {
        ScrollView {
            if showsWideCard {
                wideLayout
            } else {
                phoneLayout
            }
        }
        // La tastiera non restringe lo scorrimento di colpo (il contenuto, centrato, saltava in alto
        // prima che partisse l'animazione): lo spazio della tastiera è un margine in fondo animato con
        // la molla della disposizione compatta. Nella card larga dell'iPad resta quello di sistema.
        .safeAreaPadding(.bottom, wideCard ? 0 : keyboardHeight)
        .ignoresSafeArea(wideCard ? [] : .keyboard, edges: .bottom)
        // Sull'iPad largo, da 760 punti, l'accesso è una card a due colonne (come la versione web).
        .widthAtLeast(760, isOn: $wideCard)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .themedBackground()
        .animation(Motion.spatial, value: errorMessage)
        .animation(Motion.spatial, value: focused)
        .animation(Motion.spatial, value: registering)
        .animation(Motion.spatial, value: mode)
        #if DEBUG
        // Script di prova (`-BCWScript`): cambia modulo o dà il fuoco al primo campo.
        .debugAction("loginmode") { mode = mode == .bcw ? .classeviva : .bcw }
        .debugAction("loginfocus") { focused = currentMode == .bcw ? .bcwUsername : .username }
        // Come se la tastiera si aprisse o chiudesse (sul simulatore con la tastiera del Mac non compare).
        .debugAction("loginkeyboard") {
            withAnimation(Motion.spatial) {
                keyboardVisible.toggle()
                keyboardHeight = keyboardVisible ? 336 : 0
            }
        }
        #endif
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            withAnimation(Motion.spatial) {
                keyboardVisible = true
                keyboardHeight = frame?.height ?? 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Motion.spatial) {
                keyboardVisible = false
                keyboardHeight = 0
            }
        }
        .sheet(isPresented: Binding(get: { !choices.isEmpty }, set: { if !$0 { choices = [] } })) {
            ProfileChoiceSheet(choices: choices) { choice in
                choices = []
                signIn(ident: choice.ident)
            }
            .m3Detents([.medium, .large])
        }
        .sheet(isPresented: $editingServer) {
            CloudServerSheet()
        }
        .m3Dialog("Vuoi uscire dall'account BCW \(model.cloud?.user.username ?? "")?", isPresented: $confirmingCloudSignOut,
                  message: "Gli account Classeviva abbinati e i loro dati verranno rimossi da questo dispositivo. Restano nel tuo account BCW: li ritroverai accedendo di nuovo.") {
            [.cancel(), DialogAction(title: "Esci", style: .destructive) { Task { await model.cloudSignOut() } }]
        }
    }

    /// Telefono (e iPad stretto o nei fogli): una colonna centrata.
    private var phoneLayout: some View {
        VStack(spacing: compact ? 20 : 24) {
            header

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

    /// iPad largo: card a due colonne (logo, titolo e spiegazione a sinistra, il modulo a destra),
    /// con le note e il server sotto.
    private var wideLayout: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        BCWLogo(size: 40)
                        Text("Better ClasseViVa")
                            .font(.m3(16, weight: 500))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .accessibilityElement(children: .combine)
                    wideCopies
                    Spacer(minLength: 0)
                    LoginArt(wide: true)
                        .frame(height: 150)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(spacing: 24) {
                    if showsModePicker {
                        SegmentedButtons(selection: $mode, options: [(Mode.classeviva, "Classeviva", nil), (Mode.bcw, "Account BCW", nil)],
                                         height: 48)
                    }
                    if currentMode == .bcw {
                        cloudForm
                    } else {
                        classevivaForm
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(48)
            .background(Theme.surfaceContainer, in: .rect(cornerRadius: Theme.radii.xli, style: .continuous))

            wideLegal
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: 1040)
        .padding(40)
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
        // Un tocco nello spazio vuoto chiude la tastiera (campi e pulsanti hanno i loro tocchi).
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { focused = nil }
        }
    }

    /// Titolo e spiegazione dei due moduli, uno sopra l'altro: occupano sempre lo spazio del più
    /// lungo, così cambiando Classeviva/Account BCW la card non cambia altezza.
    @ViewBuilder
    private var wideCopies: some View {
        if linkingFirst {
            wideCopy(title: title,
                     text: "Abbina il tuo primo account Classeviva: con il tuo account BCW entrerai in tutti gli account abbinati, su ogni dispositivo.",
                     note: footerText(for: .classeviva))
        } else {
            ZStack(alignment: .topLeading) {
                ForEach([Mode.classeviva, .bcw], id: \.self) { mode in
                    wideCopy(title: mode == .bcw ? (registering ? "Crea un account BCW" : "Accedi con un account BCW")
                             : "Accedi con Classeviva",
                             text: footerText(for: mode))
                        .opacity(mode == currentMode ? 1 : 0)
                        .accessibilityHidden(mode != currentMode)
                }
            }
        }
    }

    private func wideCopy(title: String, text: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.m3(36, weight: 500, rounded: true))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(.m3(16))
                .foregroundStyle(Theme.secondaryInk)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(.m3(14))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    /// Note sotto la card: affiliazione, account BCW e server.
    private var wideLegal: some View {
        HStack(spacing: 24) {
            Text("BCW non è affiliata a Gruppo Spaggiari Parma.")
            if linkingFirst, let username = model.cloud?.user.username {
                Text("Account BCW: \(username)")
            }
            Spacer(minLength: 0)
            if currentMode == .bcw || linkingFirst {
                serverLine
            }
        }
        .font(.m3(12))
        .foregroundStyle(Theme.secondaryInk)
    }

    private var serverLine: some View {
        HStack(spacing: 6) {
            Icon("cloud", size: 16)
            Text("Server BCW: \(BCWServer.host)")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("·")
            Button("Modifica") { editingServer = true }
                .buttonStyle(LinkButtonStyle())
        }
    }

    /// Spiegazione di un modulo (note del telefono, titolo della card dell'iPad).
    private func footerText(for mode: Mode) -> String {
        if mode == .bcw {
            return "Con un account BCW entri in tutti i tuoi account Classeviva abbinati e ritrovi impostazioni e orario su ogni dispositivo. Le credenziali di Classeviva sono salvate cifrate sul server di BCW."
        } else if model.isCloud {
            return "Usa le credenziali di Classeviva. Il server di BCW le verifica e le salva cifrate nel tuo account BCW."
        }
        return "Usa le stesse credenziali di Classeviva. Restano solo su questo dispositivo, nel Portachiavi, e vengono inviate esclusivamente ai server di Classeviva."
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

    /// Intestazione: logo (con la barra sotto la scritta) e titolo uno sopra l'altro, con le forme che
    /// ruotano; con la tastiera aperta logo piccolo con la barra a destra e titolo su una riga. È la stessa
    /// vista nelle due disposizioni (`AnyLayout`), così il logo si rimpicciolisce e la barra si sposta con
    /// la molla invece di sparire e ricomparire in dissolvenza (prima andava a scatti). Il logo è disegnato
    /// sempre a 64 punti e rimpicciolito (`ScaledLogo`): un testo che cambia misura non si anima con
    /// continuità.
    ///
    /// Titoli lunghi: sotto il logo vanno a capo, centrati; accanto al logo piccolo, se non stanno su una
    /// riga, vanno a capo allineati a sinistra e il blocco è centrato sul logo. Un titolo che sta su una
    /// riga resta a misura piena (`fixedSize`): durante la molla, con il logo ancora grande, andava a capo
    /// o veniva troncato per un attimo.
    private var header: some View {
        let font = Typography.platformFont(size: 16, weight: 500)
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        let fitsBesideLogo = titleWidth <= headerWidth - ScaledLogo.sideWidth(scale: Self.compactLogoScale) - 14
        let fitsBelowLogo = titleWidth <= headerWidth
        let oneLine = compact ? fitsBesideLogo : fitsBelowLogo
        let layout = compact ? AnyLayout(HStackLayout(alignment: .capCenter, spacing: 14)) : AnyLayout(VStackLayout(spacing: 10))
        let showsArt = !compact && !isAddingAccount && !cloudOnly
        return layout {
            ScaledLogo(scale: compact ? Self.compactLogoScale : 1, stacked: !compact)
            Text(title)
                .font(.m3(16, weight: 500))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(compact ? .leading : .center)
                .lineLimit(oneLine ? 1 : 3)
                .fixedSize(horizontal: oneLine, vertical: true)
                // Su una riga centrato sulle maiuscole del logo, poi 2 punti più in basso: a misura
                // sembrava alto, accanto alla scritta pesante e alla barra (segnalato dall'utente). Su più
                // righe il blocco intero sta al centro delle maiuscole.
                .alignmentGuide(.capCenter) { dimensions in
                    oneLine ? dimensions[.firstTextBaseline] - font.capHeight / 2 - 2 : dimensions.height / 2
                }
                // Il titolo non scorre da una posizione all'altra (passava sopra il logo e la barra): sparisce
                // subito dove era e ricompare nel posto nuovo quando logo e barra sono quasi fermi, come la
                // dissolvenza in sequenza di Material 3 (`fadeThrough`).
                .id(compact)
                .transition(.asymmetric(insertion: .opacity.animation(Motion.effects.delay(0.22)),
                                        removal: .opacity.animation(Motion.effectsFast)))
        }
        .frame(maxWidth: .infinity, minHeight: showsArt ? 200 : 0, alignment: compact ? .leading : .center)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { headerWidth = $0 }
        .padding(.top, compact ? 8 : 0)
        .background {
            if showsArt { LoginArt().transition(.opacity) }
        }
        .accessibilityElement(children: .combine)
    }

    /// Il logo accanto al titolo, con la tastiera aperta: 30 punti invece di 64.
    private static let compactLogoScale: CGFloat = 30 / 64

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
            Text(footerText(for: mode))
            if !isAddingAccount {
                Text("BCW non è affiliata a Gruppo Spaggiari Parma.")
            }
            if mode == .bcw || linkingFirst {
                serverLine
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
        .m3Detents([.medium, .large])
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
struct LoginField<Content: View>: View {
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

/// Il logo di 64 punti rimpicciolito di `scale` (dall'angolo in alto a sinistra), con la misura che
/// occupa rimpicciolita anche lei. Scala e misura si animano insieme (`ScaledLayout`). La guida
/// `capCenter` è il centro delle maiuscole della scritta, rimpicciolito.
private struct ScaledLogo: View {
    let scale: CGFloat
    /// La barra sotto la scritta (altrimenti a destra), come `BCWLogo(stacked:)`.
    var stacked = false

    var body: some View {
        let caps = Typography.platformFont(size: 64, weight: 800, rounded: true).capHeight
        ScaledLayout(scale: scale) {
            BCWLogo(size: 64, stacked: stacked)
                .alignmentGuide(.capCenter) { $0[.firstTextBaseline] - caps / 2 }
                .scaleEffect(scale, anchor: .topLeading)
        }
    }

    /// Larghezza del logo con la barra a destra (scritta, spazio di 0,42 e barra di 1,1 volte la misura).
    static func sideWidth(scale: CGFloat) -> CGFloat {
        sideWidth64 * scale
    }

    /// Con l'arrotondamento scelto in Aspetto (cambia di poco la larghezza della scritta).
    private static var sideWidth64: CGFloat {
        let font = Typography.ctFont(size: 64, weight: 800, rond: ThemeStore.shared.rond)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): -0.64,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "BCW", attributes: attributes))
        return ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 64 * (0.42 + 1.1)
    }
}

/// Occupa la misura del figlio moltiplicata per `scale` (il figlio si rimpicciolisce da sé con
/// `scaleEffect`) e ne riporta le guide verticali alla stessa scala.
private struct ScaledLayout: Layout {
    var scale: CGFloat

    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard let child = subviews.first else { return nil }
        return bounds.minY + child.dimensions(in: .unspecified)[guide] * scale
    }
}

/// Forme di Material 3 Expressive che ruotano lentamente dietro al logo (nella card larga
/// dell'iPad più grandi, in basso a sinistra, come la versione web).
private struct LoginArt: View {
    var wide = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || ThemeStore.shared.motion == .reduced)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let mid = proxy.size.width / 2
                ZStack(alignment: .topLeading) {
                    MaterialShape(.softBurst)
                        .fill(Theme.primaryContainer)
                        .frame(width: wide ? 128 : 96, height: wide ? 128 : 96)
                        .rotationEffect(.degrees(t / 40 * 360))
                        .offset(x: wide ? 0 : mid - 190, y: wide ? 18 : 4)
                    MaterialShape(.cookie9Sided)
                        .fill(Theme.tertiaryContainer)
                        .frame(width: wide ? 92 : 76, height: wide ? 92 : 76)
                        .rotationEffect(.degrees(-t / 32 * 360))
                        .offset(x: wide ? 150 : mid + 112, y: wide ? 54 : 92)
                    MaterialShape(.pill)
                        .fill(Theme.secondaryContainer)
                        .frame(width: wide ? 52 : 44, height: wide ? 52 : 44)
                        .rotationEffect(.degrees(t / 24 * 360))
                        .offset(x: wide ? 118 : mid + 64, y: wide ? 0 : 6)
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

struct ProfileChoiceSheet: View {
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
