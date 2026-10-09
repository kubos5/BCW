import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            GradeSettingsSection()
            NotificationSettingsSection()
            DashboardSettingsSection()
            AppearanceSettingsSection()
            DataSettingsSection()
            AboutSettingsSection()
        }
        .themedList()
        .contentMargins(.bottom, Theme.bottomInset - 24, for: .scrollContent)
        .screenTitle("Impostazioni")
    }
}

// MARK: - Sezioni (condivise con la finestra Impostazioni di macOS)

struct GradeSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences

        Section {
            Picker("Calcolo della media", selection: $preferences.averageMode) {
                ForEach(AverageMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Usa i pesi dei voti", isOn: $preferences.weightedAverage)
            Stepper(value: $preferences.targetAverage, in: 4...10, step: 0.25) {
                LabeledContent("Media obiettivo", value: GradeFormat.short(preferences.targetAverage))
            }
        } header: {
            Text("Voti")
        } footer: {
            Text("I voti blu, annullati o \"non fa media\" sono sempre esclusi. I pesi sono quelli impostati dai docenti su Classeviva.")
        }
        .listRowBackground(Theme.surface)
    }
}

struct NotificationSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var preferences = model.preferences

        Section {
            Toggle("Promemoria compiti e verifiche", isOn: $preferences.homeworkReminders)
                .onChange(of: preferences.homeworkReminders) { _, enabled in
                    Task {
                        if enabled {
                            let granted = await Reminders.requestAuthorization()
                            if !granted {
                                notificationsDenied = true
                                model.preferences.homeworkReminders = false
                            }
                        }
                        await model.rescheduleReminders()
                    }
                }
                .notificationsDeniedAlert(isPresented: $notificationsDenied)
            if preferences.homeworkReminders {
                Picker("Orario", selection: $preferences.reminderHour) {
                    ForEach(14...22, id: \.self) { Text("\($0):00").tag($0) }
                }
                .onChange(of: preferences.reminderHour) { Task { await model.rescheduleReminders() } }
            }
        } header: {
            Text("Notifiche")
        } footer: {
            Text("Ricevi una notifica la sera prima di ogni compito o verifica. I compiti segnati come fatti vengono saltati.")
        }
        .listRowBackground(Theme.surface)
    }
}

private extension View {
    func notificationsDeniedAlert(isPresented: Binding<Bool>) -> some View {
        alert("Notifiche disattivate", isPresented: isPresented) {
            Button(Platform.isMac ? "Apri Impostazioni di Sistema" : "Apri Impostazioni") {
                Platform.openNotificationSettings()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(Platform.isMac
                 ? "Per ricevere i promemoria consenti le notifiche a BCW in Impostazioni di Sistema › Notifiche."
                 : "Per ricevere i promemoria consenti le notifiche a BCW nelle Impostazioni di iOS.")
        }
    }
}

struct DashboardSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences

        Section {
            Picker("Vista", selection: $preferences.dashboardMode) {
                ForEach(DashboardMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            Toggle("Mostra \"Nei prossimi giorni\"", isOn: $preferences.showUpcomingDays)
            // Su macOS il titolo sta nella barra della finestra, dove entra sempre per intero.
            if !Platform.isMac {
                Picker("Abbrevia il titolo", selection: $preferences.titleAbbreviation) {
                    ForEach(TitleAbbreviation.allCases) { Text($0.title).tag($0) }
                }
            }
        } header: {
            Text("Dashboard")
        } footer: {
            if Platform.isMac {
                Text("La vista Calendario mostra il mese intero accanto al giorno scelto; la vista Lista la sola settimana.")
            } else {
                Text("Il titolo abbreviato mostra la data in forma breve (es. \"Gio 1 ott\"). In automatico si abbrevia solo se il nome completo non entra.")
            }
        }
        .listRowBackground(Theme.surface)
    }
}

struct AppearanceSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences

        Section("Aspetto e sicurezza") {
            Picker("Tema", selection: $preferences.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Blocca con \(BiometricLock.biometryName)", isOn: $preferences.useBiometrics)
        }
        .listRowBackground(Theme.surface)
    }
}

struct DataSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Dati") {
            Button("Aggiorna tutto", systemImage: "arrow.clockwise") {
                Task { await model.refreshAll() }
            }
            Button("Azzera compiti segnati come fatti", systemImage: "checklist.unchecked") {
                model.preferences.completedHomework = []
            }
        }
        .listRowBackground(Theme.surface)
    }
}

