import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NavigationLink {
                        AccountView()
                    } label: {
                        ProfileCard()
                    }
                    .buttonStyle(.plain)
                    stats

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
                        MenuRow(title: "Anno precedente", subtitle: "Voti, assenze e pagelle \(ArchiveModel.defaultTitle)",
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
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationTitle("Tu")
            .refreshable { await model.refreshAll() }
        }
    }

    private var stats: some View {
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
                    Text("\(badge)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.accent, in: .capsule)
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

private struct ProfileCard: View {
    @Environment(AppModel.self) private var model

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
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let classDescription = model.classDescription {
                    Text(classDescription.sentenceCased)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink.opacity(0.8))
                }
                if let school = model.card?.schoolDescription {
                    Text([school, model.card?.schoolCity?.nameCased].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryInk.opacity(0.7))
                .padding(18)
        }
        .card(padding: 18)
    }
}
