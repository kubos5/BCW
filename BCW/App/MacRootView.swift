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
    /// Incrementato per chiudere la ricerca: `MacRootView` toglie prima il focus al campo e
    /// mostra la pagina solo quando il campo si è richiuso (vedi `closeSearch`).
    var searchEndRequest = 0

    private static let sectionKey = "macSection"

    /// Torna a una sezione chiudendo la ricerca.
    func show(_ section: MacSection) {
        self.section = section
        if isSearching { searchEndRequest += 1 }
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
    /// Le pagine a due colonne (`SplitColumns`) si affiancano da 780 punti in su.
    @State private var detailHasTwoColumns = true
    /// La riserva non ci sta nella barra: è ridotta al minimo (vedi `SearchFieldCompaction`).
    @State private var searchReserveIsTight = false

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
            .onGeometryChange(for: Bool.self) { $0.size.width >= 780 } action: { detailHasTwoColumns = $0 }
        }
        // Ricerca generale: campo sempre visibile a destra nella barra della finestra.
        // Selezionandolo si apre la pagina di ricerca; si chiude uscendo dal campo vuoto
        // o scegliendo una sezione nella barra laterale.
        .searchable(text: $nav.searchQuery, placement: .toolbar, prompt: SearchView.prompt)
        .searchFocused($searchFocused)
        // Con una colonna il campo resta esteso solo se, oltre a lui, nella barra resta vuoto
        // almeno un quinto della sua larghezza: lo tiene da parte `macWindowActions`.
        .environment(\.searchReserveWidth, searchReserveWidth)
        .background {
            SearchFieldCompaction(twoColumns: detailHasTwoColumns, isSearching: nav.isSearching,
                                  reserveIsTight: $searchReserveIsTight)
        }
        .onChange(of: searchFocused) { _, focused in
            if focused {
                nav.isSearching = true
            } else if nav.searchQuery.isEmpty {
                closeSearch()
            }
        }
        .onChange(of: nav.searchEndRequest) {
            nav.searchQuery = ""
            if searchFocused {
                searchFocused = false  // chiude la ricerca da `onChange(of: searchFocused)`
            } else {
                closeSearch()
            }
        }
        .onChange(of: nav.searchQuery) { _, query in
            if !query.isEmpty { nav.isSearching = true }
        }
        .onChange(of: nav.searchFocusRequest) { searchFocused = true }
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
            Text(model.isDemo ? model.demoExitMessage
                 : "Le credenziali di questo account verranno rimosse da questo Mac.")
        }
    }

    /// Torna dalla pagina di ricerca a quella della sezione, ma solo dopo che il campo si è
    /// richiuso: se la barra della pagina arriva mentre il campo è ancora aperto, AppKit la
    /// impagina con il campo largo e non la ricalcola più (Aggiorna nel menu di overflow, lente
    /// in mezzo alla barra). Vale per Esc, per il clic altrove e per la scelta di una sezione.
    private func closeSearch() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if !searchFocused && nav.searchQuery.isEmpty { nav.isSearching = false }
        }
    }

    /// Spazio di riserva per il campo di ricerca (vedi `SearchFieldCompaction`).
    /// Larghezza della riserva per il campo di ricerca, `nil` se non serve.
    private var searchReserveWidth: CGFloat? {
        guard !detailHasTwoColumns, !nav.isSearching else { return nil }
        return searchReserveIsTight ? SearchFieldCompaction.tightReserveWidth : SearchFieldCompaction.reserveWidth
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
        .macWindowActions()
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

extension EnvironmentValues {
    /// Larghezza dello spazio di riserva del campo di ricerca nella barra, `nil` se non serve.
    @Entry var searchReserveWidth: CGFloat? = nil
}

extension View {
    /// Azioni a destra nella barra della finestra: distanziatore e Aggiorna, con la ricerca
    /// generale subito dopo. Vanno sulla pagina principale di ogni sezione e su ogni pagina
    /// aperta da un'altra (`NavigationLink`, `navigationDestination`): la pagina aperta
    /// sostituisce la barra, e senza di esse Aggiorna sparirebbe e la ricerca finirebbe
    /// accanto al titolo. Agganciate alla finestra o alla pila restano sì, ma accanto al titolo.
    func macWindowActions() -> some View {
        modifier(MacWindowActions())
    }
}

private struct MacWindowActions: ViewModifier {
    @Environment(\.searchReserveWidth) private var searchReserveWidth

    func body(content: Content) -> some View {
        content.toolbar {
            // Riserva invisibile per il campo di ricerca (`SearchFieldCompaction`): prima del
            // distanziatore, cioè subito dopo titolo e navigazione, dove si confonde con lo spazio
            // vuoto. Tra i pulsanti di destra lascerebbe un buco prima del campo.
            // L'identificativo cambia con la larghezza: la barra reinserisce l'elemento invece di
            // ridimensionarlo (che fa male).
            if let width = searchReserveWidth {
                ToolbarItem(id: "\(SearchFieldCompaction.reserveID)-\(Int(width))") {
                    Color.clear
                        .frame(width: width, height: 1)
                        .accessibilityHidden(true)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .automatic) {
                RefreshButton()
            }
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

/// Con poco spazio nella barra il campo di ricerca diventa un'icona, che si espande quando la
/// si preme (come in Note). `NSSearchToolbarItem` lo fa quando gli spetta meno di una soglia
/// minima, di serie 160 punti: prima il campo si stringe, e alla larghezza minima della finestra
/// resterebbe sempre intero. La soglia si alza con la proprietà non pubblica
/// `minimumWidthForSearchFieldRepresentation` (se un giorno sparisse, il campo si stringe e basta):
/// - con le pagine a due colonne a 260 punti;
/// - con una colonna alla larghezza piena del campo, con in più una riserva invisibile nella barra
///   larga un quinto del campo (`macWindowActions`): il campo è esteso solo se è pieno e oltre a lui
///   resta vuoto almeno un quinto della sua larghezza, altrimenti diventa icona. La riserva ha la
///   priorità più bassa: se non c'è posto finisce lei fuori dalla barra, non un pulsante;
/// - durante la ricerca la soglia torna quella di serie e la riserva non c'è.
/// Forzare l'icona con `prefersCompactRepresentation` o con una soglia enorme non va: la barra
/// lascia al campo tutto il suo spazio e la lente finisce in mezzo (verificato).
struct SearchFieldCompaction: NSViewRepresentable {
    let twoColumns: Bool
    let isSearching: Bool
    @Binding var reserveIsTight: Bool

    static let reserveID = "riserva-ricerca"
    /// Riserva ridotta, quando quella intera non ci sta: in quel caso il campo è comunque un'icona
    /// (lo spazio è molto meno della sua larghezza). Se la riserva intera uscisse dalla barra,
    /// lo spazio avanzato finirebbe tra Aggiorna e l'icona invece che dopo il titolo (verificato).
    static let tightReserveWidth: CGFloat = 1
    /// Un quinto della larghezza piena del campo (325 punti su macOS 26-27).
    static let reserveWidth: CGFloat = 65

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.twoColumns = twoColumns
        context.coordinator.isSearching = isSearching
        context.coordinator.reserveIsTight = $reserveIsTight
        context.coordinator.scheduleUpdate()
    }

    final class Coordinator {
        weak var view: NSView?
        var twoColumns = true
        var isSearching = false
        var reserveIsTight: Binding<Bool>?
        private weak var observedToolbar: NSToolbar?
        private var observers: [NSObjectProtocol] = []

        private static let minimumKey = "minimumWidthForSearchFieldRepresentation"
        /// Soglia di serie di AppKit.
        private static let systemMinimum: CGFloat = 160
        /// Larghezza del campo ridotto a icona.
        private static let iconWidth: CGFloat = 36


        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        func scheduleUpdate() {
            DispatchQueue.main.async { [weak self] in
                self?.observe()
                self?.update()
            }
        }

        /// Gli elementi della barra cambiano con la pagina: la riserva va ritrovata ogni volta.
        private func observe() {
            guard let toolbar = view?.window?.toolbar, toolbar !== observedToolbar else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            observedToolbar = toolbar
            observers = [
                NotificationCenter.default.addObserver(forName: NSToolbar.willAddItemNotification, object: toolbar,
                                                       queue: .main) { [weak self] _ in self?.scheduleUpdate() },
            ]
        }

        /// Riserva intera che non ci sta (è finita fuori dalla barra) → ridotta; riserva ridotta e
        /// abbastanza spazio vuoto per quella intera → di nuovo intera. Le due condizioni non si
        /// sovrappongono, quindi non si alternano.
        private func updateReserveSize(_ reserve: NSToolbarItem, toolbar: NSToolbar) {
            guard let tight = reserveIsTight else { return }
            let view = reserve.value(forKey: "view") as? NSView
            let isVisible = view?.window != nil && view?.isHiddenOrHasHiddenAncestor == false
            if !tight.wrappedValue {
                if !isVisible { tight.wrappedValue = true }
            } else if isVisible, let free = Self.freeSpace(in: toolbar),
                      // 16 punti di margine: lo spazio misurato comprende piccoli scarti fissi
                      // (es. tra barra laterale e contenuto) che la riserva non può usare.
                      free >= SearchFieldCompaction.reserveWidth - SearchFieldCompaction.tightReserveWidth + 16 {
                tight.wrappedValue = false
            }
        }

        /// Spazio vuoto nella barra: la somma degli spazi tra gli elementi visibili oltre la
        /// distanza normale tra due elementi (8 punti).
        private static func freeSpace(in toolbar: NSToolbar) -> CGFloat? {
            var frames: [CGRect] = []
            for item in toolbar.items {
                let view = (item as? NSSearchToolbarItem)?.searchField ?? (item.value(forKey: "view") as? NSView)
                guard let view, view.window != nil, !view.isHiddenOrHasHiddenAncestor else { continue }
                let frame = view.convert(view.bounds, to: nil)
                if frame.width > 0 { frames.append(frame) }
            }
            frames.sort { $0.minX < $1.minX }
            guard frames.count > 1 else { return nil }
            return zip(frames, frames.dropFirst()).reduce(0) { $0 + max(0, $1.1.minX - $1.0.maxX - 8) }
        }

        private func update() {
            guard let toolbar = view?.window?.toolbar else { return }
            for item in toolbar.items where item.itemIdentifier.rawValue.contains(SearchFieldCompaction.reserveID) {
                if item.visibilityPriority != .low { item.visibilityPriority = .low }
                updateReserveSize(item, toolbar: toolbar)
            }
            guard let search = toolbar.items.compactMap({ $0 as? NSSearchToolbarItem }).first,
                  search.responds(to: NSSelectorFromString("setMinimumWidthForSearchFieldRepresentation:")) else { return }
            let fullWidth = search.maxSize.width > 0 ? search.maxSize.width : 325
            // Un punto sotto la larghezza piena: con la soglia uguale alla larghezza massima
            // l'icona terrebbe lo spazio del campo (verificato).
            let minimum: CGFloat = isSearching ? Self.systemMinimum : (twoColumns ? 260 : fullWidth - 1)
            if (search.value(forKey: Self.minimumKey) as? CGFloat) != minimum {
                search.setValue(minimum, forKey: Self.minimumKey)
            }
        }
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
            AccountMenuItems { nav.addingAccount = true }
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
            // La demo non è un account: si apre da qui anche con un account collegato.
            Button("Prova la demo") { model.startDemo() }
                .disabled(!signedIn || model.isDemo)
            Divider()
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
