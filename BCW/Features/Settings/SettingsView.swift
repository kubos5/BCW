import SwiftUI

/// Sottopagine delle Impostazioni.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, grades, dashboard, timetable, notifications, accounts
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Generale"
        case .appearance: "Aspetto"
        case .grades: "Voti"
        case .dashboard: "Dashboard"
        case .timetable: "Orario"
        case .notifications: "Notifiche"
        case .accounts: "Account"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .appearance: "palette"
        case .grades: "graduationCap"
        case .dashboard: "dashboard"
        case .timetable: "timetable"
        case .notifications: "bellActive"
        case .accounts: "users"
        }
    }

    var tint: Color {
        switch self {
        case .general: Theme.secondaryInk
        case .appearance: Theme.tertiary
        case .grades: Theme.subject(1)
        case .dashboard: Theme.primary
        case .timetable: Theme.subject(3)
        case .notifications: Theme.fair
        case .accounts: Theme.subject(5)
        }
    }

    /// Contenuto della sottopagina: elenchi segmentati uno sotto l'altro.
    @ViewBuilder
    var content: some View {
        switch self {
        case .general:
            SecuritySettingsSection()
            DataSettingsSection()
            AboutSettingsSection()
        case .appearance: AppearanceSettingsSection()
        case .grades: GradeSettingsSection()
        case .dashboard: DashboardSettingsSection()
        case .timetable: TimetableSettingsSection()
        case .notifications: NotificationSettingsSection()
        case .accounts: AccountsSettingsPane()
        }
    }
}

/// Impostazioni: un elenco di sottopagine.
struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ListGroup {
                    link(.general)
                    link(.appearance)
                }
                ListGroup {
                    link(.grades)
                    link(.dashboard)
                    link(.timetable)
                    link(.notifications)
                }
                ListGroup {
                    NavigationLink {
                        AccountView()
                    } label: {
                        NavigationRow(SettingsPane.accounts.title, icon: SettingsPane.accounts.icon,
                                      tint: SettingsPane.accounts.tint)
                    }
                    .buttonStyle(.listRow)
                }
            }
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        .tracksPageScroll()
        .themedBackground()
        .pageChrome("Impostazioni", style: .inline)
    }

    private func link(_ pane: SettingsPane) -> some View {
        NavigationLink {
            SettingsPaneView(pane: pane)
        } label: {
            NavigationRow(pane.title, icon: pane.icon, tint: pane.tint)
        }
        .buttonStyle(.listRow)
    }
}

/// Una sottopagina delle Impostazioni su iPhone.
struct SettingsPaneView: View {
    let pane: SettingsPane

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                pane.content
            }
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        .tracksPageScroll()
        .themedBackground()
        .pageChrome(pane.title, style: .inline)
    }
}

// MARK: - Sezioni

struct SecuritySettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ListGroup("Sicurezza", footer: "BCW si blocca all'apertura e quando torni dopo averla lasciata in secondo piano.") {
            ToggleRow("Blocca con \(BiometricLock.biometryName)", icon: "lock",
                      isOn: Bindable(model.preferences).useBiometrics)
        }
    }
}

struct GradeSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences

        ListGroup("Voti", footer: "I voti blu, annullati o \"non fa media\" sono sempre esclusi. I pesi sono quelli impostati dai docenti su Classeviva.") {
            SelectRow("Calcolo della media", selection: $preferences.averageMode,
                      options: AverageMode.allCases.map { ($0, $0.title, nil) })
            ToggleRow("Usa i pesi dei voti", isOn: $preferences.weightedAverage)
            StepperRow(title: "Media obiettivo", value: $preferences.targetAverage, range: 4...10, step: 0.25) {
                GradeFormat.short($0)
            }
        }
    }
}