struct AboutSettingsSection: View {
    var body: some View {
        Section {
            LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            Link(destination: URL(string: "https://web.spaggiari.eu")!) {
                Label("Apri Classeviva sul web", systemImage: "safari")
            }
        } header: {
            Text("Informazioni")
        } footer: {
            Text("BCW (Better ClasseViVa) è un client non ufficiale e non è affiliato a Gruppo Spaggiari Parma S.p.A. Le credenziali sono salvate solo nel Portachiavi di questo dispositivo e inviate esclusivamente ai server di Classeviva.")
        }
        .listRowBackground(Theme.surface)
    }
}

#if os(macOS)
/// Finestra Impostazioni di macOS (⌘,): le stesse sezioni di iOS, divise in schede.
struct MacSettingsView: View {
    enum Pane: Hashable { case general, grades, dashboard, notifications, accounts }
    @State private var pane: Pane = .general

    var body: some View {
        TabView(selection: $pane) {
            Tab("Generale", systemImage: "gearshape", value: Pane.general) {
                settingsForm {
                    AppearanceSettingsSection()
                    DataSettingsSection()
                    AboutSettingsSection()
                }
            }
            Tab("Voti", systemImage: "graduationcap", value: .grades) {
                settingsForm { GradeSettingsSection() }
            }
            Tab("Dashboard", systemImage: "calendar.day.timeline.left", value: .dashboard) {
                settingsForm { DashboardSettingsSection() }
            }
            Tab("Notifiche", systemImage: "bell.badge", value: .notifications) {
                settingsForm { NotificationSettingsSection() }
            }
            Tab("Account", systemImage: "person.2", value: .accounts) {
                AccountsSettingsPane()
            }
        }
        .frame(width: 540)
        .frame(minHeight: 300)
    }

    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            .themedList()
            .scrollDisabled(false)
            .frame(minHeight: 300, idealHeight: 420)
    }
}

