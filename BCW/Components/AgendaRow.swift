import EventKit
import EventKitUI
import SwiftUI
import UniformTypeIdentifiers

struct AgendaEventRow: View {
    @Environment(AppModel.self) private var model
    let event: AgendaEvent
    var showsDate = false
    /// Testo aperto: un tocco sulla riga mostra tutto il testo tagliato (o lo richiude).
    @State private var expanded = false
    @State private var exportingToCalendar = false

    private var isDone: Bool { model.preferences.isCompleted(event) }

    var body: some View {
        LeadingColumnLayout(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    SubjectTag(name: event.title, id: event.subjectId)
                        .layoutPriority(1)
                    if event.kind == .test {
                        Pill(text: "Verifica", bold: true)
                    }
                }
                Text(event.notes.isEmpty ? "Nessuna descrizione" : event.notes)
                    .font(.m3(15))
                    .lineSpacing(2)
                    .foregroundStyle(isDone ? Theme.secondaryInk : Theme.ink)
                    .strikethrough(isDone, color: Theme.secondaryInk)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(Motion.spatial) { expanded.toggle() }
        }
        .contextMenu {
            if event.kind != .event {
                Button { toggle() } label: {
                    Label(isDone ? "Segna come da fare" : "Segna come fatto", icon: isDone ? "arrowUturn" : "checkCircle")
                }
            }
            Button { addToCalendar() } label: { Label("Aggiungi al Calendario", icon: "calendarPlus") }
            ShareLink(item: shareText) { Label("Condividi", icon: "share") }
            Button { Platform.copy(event.notes) } label: { Label("Copia testo", icon: "copy") }
        }
        .sheet(isPresented: $exportingToCalendar) {
            EventEditor(event: event).ignoresSafeArea()
        }
    }

    private func addToCalendar() {
        exportingToCalendar = true
    }

    @ViewBuilder
    private var leading: some View {
        if event.kind == .event {
            Icon("calendar", size: 22)
                .foregroundStyle(Theme.subjectColor(event.subjectId))
                .frame(width: 32, height: 32)
                .padding(.horizontal, -2)
                .padding(.top, -4)
        } else {
            Button(action: toggle) {
                // Come la casella di Material 3: il segno compare ingrandendosi con la molla veloce.
                ZStack {
                    if isDone {
                        Icon("checkCircleFill")
                            .foregroundStyle(Theme.good)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else {
                        Icon("circle")
                            .foregroundStyle(Theme.subjectColor(event.subjectId))
                            .transition(.opacity)
                    }
                }
                .animation(Motion.spatialFast, value: isDone)
            }
            .buttonStyle(CheckButtonStyle())
            .frame(width: 32, height: 32)
            .padding(.horizontal, -2)
            .padding(.top, -4)
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
        withAnimation(Motion.spatialFast) { model.preferences.toggleCompleted(event) }
        Task { await model.rescheduleReminders() }
    }
}

/// Per `.equatable()`: la riga si ricalcola solo se cambia l'evento. Ciò che legge dal modello
/// (es. compito fatto) la aggiorna comunque.
extension AgendaEventRow: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.event == rhs.event && lhs.showsDate == rhs.showsDate
    }
}

/// Casella dei compiti: alla pressione si rimpicciolisce, con il velo circolare.
private struct CheckButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 32, height: 32)
            .background(Circle().fill(.foreground.opacity(configuration.isPressed ? 0.1 : 0)))
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .contentShape(Circle())
            .animation(Motion.spatialFast, value: configuration.isPressed)
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

// MARK: - Esportazione in iCalendar

/// Agenda in formato iCalendar (.ics), da aprire con Calendario, Google Calendar, Outlook…:
/// ogni compito e verifica ha un avviso la sera prima all'orario dei promemoria.
struct AgendaCalendarFile: Transferable {
    let events: [AgendaEvent]
    let reminderHour: Int?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .calendarEvent) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Agenda BCW.ics")
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    private var contents: String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//BCW//Better ClasseViVa//IT", "CALSCALE:GREGORIAN",
                     "X-WR-CALNAME:BCW"]
        for event in events { lines += vevent(event) }
        lines.append("END:VCALENDAR")
        return lines.map(Self.fold).joined(separator: "\r\n") + "\r\n"
    }

    private func vevent(_ event: AgendaEvent) -> [String] {
        let allDay = event.isFullDay || event.kind == .homework
        var lines = ["BEGIN:VEVENT", "UID:bcw-\(event.id)@bcw", "DTSTAMP:\(Self.utc(Date()))",
                     "SUMMARY:\(Self.escape(Self.title(event)))", "DESCRIPTION:\(Self.escape(event.notes))"]
        if allDay {
            lines += ["DTSTART;VALUE=DATE:\(Self.dateOnly(event.begin))",
                      "DTEND;VALUE=DATE:\(Self.dateOnly(event.begin.adding(days: 1)))"]
        } else {
            let end = event.end > event.begin ? event.end : event.begin.addingTimeInterval(3600)
            lines += ["DTSTART:\(Self.utc(event.begin))", "DTEND:\(Self.utc(end))"]
        }
        if let reminderHour, event.kind != .event,
           let fire = CVDate.calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: event.day.adding(days: -1)) {
            lines += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(Self.escape(Self.title(event)))",
                      "TRIGGER;VALUE=DATE-TIME:\(Self.utc(fire))", "END:VALARM"]
        }
        lines.append("END:VEVENT")
        return lines
    }

    private static func title(_ event: AgendaEvent) -> String {
        let prefix = event.kind == .test ? "Verifica" : (event.kind == .homework ? "Compiti" : "")
        return [prefix, event.title].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = CVDate.calendar
        formatter.timeZone = CVDate.calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Le righe più lunghe di 75 byte vanno spezzate (RFC 5545).
    private static func fold(_ line: String) -> String {
        var parts: [String] = []
        var current = ""
        var bytes = 0
        for character in line {
            let size = String(character).utf8.count
            if bytes + size > 73 {
                parts.append(current)
                current = " "
                bytes = 1
            }
            current.append(character)
            bytes += size
        }
        parts.append(current)
        return parts.joined(separator: "\r\n")
    }
}