struct NotificationSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var preferences = model.preferences

        ListGroup("Promemoria", footer: "Ricevi una notifica la sera prima di ogni compito o verifica. I compiti segnati come fatti vengono saltati.") {
            ToggleRow("Promemoria compiti e verifiche", icon: "bell", isOn: $preferences.homeworkReminders)
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
            if preferences.homeworkReminders {
                SelectRow("Orario", icon: "clock", selection: $preferences.reminderHour,
                          options: (14...22).map { ($0, "\($0):00", nil) })
                    .onChange(of: preferences.reminderHour) { Task { await model.rescheduleReminders() } }
            }
            ShareLink(item: AgendaCalendarFile(events: model.agenda.filter { $0.begin >= Date().startOfDay },
                                               reminderHour: preferences.homeworkReminders ? preferences.reminderHour : nil),
                      preview: SharePreview("Agenda di BCW")) {
                ListRow("Esporta l'agenda nel Calendario", titleColor: Theme.primary, leading: {
                    FormIcon("calendarPlus", color: Theme.primary)
                }, trailing: { EmptyView() })
            }
            .buttonStyle(.listRow)
        }
        .m3Dialog("Notifiche disattivate", isPresented: $notificationsDenied,
                  message: "Per ricevere i promemoria consenti le notifiche a BCW nelle Impostazioni di iOS.") {
            [.cancel("OK"), DialogAction(title: "Apri Impostazioni", style: .strong) {
                Platform.openNotificationSettings()
            }]
        }

        ListGroup("Novità", footer: "Una notifica per ogni novità trovata aggiornando i dati, anche con BCW chiusa: iOS sceglie quando aggiornare in background, in base a quanto usi l'app, quindi le notifiche possono arrivare con un po' di ritardo.") {
            ForEach(NewsKind.allCases) { kind in
                ToggleRow(kind.title, icon: kind.icon, isOn: Binding {
                    preferences.newsNotifications.contains(kind)
                } set: { isOn in
                    if isOn { enableNews(kind) } else { preferences.newsNotifications.remove(kind) }
                })
            }
        }
        .onChange(of: preferences.newsNotifications) {
            NewsNotifications.scheduleBackgroundRefresh(model: model)
        }
    }

    /// Attiva un tipo di novità chiedendo prima il permesso per le notifiche.
    private func enableNews(_ kind: NewsKind) {
        model.preferences.newsNotifications.insert(kind)
        Task {
            if !(await Reminders.requestAuthorization()) {
                notificationsDenied = true
                model.preferences.newsNotifications.remove(kind)
            }
        }
    }
}

struct DashboardSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences

        ListGroup("Dashboard", footer: "Il titolo abbreviato mostra la data in forma breve (es. \"Gio 1 ott\"). In automatico si abbrevia solo se il nome completo non entra.") {
            SelectRow("Vista", selection: $preferences.dashboardMode,
                      options: DashboardMode.allCases.map { ($0, $0.title, $0.icon) })
            ToggleRow("Mostra \"Nei prossimi giorni\"", isOn: $preferences.showUpcomingDays)
            SelectRow("Abbrevia il titolo", selection: $preferences.titleAbbreviation,
                      options: TitleAbbreviation.allCases.map { ($0, $0.title, nil) })
        }
    }
}

struct DataSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ListGroup("Dati") {
            ButtonRow("Aggiorna tutto", icon: "refresh") {
                Task { await model.refreshAll() }
            }
            ButtonRow("Azzera compiti segnati come fatti", icon: "listUnchecked") {
                model.preferences.completedHomework = []
            }
        }
    }
}

struct AboutSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        ListGroup("Informazioni", footer: model.isCloud
                  ? "BCW (Better ClasseViVa) è un client non ufficiale e non è affiliato a Gruppo Spaggiari Parma S.p.A. Le credenziali degli account abbinati sono salvate cifrate nel tuo account BCW e nel Portachiavi di questo dispositivo, e inviate ai server di Classeviva per accedere."
                  : "BCW (Better ClasseViVa) è un client non ufficiale e non è affiliato a Gruppo Spaggiari Parma S.p.A. Le credenziali sono salvate solo nel Portachiavi di questo dispositivo e inviate esclusivamente ai server di Classeviva.") {
            ValueRow("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            Button {
                openURL(URL(string: "https://web.spaggiari.eu")!)
            } label: {
                ListRow("Apri Classeviva sul web") {
                    FormIcon("compass")
                } trailing: {
                    Icon("externalLink", size: 18)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
            }
            .buttonStyle(.listRow)
        }
    }
}

// MARK: - Aspetto

