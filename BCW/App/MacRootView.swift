#if os(macOS)
import SwiftUI

/// Sezioni della barra laterale su macOS: le schede di iOS più le pagine che su iPhone
/// stanno dentro "Tu", così ogni funzione è a un clic di distanza. La ricerca non è una
/// sezione: è il campo sempre visibile nella barra della finestra.
enum MacSection: String, CaseIterable, Identifiable {
    case dashboard, grades, you
    case noticeboard, notes
    case reports, previousYears
    case absences
    case didactics, lessons, agenda, subjects, schoolbooks, schoolCalendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .grades: "Voti"
        case .you: "Tu"
        case .noticeboard: "Bacheca"
        case .notes: "Note e annotazioni"
        case .reports: "Scrutini e pagelle"
        case .previousYears: "Anni precedenti"
        case .absences: "Assenze e ritardi"
        case .didactics: "Materiale didattico"
        case .lessons: "Registro delle lezioni"
        case .agenda: "Agenda completa"
        case .subjects: "Materie e docenti"
        case .schoolbooks: "Libri di testo"
        case .schoolCalendar: "Calendario scolastico"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "calendar.day.timeline.left"
        case .grades: "chart.line.uptrend.xyaxis"
        case .you: "person.crop.circle"
        case .noticeboard: "megaphone"
        case .notes: "exclamationmark.bubble"
        case .reports: "doc.text.magnifyingglass"
        case .previousYears: "clock.arrow.circlepath"
        case .absences: "person.badge.clock"
        case .didactics: "folder"
        case .lessons: "text.book.closed"
        case .agenda: "checklist"
        case .subjects: "person.2"
        case .schoolbooks: "books.vertical"
        case .schoolCalendar: "calendar.badge.clock"
        }
    }

    /// Stessi colori delle righe di "Tu" su iOS.
    var tint: Color {
        switch self {
        case .dashboard, .grades, .you, .noticeboard: Theme.accent
        case .notes: Theme.poor
        case .reports: Theme.neutral
        case .previousYears: Theme.secondaryInk
        case .absences: Theme.fair
        case .didactics: Theme.subjectColor(3)
        case .lessons: Theme.subjectColor(1)
        case .agenda: Theme.subjectColor(5)
        case .subjects: Theme.subjectColor(2)
        case .schoolbooks: Theme.subjectColor(4)
        case .schoolCalendar: Theme.subjectColor(7)
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .dashboard: "1"
        case .grades: "2"
        case .you: "3"
        case .noticeboard: "4"
        case .notes: "5"
        case .absences: "6"
        case .agenda: "7"
        case .didactics: "8"
        case .lessons: "9"
        default: nil
        }
    }

    static let groups: [(title: String?, sections: [MacSection])] = [
        (nil, [.dashboard, .grades, .you]),
        ("Comunicazioni", [.noticeboard, .notes]),
        ("Valutazioni", [.reports, .previousYears]),
        ("Frequenza", [.absences]),
        ("Didattica", [.didactics, .lessons, .agenda, .subjects, .schoolbooks, .schoolCalendar]),
    ]
}

/// Stato della finestra su macOS, condiviso con i comandi della barra dei menu.
@Observable
final class MacNavigation {
    var section: MacSection {
        didSet { UserDefaults.standard.set(section.rawValue, forKey: Self.sectionKey) }
    }
    var addingAccount = false
    var confirmingSignOut = false
    /// Testo della ricerca generale, nel campo della barra della finestra.
    var searchQuery = ""
    /// `true` mentre il dettaglio mostra la pagina di ricerca al posto della sezione.
    var isSearching = false
    /// Incrementato dal comando "Cerca" (⌘F) per mettere il cursore nel campo.
    var searchFocusRequest = 0

    private static let sectionKey = "macSection"

    /// Torna a una sezione chiudendo la ricerca.
    func show(_ section: MacSection) {
        endSearch()
        self.section = section
    }

    func endSearch() {
        isSearching = false
        searchQuery = ""
    }

