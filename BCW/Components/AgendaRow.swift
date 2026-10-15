import EventKit
#if os(iOS)
import EventKitUI
#endif
import SwiftUI

struct AgendaEventRow: View {
    @Environment(AppModel.self) private var model
    let event: AgendaEvent
    var showsDate = false
    /// Tocco sulla riga quando non c'è testo da aprire (es. andare al giorno, in "Nei prossimi
    /// giorni"). Senza, la riga si apre o si chiude sempre.
    var onPlainTap: (() -> Void)? = nil
    @State private var expanded = false
    /// Altezze del testo mostrato e di quello intero: se coincidono non c'è niente da aprire.
    @State private var shown: CGFloat = 0
    @State private var full: CGFloat = 0
    @State private var exportingToCalendar = false
    /// Esito dell'aggiunta al Calendario (solo macOS, dove non c'è l'editor di sistema).
    @State private var calendarResult: CalendarExport.Result?

    private var isDone: Bool { model.preferences.isCompleted(event) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    SubjectTag(name: event.title, id: event.subjectId)
                    Spacer(minLength: 6)
                    if event.kind == .test {
                        Pill(text: "Verifica", font: .caption.weight(.bold))
                    }
                }
                Text(event.notes.isEmpty ? "Nessuna descrizione" : event.notes)
                    .font(.body)
                    .foregroundStyle(isDone ? Theme.secondaryInk : Theme.ink)
                    .strikethrough(isDone, color: Theme.secondaryInk)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(alignment: .topLeading) {
                        if onPlainTap != nil && !expanded {
                            Text(event.notes.isEmpty ? "Nessuna descrizione" : event.notes)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .hidden()
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full = $0 }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown = $0 }
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if let onPlainTap, !expanded, full <= shown + 1 {
                onPlainTap()
            } else {
                withAnimation(.snappy) { expanded.toggle() }
            }
        }
        .contextMenu {
            if event.kind != .event {
                Button(isDone ? "Segna come da fare" : "Segna come fatto",
                       systemImage: isDone ? "arrow.uturn.backward" : "checkmark.circle") { toggle() }
            }
            Button("Aggiungi al Calendario", systemImage: "calendar.badge.plus") { addToCalendar() }
            ShareLink(item: shareText) { Label("Condividi", systemImage: "square.and.arrow.up") }
            Button("Copia testo", systemImage: "doc.on.doc") { Platform.copy(event.notes) }
        }
        #if os(iOS)
        .sheet(isPresented: $exportingToCalendar) {
            EventEditor(event: event).ignoresSafeArea()
        }
        #else
        .alert(calendarResult?.title ?? "", isPresented: Binding(get: { calendarResult != nil },
                                                                 set: { if !$0 { calendarResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarResult?.message ?? "")
        }
        #endif
    }

    private func addToCalendar() {
        #if os(iOS)
        exportingToCalendar = true
        #else
        Task { calendarResult = await CalendarExport.add(event) }
        #endif
    }

    @ViewBuilder
    private var leading: some View {
        if event.kind == .event {
            IconBadge(symbol: "calendar", tint: Theme.subjectColor(event.subjectId), size: 30)
        } else {
            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isDone ? Theme.good : Theme.subjectColor(event.subjectId))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .sensoryFeedback(.success, trigger: isDone) { _, new in new }
            .accessibilityLabel(isDone ? "Fatto" : "Da fare")
        }
    }

    private var metadata: String {
        var parts: [String] = []
        if showsDate { parts.append(event.begin.relativeDayName) }
        if event.kind != .homework { parts.append(event.timeDescription) }
        if !event.authorName.isEmpty, event.subjectName != nil { parts.append(event.authorName) }
        return parts.joined(separator: " · ")
    }

    private var shareText: String {
        "\(event.title) – \(event.begin.longDay)\n\(event.notes)"
    }

    private func toggle() {
        withAnimation(.snappy) { model.preferences.toggleCompleted(event) }
        Task { await model.rescheduleReminders() }
    }
}

/// Per `.equatable()` nelle righe con `onPlainTap`, una chiusura che cambia a ogni aggiornamento
/// di chi la passa ma fa sempre la stessa cosa: si confronta solo se c'è. Ciò che la riga legge
/// dal modello (es. compito fatto) la aggiorna comunque.
extension AgendaEventRow: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.event == rhs.event && lhs.showsDate == rhs.showsDate && (lhs.onPlainTap == nil) == (rhs.onPlainTap == nil)
    }
}

extension AgendaEvent {
    /// Evento di Calendario corrispondente, con titolo, note e orari.
    func calendarEvent(in store: EKEventStore) -> EKEvent {
        let ekEvent = EKEvent(eventStore: store)
        let prefix = kind == .test ? "Verifica" : (kind == .homework ? "Compiti" : "")
        ekEvent.title = [prefix, title].filter { !$0.isEmpty }.joined(separator: " · ")
        ekEvent.notes = notes
        ekEvent.startDate = begin
        ekEvent.endDate = max(end, begin.addingTimeInterval(3600))
        ekEvent.isAllDay = isFullDay || kind == .homework
        return ekEvent
    }
}

#if os(iOS)
/// Editor nativo di Calendario: dal iOS 17 non richiede permessi di accesso.
struct EventEditor: UIViewControllerRepresentable {
    let event: AgendaEvent
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event.calendarEvent(in: store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
#endif

/// Su macOS non esiste l'editor di EventKitUI: l'evento viene salvato direttamente nel
/// calendario predefinito, chiedendo solo l'accesso in scrittura.
enum CalendarExport {
    struct Result {
        let title: String
        let message: String
    }

    static func add(_ event: AgendaEvent) async -> Result {
        let store = EKEventStore()
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else {
                return Result(title: "Accesso negato",
                              message: "Consenti a BCW di aggiungere eventi in Impostazioni di Sistema › Privacy e sicurezza › Calendari.")
            }
            let ekEvent = event.calendarEvent(in: store)
            ekEvent.calendar = store.defaultCalendarForNewEvents
            try store.save(ekEvent, span: .thisEvent)
            return Result(title: "Aggiunto al Calendario", message: "\"\(ekEvent.title ?? event.title)\" è nel tuo calendario predefinito.")
        } catch {
            return Result(title: "Impossibile aggiungere l'evento", message: error.localizedDescription)
        }
    }
}