/// Aspetto: tema, colore d'accento (colori dinamici di Material 3), forme, movimento, caratteri e
/// Liquid Glass. Le stesse impostazioni della versione web.
struct AppearanceSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var theme = ThemeStore.shared

        ListGroup("Tema") {
            ThemePreview()
            SelectRow("Tema", icon: "sun", selection: $preferences.appearance,
                      options: AppearanceMode.allCases.map { ($0, $0.title, nil) })
        }

        ListGroup("Interfaccia", footer: "Con Liquid Glass la barra di navigazione, la barra delle schede e i pulsanti dei menu sono quelli di sistema, in vetro. Senza, tutta l'interfaccia è in Material 3 Expressive, come la versione web di BCW.") {
            ToggleRow("Liquid Glass", subtitle: theme.liquidGlass ? "Sì" : "No", icon: "sparkles", isOn: $theme.liquidGlass)
        }

        ListGroup("Colore d'accento", footer: "Tutti i colori di BCW (pulsanti, superfici, schede) sono generati dal colore scelto con i colori dinamici di Material 3, nel tema chiaro e in quello scuro. I colori di materie, voti e assenze non cambiano.") {
            AccentPicker()
            SelectRow("Stile dei colori", subtitle: theme.colorStyle.subtitle, icon: "colorStyle", selection: $theme.colorStyle,
                      options: ColorStyle.allCases.map { ($0, $0.title, nil) })
            SelectRow("Contrasto", icon: "contrast", selection: $theme.contrast,
                      options: ContrastLevel.allCases.map { ($0, $0.title, nil) })
        }
        // Con "Tema dell'app" l'icona segue l'accento: cambia (con l'avviso di iOS) uscendo dalla pagina.
        .onAppear { AppIconController.shared.holdThemeChanges(true) }
        .onDisappear { AppIconController.shared.holdThemeChanges(false) }

        ListGroup {
            AppIconSettingsLink()
        }

        ListGroup("Forme e movimento", footer: "Espressive: animazioni a molla con un piccolo rimbalzo, come in Material 3 Expressive. Standard: senza rimbalzo. Ridotte: brevi e senza movimenti ampi. I caratteri arrotondati usano l'asse ROND di Google Sans Flex.") {
            SelectRow("Angoli", icon: "corners", selection: $theme.corners,
                      options: CornerStyle.allCases.map { ($0, $0.title, nil) })
            SelectRow("Animazioni", icon: "motion", selection: $theme.motion,
                      options: MotionStyle.allCases.map { ($0, $0.title, nil) })
            SelectRow("Caratteri arrotondati", icon: "textStyle", selection: $theme.roundedText,
                      options: RoundedText.allCases.map { ($0, $0.title, nil) })
            if !theme.isDefault {
                ButtonRow("Ripristina l'aspetto di BCW", icon: "refresh") {
                    withAnimation(Motion.effects) { theme.reset() }
                }
            }
        }
    }
}

/// Piccola anteprima dei componenti con i colori e le forme scelti.
private struct ThemePreview: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Shaped(shape: .cookie9Sided, fill: Theme.primaryContainer, size: 56) {
                Icon("palette")
                    .foregroundStyle(Theme.onPrimaryContainer)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Anteprima")
                    .font(.m3(16, weight: 550, rounded: true))
                    .foregroundStyle(Theme.ink)
                Text("Pulsanti, schede e forme")
                    .font(.m3(13))
                    .foregroundStyle(Theme.secondaryInk)
                FlowLayout(spacing: 8) {
                    Text("Primario").fixedSize()
                        .modifier(PreviewButton(background: Theme.primary, foreground: Theme.onPrimary, radius: 16))
                    Text("Tonale").fixedSize()
                        .modifier(PreviewButton(background: Theme.secondaryContainer, foreground: Theme.onSecondaryContainer, radius: 16))
                    Text("Terziario").fixedSize()
                        .modifier(PreviewButton(background: Theme.tertiaryContainer, foreground: Theme.onTertiaryContainer, radius: Theme.radii.s))
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    tone(Theme.primary)
                    tone(Theme.secondaryContainer)
                }
                GridRow {
                    tone(Theme.tertiaryContainer)
                    tone(Theme.surfaceContainerHighest)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityHidden(true)
    }

    private func tone(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Theme.ink.opacity(0.12), lineWidth: 1))
            .frame(width: 16, height: 16)
    }

    private struct PreviewButton: ViewModifier {
        let background: Color
        let foreground: Color
        let radius: CGFloat

        func body(content: Content) -> some View {
            content
                .font(.m3(14, weight: 600))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(background, in: .rect(cornerRadius: radius, style: .continuous))
        }
    }
}

