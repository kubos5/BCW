import SwiftUI

/// Pagine che sul telefono stanno dentro Tu e che sull'iPad largo sono destinazioni principali
/// della barra di navigazione (come le sezioni della versione web, `sections-meta.js`): stessi
/// titoli, icone, colori, gruppi e conteggi.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case noticeboard, notes, reports, previous, absences, didactics, lessons, agenda, subjects, schoolbooks, calendar

    var id: String { rawValue }

    /// Gruppi della barra di navigazione (e del menu di Tu).
    enum Group: String, CaseIterable, Identifiable {
        case communications, evaluations, attendance, didactics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .communications: "Comunicazioni"
            case .evaluations: "Valutazioni"
            case .attendance: "Frequenza"
            case .didactics: "Didattica"
            }
        }

        var sections: [AppSection] { AppSection.allCases.filter { $0.group == self } }
    }

    var group: Group {
        switch self {
        case .noticeboard, .notes: .communications
        case .reports, .previous: .evaluations
        case .absences: .attendance
        case .didactics, .lessons, .agenda, .subjects, .schoolbooks, .calendar: .didactics
        }
    }

    var title: String {
        switch self {
        case .noticeboard: "Bacheca"
        case .notes: "Note e annotazioni"
        case .reports: "Scrutini e pagelle"
        case .previous: "Anni precedenti"
        case .absences: "Assenze e ritardi"
        case .didactics: "Materiale didattico"
        case .lessons: "Registro delle lezioni"
        case .agenda: "Agenda completa"
        case .subjects: "Materie e docenti"
        case .schoolbooks: "Libri di testo"
        case .calendar: "Calendario scolastico"
        }
    }

    /// Etichetta sotto l'icona nella barra di navigazione ridotta (una riga).
    var shortTitle: String {
        switch self {
        case .noticeboard: "Bacheca"
        case .notes: "Note"
        case .reports: "Scrutini"
        case .previous: "Anni prec."
        case .absences: "Assenze"
        case .didactics: "Materiale"
        case .lessons: "Lezioni"
        case .agenda: "Agenda"
        case .subjects: "Materie"
        case .schoolbooks: "Libri"
        case .calendar: "Calendario"
        }
    }

    var icon: String {
        switch self {
        case .noticeboard: "megaphone"
        case .notes: "messageAlert"
        case .reports: "fileSearch"
        case .previous: "history"
        case .absences: "userClock"
        case .didactics: "folder"
        case .lessons: "bookText"
        case .agenda: "checklist"
        case .subjects: "users"
        case .schoolbooks: "library"
        case .calendar: "calendarClock"
        }
    }

    var tint: Color {
        switch self {
        case .noticeboard: Theme.primary
        case .notes: Theme.poor
        case .reports: Theme.neutral
        case .previous: Theme.secondaryInk
        case .absences: Theme.fair
        case .didactics: Theme.subject(3)
        case .lessons: Theme.subject(1)
        case .agenda: Theme.subject(5)
        case .subjects: Theme.subject(2)
        case .schoolbooks: Theme.subject(4)
        case .calendar: Theme.subject(7)
        }
    }

    func subtitle(_ model: AppModel) -> String {
        switch self {
        case .noticeboard:
            let unread = model.unreadNoticesCount
            return unread == 0 ? "Tutto letto" : (unread == 1 ? "1 comunicazione da leggere" : "\(unread) comunicazioni da leggere")
        case .notes: return model.notes.isEmpty ? "Nessuna nota" : "\(model.notes.count) in totale"
        case .reports: return "Documenti di valutazione"
        case .previous: return "Pagelle e archivio degli anni passati"
        case .absences:
            let pending = model.unjustifiedAbsences.count
            return pending == 0 ? "Tutto giustificato" : "\(pending) da giustificare"
        case .didactics: return "File condivisi dai docenti"
        case .lessons: return "Argomenti svolti in classe"
        case .agenda: return "Tutti i compiti e le verifiche"
        case .subjects: return "\(model.subjects.count) materie"
        case .schoolbooks: return "Adozioni dell'anno in corso"
        case .calendar: return "Vacanze e giorni di lezione"
        }
    }

    /// Conteggio accanto alla voce: comunicazioni e note da leggere, assenze da giustificare.
    func badge(_ model: AppModel) -> Int {
        switch self {
        case .noticeboard: model.unreadNoticesCount
        case .notes: model.notes.filter { !$0.isRead }.count
        case .absences: model.unjustifiedAbsences.count
        default: 0
        }
    }

    /// Nome usato da `-BCWOpenPage` (prove di sviluppo).
    var debugKey: String {
        switch self {
        case .noticeboard: "bacheca"
        case .notes: "note"
        case .reports: "scrutini"
        case .previous: "anni"
        case .absences: "assenze"
        case .didactics: "materiale"
        case .lessons: "lezioni"
        case .agenda: "agenda"
        case .subjects: "materie"
        case .schoolbooks: "libri"
        case .calendar: "calendario"
        }
    }

    init?(debugKey: String) {
        guard let found = AppSection.allCases.first(where: { $0.debugKey == debugKey }) else { return nil }
        self = found
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .noticeboard: NoticeboardView()
        case .notes: NotesView()
        case .reports: ReportsView()
        case .previous: PreviousYearView()
        case .absences: AbsencesView()
        case .didactics: DidacticsView()
        case .lessons: LessonsView()
        case .agenda: AgendaListView()
        case .subjects: SubjectsView()
        case .schoolbooks: SchoolbooksView()
        case .calendar: SchoolCalendarView()
        }
    }
}

/// Richieste di navigazione tra le schede di una finestra (una per finestra, in `MainTabView`):
/// aprire le Impostazioni dalla barra in alto o dalla barra laterale, aprire una sezione nella
/// pila di Tu quando la finestra torna stretta, scegliere una sezione dalle righe di Tu.
@Observable
final class AppNavigation {
    /// Aprire le Impostazioni nella pila di Tu (`YouView` la consuma e la rimette a `false`).
    var openSettings = false
    /// Sezione da aprire nella pila di Tu (finestra tornata stretta con la sezione aperta).
    var pendingSection: AppSection?
    /// Le sezioni sono destinazioni della barra di navigazione (iPad con la finestra larga): le righe
    /// di Tu le scelgono con `select` invece di aprirle nella pila.
    var sectionsAreDestinations = false
    /// Sezione da scegliere nella barra di navigazione (`MainTabView` la consuma).
    var requestedSection: AppSection?

    func select(_ section: AppSection) {
        requestedSection = section
    }
}

extension EnvironmentValues {
    @Entry var appNavigation: AppNavigation?
}