/// Elenco degli account salvati, nella finestra Impostazioni.
private struct AccountsSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(MacNavigation.self) private var nav

    var body: some View {
        Form {
            Section {
                ForEach(model.accounts) { account in
                    let isActive = !model.isDemo && account.id == model.activeAccountID
                    HStack {
                        AccountRow(account: account, isActive: isActive)
                        if !isActive {
                            Button("Usa") { withAnimation { model.switchAccount(to: account.id) } }
                        }
                        Button("Rimuovi", systemImage: "minus.circle", role: .destructive) {
                            withAnimation { model.removeAccount(account.id) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Rimuovi l'account e le sue credenziali da questo Mac")
                    }
                }
                if model.accounts.isEmpty {
                    Text(model.isDemo ? "Stai usando la modalità demo." : "Nessun account salvato.")
                        .foregroundStyle(Theme.secondaryInk)
                }
            } header: {
                Text("Account salvati")
            } footer: {
                Text("Le credenziali restano solo nel Portachiavi di questo Mac.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Aggiungi account…", systemImage: "person.crop.circle.badge.plus") {
                    nav.addingAccount = true
                }
                .disabled(model.phase != .signedIn)
                if !model.isDemo {
                    Button("Prova la demo", systemImage: "sparkles") {
                        withAnimation { model.startDemo() }
                    }
                    .disabled(model.phase != .signedIn)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .formStyle(.grouped)
        .themedList()
        .frame(minHeight: 300, idealHeight: 420)
    }
}
#endif

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    @State private var addingAccount = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(model.card?.initials ?? String(model.displayName.prefix(1)))
                        .font(.numeral(34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(Theme.accent.gradient, in: .circle)
                    Text(model.displayName)
                        .font(.title2.weight(.semibold))
                    if let classDescription = model.classDescription {
                        Text(classDescription.sentenceCased)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            AccountsSection { addingAccount = true }

            if let card = model.card {
                Section("Profilo") {
                    LabeledContent("Codice utente", value: card.ident)
                    LabeledContent("Tipo di account", value: card.userTypeDescription)
                    if let birth = card.birthDate {
                        LabeledContent("Data di nascita", value: birth.shortDayWithYear)
                    }
                    if let fiscal = card.fiscalCode?.nilIfEmpty {
                        LabeledContent("Codice fiscale", value: fiscal)
                            .textSelection(.enabled)
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Scuola") {
                    if let school = card.schoolDescription {
                        LabeledContent("Istituto", value: school)
                    }
                    if let city = card.schoolCity?.nilIfEmpty {
                        LabeledContent("Città", value: "\(city.nameCased)\(card.schoolProvince.map { " (\($0))" } ?? "")")
                    }
                    if let code = card.miurSchoolCode?.nilIfEmpty {
                        LabeledContent("Codice meccanografico", value: code)
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                // Stesso colore d'accento degli altri pulsanti; il ruolo distruttivo resta nel dialogo.
                Button(model.isDemo ? "Esci dalla demo" : "Esci da questo account",
                       systemImage: "rectangle.portrait.and.arrow.right") {
                    confirmSignOut = true
                }
                .foregroundStyle(Theme.accent)
                // Agganciato al pulsante: il dialogo compare accanto ad esso.
                .confirmationDialog(signOutTitle, isPresented: $confirmSignOut, titleVisibility: .visible) {
                    Button("Esci", role: .destructive) { model.signOut() }
                }
            } footer: {
                Text(signOutFooter)
            }
            .listRowBackground(Theme.surface)
        }
        #if os(macOS)
        .formStyle(.grouped)
        .themedList()
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .themedBackground()
        #else
        .themedList()
        .contentMargins(.bottom, Theme.bottomInset - 24, for: .scrollContent)
        #endif
        .screenTitle("Account")
        .inlineTitleDisplay()
        .sheet(isPresented: $addingAccount) {
            NavigationStack {
                LoginView(isAddingAccount: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla", systemImage: "xmark") { addingAccount = false }
                        }
                    }
            }
            .sheetFrame(width: 480, height: 600)
        }
    }

    private var signOutTitle: String {
        model.isDemo ? "Vuoi uscire dalla demo?" : "Vuoi uscire da \(model.displayName)?"
    }

    private var signOutFooter: String {
        if model.isDemo { return model.demoExitMessage }
        return model.accounts.count > 1
            ? "Le credenziali di questo account verranno rimosse e passerai a un altro account salvato."
            : "Uscendo, le credenziali verranno rimosse da questo dispositivo."
    }
}

/// Sezione "Account" della pagina Account: account salvati, aggiunta di un account e demo.
/// È anche il contenuto del popup per cambiare account (`AccountSwitcherSheet`).
struct AccountsSection: View {
    @Environment(AppModel.self) private var model
    /// Nel popup il titolo è già nella barra: l'intestazione della sezione si ripeterebbe.
    var showsHeader = true
    let addAccount: () -> Void

    var body: some View {
        Section {
            ForEach(model.accounts) { account in
                Button {
                    withAnimation { model.switchAccount(to: account.id) }
                } label: {
                    AccountRow(account: account,
                               isActive: !model.isDemo && account.id == model.activeAccountID)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Rimuovi", systemImage: "trash", role: .destructive) {
                        withAnimation { model.removeAccount(account.id) }
                    }
                }
                .contextMenu {
                    Button("Rimuovi", systemImage: "trash", role: .destructive) {
                        withAnimation { model.removeAccount(account.id) }
                    }
                }
            }
            Button("Aggiungi account", systemImage: "person.crop.circle.badge.plus", action: addAccount)
            if !model.isDemo {
                // Uscendo dalla demo si torna a questo account.
                Button("Prova la demo", systemImage: "sparkles") {
                    withAnimation { model.startDemo() }
                }
            }
        } header: {
            if showsHeader { Text("Account") }
        } footer: {
            Text(model.accounts.count > 1
                 ? (Platform.isMac
                    ? "Fai clic su un account per passare ad esso. Fai clic con il tasto destro per rimuoverlo."
                    : "Tocca un account per passare ad esso. Scorri verso sinistra per rimuoverlo.")
                 : "Puoi aggiungere altri account Classeviva (ad esempio quelli di fratelli o sorelle) e passare dall'uno all'altro.")
        }
        .listRowBackground(Theme.surface)
    }
}

struct AccountRow: View {
    let account: SavedAccount
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(account.initials)
                .font(.numeral(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.subjectColor(StableID.make(account.id)).gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(account.school ?? account.credentials.username)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isActive {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .contentShape(.rect)
    }
}
