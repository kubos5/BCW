import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @State private var switchingAccount = false

    var body: some View {
        #if os(macOS)
        MacYouView()
        #else
        iOSBody
        #endif
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
            #if os(iOS)
            .sheet(isPresented: $switchingAccount) {
                AccountSwitcherSheet()
            }
            #endif
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
    /// Riempie l'altezza disponibile (su macOS, accanto alle statistiche).
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

#if os(macOS)
/// "Tu" su macOS: le funzioni sono già nella barra laterale, quindi la pagina diventa
/// un riepilogo dell'account con lo stato di ogni sezione, a griglia.
private struct MacYouView: View {
    @Environment(AppModel.self) private var model
    @Environment(MacNavigation.self) private var nav

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                // Profilo e statistiche affiancati se c'è spazio, altrimenti uno sotto l'altro.
                // Affiancati hanno tutti la stessa altezza: quella del più alto. Tra profilo e
                // statistiche c'è la stessa distanza che c'è tra le statistiche.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        profile(fillsHeight: true)
                            .frame(minWidth: 380)
                        stats(fillsHeight: true)
                            .frame(width: 520)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        profile(fillsHeight: false)
                        stats(fillsHeight: false)
                    }
                }

                ForEach(MacSection.groups.dropFirst().indices, id: \.self) { index in
                    let group = MacSection.groups[index]
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: group.title ?? "")
                            .padding(.leading, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10, alignment: .top)],
                                  alignment: .leading, spacing: 10) {
                            ForEach(group.sections) { section in
                                SectionTile(section: section, subtitle: subtitle(for: section),
                                            badge: badge(for: section)) {
                                    nav.show(section)
                                }
                            }
                        }
                    }
                }

                YouFooter()
            }
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        .tracksPageScroll()
        .themedBackground()
        .pageChrome("Tu")
    }

    private func profile(fillsHeight: Bool) -> some View {
        NavigationLink {
            AccountView()
        } label: {
            ProfileCard(fillsHeight: fillsHeight)
        }
        .buttonStyle(.pressable(radius: Theme.radii.xl, pressed: Theme.radii.l))
    }

    private func stats(fillsHeight: Bool) -> some View {
        let absences = model.absences.filter { $0.kind == .absence }.count
        let lates = model.absences.filter { $0.kind == .late || $0.kind == .shortLate }.count
        let exits = model.absences.filter { $0.kind == .earlyExit }.count
        return HStack(spacing: 10) {
            StatTile(title: "Media", value: GradeFormat.average(model.gradeBook.average()),
                     icon: "graduationCap", tint: Theme.gradeColor(value: model.gradeBook.average()),
                     shape: .cookie9Sided, fillsHeight: fillsHeight)
            StatTile(title: "Assenze", value: "\(absences)", icon: "userX", tint: Theme.poor, shape: .clover4Leaf, fillsHeight: fillsHeight)
            StatTile(title: "Ritardi", value: "\(lates)", icon: "clock", tint: Theme.fair, shape: .sunny, fillsHeight: fillsHeight)
            StatTile(title: "Uscite", value: "\(exits)", icon: "doorOpen", tint: Theme.neutral, shape: .cookie6Sided, fillsHeight: fillsHeight)
        }
    }

    private func subtitle(for section: MacSection) -> String {
        switch section {
        case .noticeboard:
            let unread = model.unreadNoticesCount
            return unread == 0 ? "Tutto letto" : (unread == 1 ? "1 comunicazione da leggere" : "\(unread) comunicazioni da leggere")
        case .notes: return model.notes.isEmpty ? "Nessuna nota" : "\(model.notes.count) in totale"
        case .reports: return "Documenti di valutazione"
        case .previousYears: return "Pagelle e archivio degli anni passati"
        case .absences:
            let pending = model.unjustifiedAbsences.count
            return pending == 0 ? "Tutto giustificato" : "\(pending) da giustificare"
        case .didactics: return "File condivisi dai docenti"
        case .lessons: return "Argomenti svolti in classe"
        case .agenda: return "Tutti i compiti e le verifiche"
        case .subjects: return "\(model.subjects.count) materie"
        case .schoolbooks: return "Adozioni dell'anno in corso"
        case .schoolCalendar: return "Vacanze e giorni di lezione"
        default: return ""
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

/// Riquadro di una sezione nella pagina "Tu" su macOS.
private struct SectionTile: View {
    let section: MacSection
    let subtitle: String
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(icon: section.icon, tint: section.tint, size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.title)
                        .font(.m3(16, weight: 600))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.m3(13))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if badge > 0 {
                    Pill(text: "\(badge)", color: Theme.error, filled: true)
                }
                Icon("chevronRight", size: 22)
                    .foregroundStyle(Theme.secondaryInk)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
        }
        .buttonStyle(.pressable)
    }
}
#endif
