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
                    // Profilo e statistiche formano un blocco: stessa distanza che c'è tra le statistiche.
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink {
                            AccountView()
                        } label: {
                            ProfileCard()
                        }
                        .buttonStyle(.plain)
                        stats
                    }

                    menuSection("Comunicazioni") {
                        MenuRow(title: "Bacheca", subtitle: noticeSubtitle, symbol: "megaphone",
                                tint: Theme.accent, badge: model.unreadNoticesCount) { NoticeboardView() }
                        MenuRow(title: "Note e annotazioni", subtitle: notesSubtitle,
                                symbol: "exclamationmark.bubble", tint: Theme.poor,
                                badge: model.notes.filter { !$0.isRead }.count) { NotesView() }
                    }

                    menuSection("Valutazioni") {
                        MenuRow(title: "Scrutini e pagelle", subtitle: "Documenti di valutazione",
                                symbol: "doc.text.magnifyingglass", tint: Theme.neutral) { ReportsView() }
                        MenuRow(title: "Anni precedenti", subtitle: "Pagelle e archivio degli anni passati",
                                symbol: "clock.arrow.circlepath", tint: Theme.secondaryInk) { PreviousYearView() }
                    }

                    menuSection("Frequenza") {
                        MenuRow(title: "Assenze e ritardi", subtitle: absenceSubtitle,
                                symbol: "person.badge.clock", tint: Theme.fair,
                                badge: model.unjustifiedAbsences.count) { AbsencesView() }
                    }

                    menuSection("Didattica") {
                        MenuRow(title: "Materiale didattico", subtitle: "File condivisi dai docenti",
                                symbol: "folder", tint: Theme.subjectColor(3)) { DidacticsView() }
                        MenuRow(title: "Registro delle lezioni", subtitle: "Argomenti svolti in classe",
                                symbol: "text.book.closed", tint: Theme.subjectColor(1)) { LessonsView() }
                        MenuRow(title: "Agenda completa", subtitle: "Tutti i compiti e le verifiche",
                                symbol: "checklist", tint: Theme.subjectColor(5)) { AgendaListView() }
                        MenuRow(title: "Materie e docenti", subtitle: "\(model.subjects.count) materie",
                                symbol: "person.2", tint: Theme.subjectColor(2)) { SubjectsView() }
                        MenuRow(title: "Libri di testo", subtitle: "Adozioni dell'anno in corso",
                                symbol: "books.vertical", tint: Theme.subjectColor(4)) { SchoolbooksView() }
                        MenuRow(title: "Calendario scolastico", subtitle: "Vacanze e giorni di lezione",
                                symbol: "calendar.badge.clock", tint: Theme.subjectColor(7)) { SchoolCalendarView() }
                    }

                    menuSection("App") {
                        MenuRow(title: "Impostazioni", subtitle: "Medie, promemoria, sicurezza",
                                symbol: "gearshape", tint: Theme.secondaryInk) { SettingsView() }
                    }

                    footer
                }
                .pagePadding()
                .padding(.bottom, Theme.bottomInset)
            }
            .themedBackground()
            .screenTitle("Tu")
            .inlineLargeTitleDisplay()
            .refreshable { await model.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .trailingBar) { accountSwitcher }
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
        Button {
            switchingAccount = true
        } label: {
            Image(systemName: model.accounts.count > 1 ? "person.2.circle" : "person.crop.circle.badge.plus")
        }
        .accessibilityLabel(model.accounts.count > 1 ? "Cambia account" : "Aggiungi account")
    }

    var stats: some View {
        let absences = model.absences.filter { $0.kind == .absence }.count
        let lates = model.absences.filter { $0.kind == .late || $0.kind == .shortLate }.count
        let exits = model.absences.filter { $0.kind == .earlyExit }.count
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "Media", value: GradeFormat.average(model.gradeBook.average()),
                         symbol: "graduationcap", tint: Theme.gradeColor(value: model.gradeBook.average()))
                StatTile(title: "Assenze", value: "\(absences)", symbol: "person.crop.circle.badge.xmark", tint: Theme.poor)
            }
            GridRow {
                StatTile(title: "Ritardi", value: "\(lates)", symbol: "clock", tint: Theme.fair)
                StatTile(title: "Uscite", value: "\(exits)", symbol: "figure.walk.departure", tint: Theme.neutral)
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

    private var footer: some View {
        VStack(spacing: 4) {
            Text("BCW · Better ClasseViVa")
                .font(.footnote.weight(.semibold))
            if let updated = model.lastUpdated {
                Text("Aggiornato alle \(updated.time)")
            }
            if model.isDemo {
                Text("Modalità demo: i dati sono di esempio.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryInk)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func menuSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
                .padding(.leading, 6)
            VStack(spacing: 0) {
                content()
            }
            .background(Theme.surface, in: .rect(cornerRadius: Theme.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.7), lineWidth: 0.5)
            }
        }
    }
}

private struct MenuRow<Destination: View>: View {
    let title: String
    var subtitle: String?
    let symbol: String
    var tint: Color = Theme.accent
    var badge: Int = 0
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                IconBadge(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if badge > 0 {
                    Pill(text: "\(badge)", filled: true, font: .caption.weight(.bold).monospacedDigit())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct ProfileCard: View {
    @Environment(AppModel.self) private var model
    /// Riempie l'altezza disponibile (su macOS, accanto alle statistiche).
    var fillsHeight = false

    var body: some View {
        HStack(spacing: 16) {
            Text(model.card?.initials ?? String(model.displayName.prefix(1)))
                .font(.numeral(26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .background(
                    LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .circle
                )
            // Solo nome e scuola: la classe è nella pagina Account.
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let school = model.card?.schoolDescription {
                    Text([school, model.card?.schoolCity?.nameCased].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryInk.opacity(0.7))
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil)
        .card(padding: 18)
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
                            .padding(.leading, 6)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12, alignment: .top)],
                                  alignment: .leading, spacing: 12) {
                            ForEach(group.sections) { section in
                                SectionTile(section: section, subtitle: subtitle(for: section),
                                            badge: badge(for: section)) {
                                    nav.show(section)
                                }
                            }
                        }
                    }
                }

                footer
            }
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        .themedBackground()
        .screenTitle("Tu")
    }

    private func profile(fillsHeight: Bool) -> some View {
        NavigationLink {
            AccountView()
                .pushedPageActions()
        } label: {
            ProfileCard(fillsHeight: fillsHeight)
        }
        .buttonStyle(.plain)
    }

    private func stats(fillsHeight: Bool) -> some View {
        let absences = model.absences.filter { $0.kind == .absence }.count
        let lates = model.absences.filter { $0.kind == .late || $0.kind == .shortLate }.count
        let exits = model.absences.filter { $0.kind == .earlyExit }.count
        return HStack(spacing: 10) {
            StatTile(title: "Media", value: GradeFormat.average(model.gradeBook.average()),
                     symbol: "graduationcap", tint: Theme.gradeColor(value: model.gradeBook.average()),
                     fillsHeight: fillsHeight)
            StatTile(title: "Assenze", value: "\(absences)", symbol: "person.crop.circle.badge.xmark", tint: Theme.poor, fillsHeight: fillsHeight)
            StatTile(title: "Ritardi", value: "\(lates)", symbol: "clock", tint: Theme.fair, fillsHeight: fillsHeight)
            StatTile(title: "Uscite", value: "\(exits)", symbol: "figure.walk.departure", tint: Theme.neutral, fillsHeight: fillsHeight)
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

    private var footer: some View {
        VStack(spacing: 4) {
            Text("BCW · Better ClasseViVa")
                .font(.footnote.weight(.semibold))
            if let updated = model.lastUpdated {
                Text("Aggiornato alle \(updated.time)")
            }
            if model.isDemo {
                Text("Modalità demo: i dati sono di esempio.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryInk)
        .frame(maxWidth: .infinity)
    }
}

/// Riquadro di una sezione nella pagina "Tu" su macOS.
private struct SectionTile: View {
    let section: MacSection
    let subtitle: String
    let badge: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(symbol: section.symbol, tint: section.tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if badge > 0 {
                    Pill(text: "\(badge)", filled: true, font: .caption.weight(.bold).monospacedDigit())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk.opacity(hovering ? 1 : 0.6))
            }
            .card(padding: 14)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(section.tint.opacity(hovering ? 0.5 : 0), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: Theme.corner))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
    }
}
#endif