    init() {
        // L'app riapre l'ultima sezione visitata.
        section = MacSection(rawValue: UserDefaults.standard.string(forKey: Self.sectionKey) ?? "") ?? .dashboard
    }
}

// MARK: - Finestra principale

struct MacRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(MacNavigation.self) private var nav
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var nav = nav

        NavigationSplitView {
            MacSidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            NavigationStack {
                MacDetailView(section: nav.section, isSearching: nav.isSearching)
            }
            // Cambiando sezione (o aprendo la ricerca) si riparte dalla pagina principale.
            .id(nav.isSearching ? "ricerca" : nav.section.rawValue)
        }
        // Ricerca generale: campo sempre visibile a destra nella barra della finestra.
        // Selezionandolo si apre la pagina di ricerca; si chiude uscendo dal campo vuoto
        // o scegliendo una sezione nella barra laterale.
        .searchable(text: $nav.searchQuery, placement: .toolbar, prompt: SearchView.prompt)
        .searchFocused($searchFocused)
        .onChange(of: searchFocused) { _, focused in
            if focused {
                nav.isSearching = true
            } else if nav.searchQuery.isEmpty {
                nav.isSearching = false
            }
        }
        .onChange(of: nav.searchQuery) { _, query in
            if !query.isEmpty { nav.isSearching = true }
        }
        .onChange(of: nav.searchFocusRequest) { searchFocused = true }
        .onChange(of: nav.isSearching) { _, searching in
            if !searching { searchFocused = false }
        }
        .frame(minWidth: 860, minHeight: 580)
        #if DEBUG
        .task { DebugSnapshots.runIfRequested(nav: nav, openSettings: openSettings) }
        #endif
        .sheet(isPresented: $nav.addingAccount) {
            AddAccountSheet()
        }
        .alert(signOutTitle, isPresented: $nav.confirmingSignOut) {
            Button("Esci", role: .destructive) { model.signOut() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(model.isDemo ? "Stai usando la modalità demo."
                 : "Le credenziali di questo account verranno rimosse da questo Mac.")
        }
    }

    private var signOutTitle: String {
        model.isDemo ? "Vuoi uscire dalla demo?" : "Vuoi uscire da \(model.displayName)?"
    }
}

/// Foglio per aggiungere un account, con le dimensioni adatte a macOS.
struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginView(isAddingAccount: true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { dismiss() }
                    }
                }
        }
        .sheetFrame(width: 480, height: 600)
    }
}

private struct MacDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(MacNavigation.self) private var nav
    let section: MacSection
    let isSearching: Bool

    var body: some View {
        @Bindable var nav = nav

        Group {
            if isSearching {
                SearchView(query: $nav.searchQuery)
            } else {
                content
            }
        }
            .toolbar {
                // Il distanziatore spinge a destra le azioni: a sinistra restano titolo e navigazione.
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .automatic) {
                    RefreshButton()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .dashboard: DashboardView()
        case .grades: GradesView()
        case .you: YouView()
        case .noticeboard: NoticeboardView()
        case .notes: NotesView()
        case .reports: ReportsView()
        case .previousYears: PreviousYearView()
        case .absences: AbsencesView()
        case .didactics: DidacticsView()
        case .lessons: LessonsView()
        case .agenda: AgendaListView()
        case .subjects: SubjectsView()
        case .schoolbooks: SchoolbooksView()
        case .schoolCalendar: SchoolCalendarView()
        }
    }
}

/// Su macOS non si trascina per aggiornare: c'è un pulsante (e ⌘R).
struct RefreshButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Task { await model.refreshAll() }
        } label: {
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Label("Aggiorna", systemImage: "arrow.clockwise")
            }
        }
        .disabled(model.isRefreshing)
        .help("Aggiorna i dati da Classeviva (⌘R)")
    }
}

// MARK: - Barra laterale

