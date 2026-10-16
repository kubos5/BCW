import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// `true` quando si aggiunge un altro account da dentro l'app (presentata come foglio).
    var isAddingAccount = false
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var choices: [LoginChoice] = []
    @FocusState private var focused: Field?

    private enum Field { case username, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 12) {
                    VStack(spacing: 10) {
                        LoginField(icon: "person", focused: focused == .username) {
                            TextField("Codice utente o email", text: $username)
                                .textContentType(.username)
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                #endif
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

                    Button(action: submit) {
                        // L'indicatore è sovrapposto al testo: non cambia l'altezza del pulsante.
                        Text("Accedi")
                            .opacity(isLoading ? 0 : 1)
                            .overlay {
                                if isLoading { LoadingIndicator(size: 24, color: Theme.onPrimary) }
                            }
                    }
                    .buttonStyle(.m3(.filled, size: .m, wide: true))
                    .disabled(username.isEmpty || password.isEmpty || isLoading)

                    if !isAddingAccount {
                        Button {
                            model.startDemo()
                        } label: {
                            Label { Text("Prova la demo") } icon: { Icon("sparkles") }
                        }
                        .buttonStyle(.m3(.tonal, size: .m, wide: true))
                    }
                }

                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .themedBackground()
        #if os(macOS)
        // Il logo fa già da titolo: niente titolo di sistema nella barra della finestra.
        .toolbar(removing: .title)
        // Senza elementi la finestra non avrebbe una barra degli strumenti e i pulsanti a
        // semaforo starebbero più vicini al bordo che nella finestra principale: un elemento
        // invisibile le dà la stessa barra.
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        // La barra resta (con lei i margini dei pulsanti a semaforo e gli angoli arrotondati della
        // finestra), ma senza sfondo né riga: non si vede.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .animation(Motion.spatial, value: errorMessage)
        .animation(Motion.spatial, value: focused)
        .sheet(isPresented: Binding(get: { !choices.isEmpty }, set: { if !$0 { choices = [] } })) {
            ProfileChoiceSheet(choices: choices) { choice in
                choices = []
                signIn(ident: choice.ident)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            BCWLogo(size: 64)
            Text(isAddingAccount ? "Aggiungi un account" : "Better ClasseViVa")
                .font(.m3(16, weight: 500))
                .foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: isAddingAccount ? 0 : 200)
        .background {
            if !isAddingAccount { LoginArt() }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Usa le stesse credenziali di Classeviva. Restano solo su questo dispositivo, nel Portachiavi, e vengono inviate esclusivamente ai server di Classeviva.")
            Text("BCW non è affiliata a Gruppo Spaggiari Parma.")
        }
        .font(.m3(12))
        .foregroundStyle(Theme.secondaryInk)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

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
        .sheetFrame(width: 420, height: 380)
    }
}
