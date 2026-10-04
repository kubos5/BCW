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
            VStack(spacing: 28) {
                header
                    .padding(.top, isAddingAccount ? 24 : 60)

                VStack(spacing: 0) {
                    field(symbol: "person", placeholder: "Codice utente o email") {
                        TextField("Codice utente o email", text: $username)
                            .textContentType(.username)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                            .focused($focused, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }
                    }
                    Divider().overlay(Theme.separator).padding(.leading, 48)
                    field(symbol: "key", placeholder: "Password") {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.plain)
                            .focused($focused, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                    }
                }
                .background(Theme.surface, in: .rect(cornerRadius: Theme.corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.poor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Button(action: submit) {
                    ZStack {
                        Text("Accedi").opacity(isLoading ? 0 : 1)
                        if isLoading { ProgressView().tint(.white) }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(username.isEmpty || password.isEmpty || isLoading)

                if !isAddingAccount {
                    Button {
                        model.startDemo()
                    } label: {
                        Text("Prova la demo")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .glassButton()
                    .controlSize(.large)
                }

                footer
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedBackground()
        #if os(macOS)
        // Il logo fa già da titolo: niente titolo di sistema nella barra della finestra.
        .toolbar(removing: .title)
        #endif
        .animation(.snappy, value: errorMessage)
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
            Text("BCW")
                .font(.system(size: 64, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
            Capsule()
                .fill(Theme.accent)
                .frame(width: 56, height: 4)
            Text(isAddingAccount ? "Aggiungi un account" : "Better ClasseViVa")
                .font(.title3.italic())
                .foregroundStyle(Theme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Usa le stesse credenziali di Classeviva. Restano solo su questo dispositivo, nel Portachiavi.")
            Text("BCW non è affiliata a Gruppo Spaggiari Parma.")
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryInk)
        .multilineTextAlignment(.center)
        .padding(.top, 8)
    }

    private func field<Content: View>(symbol: String, placeholder: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 20)
            content()
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
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

private struct ProfileChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let choices: [LoginChoice]
    let onSelect: (LoginChoice) -> Void

    var body: some View {
        NavigationStack {
            List(choices) { choice in
                Button {
                    onSelect(choice)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(choice.name.nameCased)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text(choice.school.nameCased)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .themedList()
            .navigationTitle("Scegli il profilo")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            #endif
            .inlineTitleDisplay()
        }
        .sheetFrame(width: 420, height: 380)
    }
}