/// Campioni dei colori d'accento (come quelli di Android: in alto il primario, in basso secondario
/// e terziario) e un campione per scegliere un colore qualsiasi.
private struct AccentPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var customColor: Color = .red
    @State private var pickingColor = false

    var body: some View {
        let theme = ThemeStore.shared
        let accent = ThemeStore.normalize(theme.accentColor) ?? defaultAccent
        let isPreset = accentPresets.contains { $0.hex == accent }
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 8)], spacing: 12) {
                ForEach(accentPresets, id: \.hex) { preset in
                    Button {
                        Haptics.selection()
                        withAnimation(Motion.spatial) { theme.accentColor = preset.hex }
                    } label: {
                        AccentSwatch(colors: theme.swatch(preset.hex, dark: colorScheme == .dark),
                                     selected: preset.hex == accent, icon: preset.hex == accent ? "check" : nil)
                    }
                    .buttonStyle(SwatchButtonStyle())
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(preset.hex == accent ? .isSelected : [])
                    .help(preset.name)
                }
                // Un colore qualsiasi: il selettore dei colori di sistema in un foglio (un
                // `ColorPicker` invisibile sopra il campione non si apriva più).
                Button { pickingColor = true } label: {
                    AccentSwatch(colors: isPreset ? nil : theme.swatch(accent, dark: colorScheme == .dark),
                                 selected: !isPreset, icon: isPreset ? "colorize" : "check")
                }
                .buttonStyle(SwatchButtonStyle())
                .frame(width: 44, height: 44)
                .accessibilityLabel("Scegli un colore qualsiasi")
                .sheet(isPresented: $pickingColor) {
                    SystemColorPicker(color: $customColor)
                        .ignoresSafeArea()
                }
            }
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(platformColor: PlatformColor(hex: Int(accent.dropFirst(), radix: 16) ?? 0)))
                    .overlay(Circle().strokeBorder(Theme.ink.opacity(0.15), lineWidth: 1))
                    .frame(width: 16, height: 16)
                Text(accent.uppercased())
                    .font(.numeral(14))
                    .foregroundStyle(Theme.secondaryInk)
                Spacer()
                if accent != defaultAccent {
                    Button {
                        withAnimation(Motion.spatial) { theme.accentColor = defaultAccent }
                    } label: {
                        Label { Text("Colore di BCW") } icon: { Icon("refresh") }
                    }
                    .buttonStyle(.m3(.text, size: .xs))
                }
            }
            .frame(minHeight: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .onAppear { customColor = Color(platformColor: PlatformColor(hex: Int(accent.dropFirst(), radix: 16) ?? 0)) }
        .onChange(of: customColor) { _, color in
            guard let hex = color.hexString, hex != ThemeStore.normalize(theme.accentColor) else { return }
            theme.accentColor = hex
        }
    }
}

private struct AccentSwatch: View {
    /// Primario, secondario, terziario; `nil` = arcobaleno (colore qualsiasi).
    let colors: [Color]?
    let selected: Bool
    let icon: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: selected ? Theme.radii.l : 22, style: .continuous)
        ZStack {
            if let colors, colors.count == 3 {
                VStack(spacing: 0) {
                    colors[0]
                    HStack(spacing: 0) {
                        colors[1]
                        colors[2]
                    }
                }
            } else {
                AngularGradient(colors: (0..<9).map { Theme.subject([0, 3, 6, 1, 9, 5, 2, 4, 0][$0]) }, center: .center)
            }
            if let icon {
                Icon(icon, size: 18)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, height: 26)
                    .background(Theme.surfaceContainerLowest, in: .circle)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.ink.opacity(0.12), lineWidth: 1))
        .padding(3)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Theme.radii.l + 3, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: 2)
            }
        }
        .padding(-3)
        .animation(Motion.spatial, value: selected)
    }
}

private struct SwatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.spatialFast, value: configuration.isPressed)
    }
}

extension Color {
    /// Colore in esadecimale (`#rrggbb`), nello spazio sRGB.
    var hexString: String? {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func channel(_ v: CGFloat) -> String { String(format: "%02x", Int((min(max(v, 0), 1) * 255).rounded())) }
        return "#" + channel(r) + channel(g) + channel(b)
    }
}

// MARK: - Account

/// Elenco degli account salvati (sottopagina Account).
struct AccountsSettingsPane: View {
    @Environment(AppModel.self) private var model
    @State private var addingAccount = false