private struct MacSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(MacNavigation.self) private var nav

    var body: some View {
        // Durante la ricerca nessuna sezione è evidenziata: un clic su qualsiasi voce,
        // anche quella da cui si è partiti, chiude la ricerca.
        List(selection: Binding(get: { nav.isSearching ? nil : nav.section },
                                set: { if let s = $0 { nav.show(s) } })) {
            ForEach(MacSection.groups.indices, id: \.self) { index in
                let group = MacSection.groups[index]
                if let title = group.title {
                    Section(title) { rows(group.sections) }
                } else {
                    Section { rows(group.sections) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarAccountMenu()
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
    }

    private func rows(_ sections: [MacSection]) -> some View {
        ForEach(sections) { section in
            Label(section.title, systemImage: section.symbol)
                .badge(badge(for: section))
                .listItemTint(section.tint)
                .tag(section)
        }
    }

    private func badge(for section: MacSection) -> Int {
        switch section {
        case .noticeboard: model.unreadNoticesCount
        case .notes: model.notes.filter { !$0.isRead }.count
        case .absences: model.unjustifiedAbsences.count
        default: 0
        }
    }
}

/// Account attivo in fondo alla barra laterale: un clic apre il menu per cambiarlo.
private struct SidebarAccountMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(MacNavigation.self) private var nav

    var body: some View {
        Menu {
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
            Button("Aggiungi account…", systemImage: "person.crop.circle.badge.plus") {
                nav.addingAccount = true
            }
            Divider()
            Button("Il tuo profilo", systemImage: "person.crop.circle") { nav.show(.you) }
            SettingsLink {
                Label("Impostazioni…", systemImage: "gearshape")
            }
            Divider()
            Button(model.isDemo ? "Esci dalla demo…" : "Esci da questo account…",
                   systemImage: "rectangle.portrait.and.arrow.right") {
                nav.confirmingSignOut = true
            }
        } label: {
            HStack(spacing: 10) {
                Text(model.card?.initials ?? String(model.displayName.prefix(1)))
                    .font(.numeral(14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.gradient, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk)
            }
            .padding(8)
            .contentShape(.rect(cornerRadius: 12))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
        .help("Cambia account")
    }

    private var subtitle: String {
        if model.isDemo { return "Modalità demo" }
        return model.classDescription?.sentenceCased ?? model.card?.schoolDescription ?? "Classeviva"
    }
}

// MARK: - Comandi della barra dei menu

struct BCWCommands: Commands {
    let model: AppModel
    let nav: MacNavigation

    private var signedIn: Bool { model.phase == .signedIn }

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("Aggiungi account…") { nav.addingAccount = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!signedIn)
        }

        CommandGroup(before: .sidebar) {
            Button("Aggiorna") { Task { await model.refreshAll() } }
                .keyboardShortcut("r")
                .disabled(!signedIn || model.isRefreshing)
            Divider()
        }

        CommandMenu("Vai") {
            Button("Cerca") { nav.searchFocusRequest += 1 }
                .keyboardShortcut("f")
                .disabled(!signedIn)
            Divider()
            ForEach(MacSection.groups.indices, id: \.self) { index in
                if index > 0 { Divider() }
                ForEach(MacSection.groups[index].sections) { section in
                    Button(section.title) { nav.show(section) }
                        .keyboardShortcut(section.shortcut.map { KeyboardShortcut($0) })
                        .disabled(!signedIn)
                }
            }
        }

        CommandMenu("Account") {
            ForEach(model.accounts) { account in
                Toggle(account.name, isOn: Binding(
                    get: { !model.isDemo && account.id == model.activeAccountID },
                    set: { if $0 { withAnimation { model.switchAccount(to: account.id) } } }
                ))
            }
            if !model.accounts.isEmpty { Divider() }
            Button("Il tuo profilo") { nav.show(.you) }
                .disabled(!signedIn)
            Button(model.isDemo ? "Esci dalla demo…" : "Esci da questo account…") {
                nav.confirmingSignOut = true
            }
            .disabled(!signedIn)
        }

        CommandGroup(replacing: .help) {
            Link("Apri Classeviva sul web", destination: URL(string: "https://web.spaggiari.eu")!)
        }
    }
}
#endif
