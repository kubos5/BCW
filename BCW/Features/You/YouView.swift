import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appNavigation) private var navigation
    @Environment(\.windowClass) private var windowClass
    @State private var switchingAccount = false
    @State private var showingSettings = false
    @State private var showingAccount = false
    /// Sezione aperta nella pila (finestra dell'iPad tornata stretta con la sezione aperta).
    @State private var openedSection: AppSection?
    /// iPad largo con la pagina larga almeno 792 punti: profilo accanto alle statistiche.
    @State private var isSplit = false
    #if DEBUG
    /// Per le prove: `-BCWOpenPage bacheca` apre una pagina di Tu all'avvio (vedi `debugPage`).
    @State private var debugPage: String?
    #endif

    var body: some View {
        PlatformNavigationStack {
            ScrollView {
                Group {
                    if isSplit {
                        wideLayout
                    } else if windowClass == .regular {
                        regularColumnLayout
                    } else {
                        phoneLayout
                    }
                }
                .pagePadding()
                .padding(.bottom, Theme.bottomInset)
            }
            // Sull'iPad largo, da 792 punti di pagina: profilo accanto alle statistiche.
            .widthAtLeast(SplitMetrics.threshold, isOn: $isSplit)
            .tracksPageScroll()
            .scrollsToTopOnReselect()
            .themedBackground()
            .refreshable { await model.refreshAll() }
            .pageChrome("Tu", style: .inline) {
                // Sull'iPad largo senza Liquid Glass l'ingranaggio è nella barra superiore.
                if ThemeStore.shared.liquidGlass || windowClass == .compact {
                    BarButton("Impostazioni", icon: "gear") { showingSettings = true }
                }
            }
            .navigationDestination(isPresented: $showingSettings) { SettingsView() }
            .navigationDestination(isPresented: $showingAccount) { AccountView() }
            .navigationDestination(item: $openedSection) { section in section.destination }
            // Impostazioni dalla barra superiore o dalla barra laterale dell'iPad.
            .onChange(of: navigation?.openSettings ?? false, initial: true) { _, open in
                guard open else { return }
                navigation?.openSettings = false
                showingSettings = true
            }
            .onChange(of: navigation?.pendingSection, initial: true) { _, section in
                guard let section else { return }
                navigation?.pendingSection = nil
                openedSection = section
            }
            #if DEBUG
            .navigationDestination(item: $debugPage) { page in debugDestination(page) }
            .task {
                if debugPage == nil, let page = UserDefaults.standard.string(forKey: "BCWOpenPage") {
                    // Sull'iPad largo le sezioni si scelgono nella barra di navigazione (`MainTabView`).
                    if windowClass == .regular && AppSection(debugKey: page) != nil { return }
                    // Sull'iPad largo un pannello delle Impostazioni si apre accanto al loro elenco.
                    if windowClass == .regular, page.hasPrefix("impostazioni-"),
                       let pane = SettingsPane(rawValue: String(page.dropFirst(13))) {
                        navigation?.settingsPane = pane
                        showingSettings = true
                        return
                    }
                    if page == "cambia-account" { switchingAccount = true } else { debugPage = page }
                }
            }
            #endif
            .sheet(isPresented: $switchingAccount) {
                AccountSwitcherSheet()
            }
        }
    }

    private var profile: some View {
        ProfileHero {
            showingAccount = true
        } switchAccount: {
            switchingAccount = true
        }
    }

    /// Le sezioni nei loro gruppi (Comunicazioni, Valutazioni, Frequenza, Didattica).
    private var groups: some View {
        ForEach(AppSection.Group.allCases) { group in
            ListGroup(group.title) {
                ForEach(group.sections) { section in
                    MenuRow(section: section, subtitle: section.subtitle(model), badge: section.badge(model))
                }
            }
        }
    }

    /// Telefono (e iPad stretto): tutto in una colonna.
    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 28) {
            profile
            stats
            attention
            groups
            YouFooter()
        }
    }

    /// iPad largo in colonna: come il telefono, con i gruppi in due colonne.
    private var regularColumnLayout: some View {
        VStack(alignment: .leading, spacing: 28) {
            profile
            stats
            attention
            AdaptiveColumns(minimum: 300, spacing: 24) { groups }
            YouFooter()
        }
    }

    /// iPad largo (come la versione web): il profilo accanto a statistiche e "Da vedere", sotto i
    /// gruppi in colonne.
    private var wideLayout: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 28) {
                profile
                    .padding(.top, 24)
                    .frame(width: 320)
                VStack(alignment: .leading, spacing: 20) {
                    stats
                    attention
                }
                .frame(maxWidth: .infinity)
            }
            AdaptiveColumns(minimum: 320, spacing: 24) { groups }
            YouFooter()
        }
    }

    /// Media e frequenza in una griglia collegata (angoli ampi solo all'esterno, come le liste
    /// segmentate). Assenze, ritardi e uscite aprono la pagina delle assenze.
    private var stats: some View {
        let absences = model.absences.filter { $0.kind == .absence }.count
        let lates = model.absences.filter { $0.kind == .late || $0.kind == .shortLate }.count
        let exits = model.absences.filter { $0.kind == .earlyExit }.count
        let average = model.gradeBook.average()
        // Larghezze e altezze uguali: due colonne della stessa misura, riquadri alti uguali.
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                StatTile(title: "Media generale", value: GradeFormat.average(average), icon: "graduationCap",
                         tint: Theme.gradeColor(value: average), shape: .cookie9Sided, corners: .topLeading)
                    .frame(height: 84)
                statLink(StatTile(title: "Assenze", value: "\(absences)", icon: "userX", tint: Theme.poor,
                                  shape: .clover4Leaf, corners: .topTrailing))
            }
            HStack(spacing: 2) {
                statLink(StatTile(title: "Ritardi", value: "\(lates)", icon: "clock", tint: Theme.fair,
                                  shape: .sunny, corners: .bottomLeading))
                statLink(StatTile(title: "Uscite", value: "\(exits)", icon: "doorOpen", tint: Theme.neutral,
                                  shape: .cookie6Sided, corners: .bottomTrailing))
            }
        }
    }

    @ViewBuilder
    private func statLink(_ tile: StatTile) -> some View {
        // Sull'iPad largo le assenze sono una destinazione della barra di navigazione.
        if let navigation, navigation.sectionsAreDestinations {
            Button { navigation.select(.absences) } label: {
                tile.frame(height: 84)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        } else {
            NavigationLink { AbsencesView() } label: {
                tile.frame(height: 84)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    /// Ciò che aspetta l'utente (comunicazioni e note da leggere, assenze da giustificare), in
    /// evidenza nel contenitore secondario. Non c'è se è tutto a posto.
    @ViewBuilder
    private var attention: some View {
        let notices = model.unreadNoticesCount
        let notes = model.notes.filter { !$0.isRead }.count
        let absences = model.unjustifiedAbsences.count
        if notices + notes + absences > 0 {
            ListGroup("Da vedere", background: Theme.secondaryContainer) {
                if notices > 0 {
                    MenuRow(section: .noticeboard,
                            title: notices == 1 ? "1 comunicazione da leggere" : "\(notices) comunicazioni da leggere")
                }
                if notes > 0 {
                    MenuRow(section: .notes, title: notes == 1 ? "1 nota da leggere" : "\(notes) note da leggere")
                }
                if absences > 0 {
                    MenuRow(section: .absences,
                            title: absences == 1 ? "1 assenza da giustificare" : "\(absences) assenze da giustificare")
                }
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    private func debugDestination(_ page: String) -> some View {
        switch page {
        case "bacheca": NoticeboardView()
        case "note": NotesView()
        case "scrutini": ReportsView()
        case "anni": PreviousYearView()
        case "assenze": AbsencesView()
        case "materiale": DidacticsView()
        case "lezioni": LessonsView()
        case "agenda": AgendaListView()
        case "materie": SubjectsView()
        case "libri": SchoolbooksView()
        case "calendario": SchoolCalendarView()
        case "account": AccountView()
        case "icona": AppIconSettingsView()
        case let pane where pane.hasPrefix("impostazioni-"):
            if let found = SettingsPane.allCases.first(where: { $0.rawValue == pane.dropFirst(13) }) {
                SettingsPaneView(pane: found)
            }
        default: SettingsView()
        }
    }
    #endif
}

/// Profilo in cima a Tu, come la pagina dell'account Google: l'avatar grande in un biscotto che
/// ruota piano al tocco, nome, scuola e classe al centro, poi i pulsanti per l'account.
struct ProfileHero: View {
    @Environment(AppModel.self) private var model
    let manage: () -> Void
    let switchAccount: () -> Void
    @State private var turns = 0.0

    var body: some View {
        VStack(spacing: 16) {
            Button {
                Haptics.soft()
                withAnimation(Motion.spatialSlow) { turns += 1 }
            } label: {
                Avatar(initials: model.card?.initials ?? String(model.displayName.prefix(1)), size: 112,
                       shape: .cookie12Sided, rotation: .degrees(turns * 60))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(model.displayName)
                    .font(.m3(28, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                if let school = model.card?.schoolDescription {
                    Text([school, model.card?.schoolCity?.nameCased].compactMap { $0 }.joined(separator: " · "))
                        .font(.m3(14))
                        .foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.center)
                }
            }
            HStack(spacing: 8) {
                Button(action: manage) {
                    Label { Text("Gestisci account") } icon: { Icon("manageAccounts") }
                }
                .buttonStyle(.m3(.tonal, size: .s))
                Button(action: switchAccount) {
                    Label { Text(model.accounts.count > 1 ? "Cambia" : "Aggiungi") } icon: {
                        Icon(model.accounts.count > 1 ? "switchAccount" : "userPlus")
                    }
                }
                .buttonStyle(.m3(.outlined, size: .s))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// Piè di pagina di "Tu": logo, aggiornamento, demo.
struct YouFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            BCWLogo(size: 15)
                .padding(.bottom, 2)
            Text("Better ClasseViVa")
                .font(.m3(13, weight: 600))
            if let updated = model.lastUpdated {
                Text("Aggiornato alle \(updated.time)")
            }
            if model.isDemo {
                Text("Modalità demo: i dati sono di esempio.")
            }
        }
        .font(.m3(12))
        .foregroundStyle(Theme.secondaryInk)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// Voce di una sezione (titolo, icona e colore da `AppSection`): apre la pagina nella pila di Tu,
/// oppure, sull'iPad largo, sceglie la sezione nella barra di navigazione.
private struct MenuRow: View {
    let section: AppSection
    var title: String?
    var subtitle: String?
    var badge: Int = 0
    @Environment(\.appNavigation) private var navigation

    var body: some View {
        let row = NavigationRow(title ?? section.title, subtitle: subtitle, icon: section.icon, tint: section.tint,
                                badge: badge)
        if let navigation, navigation.sectionsAreDestinations {
            Button { navigation.select(section) } label: { row }
                .buttonStyle(.listRow)
        } else {
            NavigationLink { section.destination } label: { row }
                .buttonStyle(.listRow)
        }
    }
}