    var body: some View {
        AccountsSection {
            addingAccount = true
        }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet { addingAccount = false }
        }
        ClassevivaLinksSection()
        CloudAccountSection()
        if model.isDemo {
            ListGroup {
                ListRow(model.demoExitMessage)
            }
        }
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    @State private var addingAccount = false
    @State private var unlinking: SavedAccount?
    @State private var unlinkError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Avatar(initials: model.card?.initials ?? String(model.displayName.prefix(1)), size: 96, shape: .cookie12Sided)
                    Text(model.displayName)
                        .font(.m3(28, weight: 500, rounded: true))
                        .foregroundStyle(Theme.ink)
                    if let classDescription = model.classDescription {
                        Text(classDescription.sentenceCased)
                            .font(.m3(16))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 4)

                AccountsSection { addingAccount = true }

                if let card = model.card {
                    ListGroup("Profilo") {
                        ValueRow("Codice utente", value: card.ident)
                        ValueRow("Tipo di account", value: card.userTypeDescription)
                        if let birth = card.birthDate {
                            ValueRow("Data di nascita", value: birth.shortDayWithYear)
                        }
                        if let fiscal = card.fiscalCode?.nilIfEmpty {
                            ValueRow("Codice fiscale", value: fiscal)
                                .textSelection(.enabled)
                        }
                    }

                    ListGroup("Scuola") {
                        if let school = card.schoolDescription {
                            ValueRow("Istituto", value: school)
                        }
                        if let city = card.schoolCity?.nilIfEmpty {
                            ValueRow("Città", value: "\(city.nameCased)\(card.schoolProvince.map { " (\($0))" } ?? "")")
                        }
                        if let code = card.miurSchoolCode?.nilIfEmpty {
                            ValueRow("Codice meccanografico", value: code)
                        }
                    }
                }

                ClassevivaLinksSection()
                CloudAccountSection()

                if model.isCloud && !model.isDemo {
                    if let account = model.activeAccount {
                        ListGroup(footer: "\(account.name) non sarà più disponibile con l'account BCW \(model.cloud?.user.username ?? "") e il suo orario verrà eliminato dal server.") {
                            ButtonRow("Scollega da BCW", icon: "minusCircle", destructive: true) {
                                unlinking = account
                            }
                        }
                    }
                } else {
                    ListGroup(footer: signOutFooter) {
                        ButtonRow(model.isDemo ? "Esci dalla demo" : "Esci da questo account", icon: "logout", destructive: true) {
                            confirmSignOut = true
                        }
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .tracksPageScroll()
        .themedBackground()
        .pageChrome("Account", style: .inline)
        .m3Dialog(signOutTitle, isPresented: $confirmSignOut,
                  message: model.isDemo ? model.demoExitMessage : "Le credenziali di questo account verranno rimosse da questo dispositivo.") {
            [.cancel(), DialogAction(title: "Esci", style: .destructive) { model.signOut() }]
        }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet { addingAccount = false }
        }
        .m3Dialog("Scollegare \(unlinking?.name ?? "l'account")?",
                  isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }),
                  message: "\(unlinking?.name ?? "L'account") non sarà più disponibile con l'account BCW \(model.cloud?.user.username ?? ""), su nessun dispositivo, e il suo orario verrà eliminato dal server. Il registro su Classeviva non cambia.") {
            let account = unlinking
            return [.cancel(), DialogAction(title: "Scollega", style: .destructive) {
                guard let account else { return }
                Task {
                    do {
                        try await model.unlinkAccount(account.id)
                    } catch {
                        unlinkError = error.localizedDescription
                    }
                }
            }]
        }
        .m3Dialog("Scollegamento non riuscito", isPresented: Binding(get: { unlinkError != nil }, set: { if !$0 { unlinkError = nil } }),
                  message: unlinkError) {
            [.cancel("OK")]
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

/// Foglio per aggiungere un account (la schermata di accesso, con Annulla). Con l'account BCW
/// l'account viene abbinato sul server.
struct AddAccountSheet: View {
    @Environment(AppModel.self) private var model
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            LoginView(isAddingAccount: true)
                .sheetChrome(model.isCloud ? "Abbina account" : "Aggiungi account", leading: .cancel(action: dismiss))
        }
        .m3Sheet()
    }
}

