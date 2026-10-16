import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @State private var switchingAccount = false

    var body: some View {
        iOSBody
    }

    private var iOSBody: some View {
        PlatformNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageLargeTitle()
                        .padding(.bottom, -10)
                    // Profilo e statistiche formano un blocco: stessa distanza che c'è tra le statistiche.
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink {
                            AccountView()
                        } label: {
                            ProfileCard()
                        }
                        .buttonStyle(.pressable(radius: Theme.radii.xl, pressed: Theme.radii.l))
                        stats
                    }

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

                    ListGroup("App") {
                        MenuRow(title: "Impostazioni", subtitle: "Medie, orario, promemoria, backup",
                                icon: "gear", tint: Theme.secondaryInk) { SettingsView() }
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
            .pageChrome("Tu") {
                accountSwitcher
            }
            .sheet(isPresented: $switchingAccount) {
                AccountSwitcherSheet()
            }
        }
    }

    /// Cambio rapido dell'account attivo: apre lo stesso popup della scheda Tu tenuta premuta.
    /// L'icona conta solo gli account veri: la demo non è un account.
    private var accountSwitcher: some View {
        BarButton(model.accounts.count > 1 ? "Cambia account" : "Aggiungi account",
                  icon: model.accounts.count > 1 ? "users" : "userPlus") {
            switchingAccount = true
        }
    }

    var stats: some View {
        let absences = model.absences.filter { $0.kind == .absence }.count
        let lates = model.absences.filter { $0.kind == .late || $0.kind == .shortLate }.count
        let exits = model.absences.filter { $0.kind == .earlyExit }.count
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "Media", value: GradeFormat.average(model.gradeBook.average()),
                         icon: "graduationCap", tint: Theme.gradeColor(value: model.gradeBook.average()), shape: .cookie9Sided)
                StatTile(title: "Assenze", value: "\(absences)", icon: "userX", tint: Theme.poor, shape: .clover4Leaf)
            }
            GridRow {
                StatTile(title: "Ritardi", value: "\(lates)", icon: "clock", tint: Theme.fair, shape: .sunny)
                StatTile(title: "Uscite", value: "\(exits)", icon: "doorOpen", tint: Theme.neutral, shape: .cookie6Sided)
            }
        }
    }

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

struct ProfileCard: View {
    @Environment(AppModel.self) private var model
    /// Riempie l'altezza disponibile.
    var fillsHeight = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            Avatar(initials: model.card?.initials ?? String(model.displayName.prefix(1)), size: 72,
                   shape: .cookie12Sided, rotation: .degrees(hovering ? 30 : 0))
                .scaleEffect(hovering ? 1.04 : 1)
            // Solo nome e scuola: la classe è nella pagina Account.
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.m3(22, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
                if let school = model.card?.schoolDescription {
                    Text([school, model.card?.schoolCity?.nameCased].compactMap { $0 }.joined(separator: " · "))
                        .font(.m3(14))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
            Icon("chevronRight", size: 22)
                .foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil)
        .card(radius: Theme.radii.xl)
        .onHover { hovering in withAnimation(Motion.spatial) { self.hovering = hovering } }
    }
}

