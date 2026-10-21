import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @State private var switchingAccount = false
    @State private var showingSettings = false
    @State private var showingAccount = false
    #if DEBUG
    /// Per le prove: `-BCWOpenPage bacheca` apre una pagina di Tu all'avvio (vedi `debugPage`).
    @State private var debugPage: String?
    #endif

    var body: some View {
        PlatformNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ProfileHero {
                        showingAccount = true
                    } switchAccount: {
                        switchingAccount = true
                    }
                    stats
                    attention

                    ListGroup("Comunicazioni") {
                        MenuRow(title: "Bacheca", subtitle: noticeSubtitle, icon: "megaphone",
                                tint: Theme.primary, badge: model.unreadNoticesCount) { NoticeboardView() }
                        MenuRow(title: "Note e annotazioni", subtitle: notesSubtitle,
                                icon: "messageAlert", tint: Theme.poor,
                                badge: model.notes.filter { !$0.isRead }.count) { NotesView() }
                    }

                    ListGroup("Valutazioni") {
                        MenuRow(title: "Scrutini e pagelle", subtitle: "Documenti di valutazione",
                                icon: "fileSearch", tint: Theme.neutral) { ReportsView() }
                        MenuRow(title: "Anni precedenti", subtitle: "Pagelle e archivio degli anni passati",
                                icon: "history", tint: Theme.secondaryInk) { PreviousYearView() }
                    }

                    ListGroup("Frequenza") {
                        MenuRow(title: "Assenze e ritardi", subtitle: absenceSubtitle,
                                icon: "userClock", tint: Theme.fair,
                                badge: model.unjustifiedAbsences.count) { AbsencesView() }
                    }

                    ListGroup("Didattica") {
                        MenuRow(title: "Materiale didattico", subtitle: "File condivisi dai docenti",
                                icon: "folder", tint: Theme.subject(3)) { DidacticsView() }
                        MenuRow(title: "Registro delle lezioni", subtitle: "Argomenti svolti in classe",
                                icon: "bookText", tint: Theme.subject(1)) { LessonsView() }
                        MenuRow(title: "Agenda completa", subtitle: "Tutti i compiti e le verifiche",
                                icon: "checklist", tint: Theme.subject(5)) { AgendaListView() }
                        MenuRow(title: "Materie e docenti", subtitle: "\(model.subjects.count) materie",
                                icon: "users", tint: Theme.subject(2)) { SubjectsView() }
                        MenuRow(title: "Libri di testo", subtitle: "Adozioni dell'anno in corso",
                                icon: "library", tint: Theme.subject(4)) { SchoolbooksView() }
                        MenuRow(title: "Calendario scolastico", subtitle: "Vacanze e giorni di lezione",
                                icon: "calendarClock", tint: Theme.subject(7)) { SchoolCalendarView() }
                    }

                    YouFooter()
                }
                .pagePadding()
                .padding(.bottom, Theme.bottomInset)
            }
            .tracksPageScroll()
            .scrollsToTopOnReselect()
            .themedBackground()
            .refreshable { await model.refreshAll() }
            .pageChrome("Tu", style: .inline) {
                BarButton("Impostazioni", icon: "gear") { showingSettings = true }
            }
            .navigationDestination(isPresented: $showingSettings) { SettingsView() }
            .navigationDestination(isPresented: $showingAccount) { AccountView() }
            #if DEBUG
            .navigationDestination(item: $debugPage) { page in debugDestination(page) }
            .task {
                if debugPage == nil, let page = UserDefaults.standard.string(forKey: "BCWOpenPage") {
                    if page == "cambia-account" { switchingAccount = true } else { debugPage = page }
                }
            }
            #endif
            .sheet(isPresented: $switchingAccount) {
                AccountSwitcherSheet()
            }
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

    private func statLink(_ tile: StatTile) -> some View {
        NavigationLink { AbsencesView() } label: {
            tile.frame(height: 84)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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
                    MenuRow(title: notices == 1 ? "1 comunicazione da leggere" : "\(notices) comunicazioni da leggere",
                            icon: "megaphone", tint: Theme.primary) { NoticeboardView() }
                }
                if notes > 0 {
                    MenuRow(title: notes == 1 ? "1 nota da leggere" : "\(notes) note da leggere",
                            icon: "messageAlert", tint: Theme.poor) { NotesView() }
                }
                if absences > 0 {
                    MenuRow(title: absences == 1 ? "1 assenza da giustificare" : "\(absences) assenze da giustificare",
                            icon: "userClock", tint: Theme.fair) { AbsencesView() }
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

    private var noticeSubtitle: String {
        let unread = model.unreadNoticesCount
        return unread == 0 ? "Tutto letto" : (unread == 1 ? "1 comunicazione da leggere" : "\(unread) comunicazioni da leggere")
    }

    private var notesSubtitle: String {
        model.notes.isEmpty ? "Nessuna nota" : "\(model.notes.count) in totale"
    }

    private var absenceSubtitle: String {
        let pending = model.unjustifiedAbsences.count
        return pending == 0 ? "Tutto giustificato" : "\(pending) da giustificare"
    }
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

private struct MenuRow<Destination: View>: View {
    let title: String
    var subtitle: String?
    let icon: String
    var tint: Color = Theme.accent
    var badge: Int = 0
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            NavigationRow(title, subtitle: subtitle, icon: icon, tint: tint, badge: badge)
        }
        .buttonStyle(.listRow)
    }
}