/// Sezione "Account" della pagina Account: account salvati (o, con l'account BCW, quelli
/// abbinati), aggiunta di un account e demo. È anche il contenuto del popup per cambiare
/// account (`AccountSwitcherSheet`).
struct AccountsSection: View {
    @Environment(AppModel.self) private var model
    /// Nel popup il titolo è già nella barra: l'intestazione della sezione si ripeterebbe.
    var showsHeader = true
    let addAccount: () -> Void
    @State private var removing: SavedAccount?
    @State private var removalError: String?

    var body: some View {
        let cloud = model.isCloud
        let removeLabel = cloud ? "Scollega" : "Rimuovi"
        ListGroup(showsHeader ? (cloud ? "Account Classeviva abbinati" : "Account") : nil, footer: footer) {
            ForEach(model.accounts) { account in
                let isActive = !model.isDemo && account.id == model.activeAccountID
                HStack(spacing: 0) {
                    Button {
                        withAnimation { model.switchAccount(to: account.id) }
                    } label: {
                        AccountRow(account: account, isActive: isActive)
                    }
                    .buttonStyle(.listRow)
                    IconButton(cloud ? "minusCircle" : "trash", label: removeLabel) { removing = account }
                        .padding(.trailing, 8)
                        .help(cloud ? "Scollega l'account dal tuo account BCW" : "Rimuovi l'account e le sue credenziali da questo dispositivo")
                }
                .contextMenu {
                    Button(role: .destructive) { removing = account } label: {
                        Label(removeLabel, icon: cloud ? "minusCircle" : "trash")
                    }
                }
            }
            ButtonRow(cloud ? "Abbina un account Classeviva" : "Aggiungi account", icon: "userPlus", action: addAccount)
            if !model.isDemo {
                // Uscendo dalla demo si torna a questo account.
                ButtonRow("Prova la demo", icon: "sparkles") {
                    withAnimation { model.startDemo() }
                }
            }
        }
        .m3Dialog("\(removeLabel) \(removing?.name ?? "l'account")?",
                  isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                  message: cloud
                  ? "\(removing?.name ?? "L'account") non sarà più disponibile con l'account BCW \(model.cloud?.user.username ?? ""), su nessun dispositivo, e il suo orario verrà eliminato dal server. Il registro su Classeviva non cambia."
                  : "Le credenziali di questo account verranno rimosse da questo dispositivo.") {
            let account = removing
            return [.cancel(), DialogAction(title: removeLabel, style: .destructive) {
                guard let account else { return }
                if cloud {
                    Task {
                        do {
                            try await model.unlinkAccount(account.id)
                        } catch {
                            removalError = error.localizedDescription
                        }
                    }
                } else {
                    withAnimation { model.removeAccount(account.id) }
                }
            }]
        }
        .m3Dialog("Scollegamento non riuscito", isPresented: Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } }),
                  message: removalError) {
            [.cancel("OK")]
        }
    }

    private var footer: String {
        let tap = "Tocca un account per passare ad esso."
        if model.isCloud {
            let base = "Gli account Classeviva abbinati all'account BCW \(model.cloud?.user.username ?? ""): li ritrovi accedendo con l'account BCW su qualsiasi dispositivo."
            return model.accounts.count > 1 ? "\(base) \(tap)" : base
        }
        return model.accounts.count > 1
            ? "\(tap) Usa il cestino per rimuoverlo."
            : "Puoi aggiungere altri account Classeviva (ad esempio quelli di fratelli o sorelle) e passare dall'uno all'altro."
    }
}

struct AccountRow: View {
    let account: SavedAccount
    let isActive: Bool

    var body: some View {
        ListRow(account.name, subtitle: account.school ?? account.credentials.username) {
            Avatar(initials: account.initials, size: 40, shape: .cookie9Sided,
                   tint: Theme.subjectColor(StableID.make(account.id)))
        } trailing: {
            if isActive {
                Icon("check")
                    .foregroundStyle(Theme.primary)
            }
        }
    }
}

/// Selettore dei colori di sistema (`UIColorPickerViewController`), senza trasparenza.
private struct SystemColorPicker: UIViewControllerRepresentable {
    @Binding var color: Color

    func makeCoordinator() -> Coordinator { Coordinator(color: $color) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(color)
        picker.title = "Colore d'accento"
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        let color: Binding<Color>
        init(color: Binding<Color>) { self.color = color }

        func colorPickerViewController(_ picker: UIColorPickerViewController, didSelect color: UIColor,
                                       continuously: Bool) {
            self.color.wrappedValue = Color(uiColor: color)
        }
    }
}
