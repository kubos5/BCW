import EventKit
import EventKitUI
import SwiftUI

struct AgendaEventRow: View {
    @Environment(AppModel.self) private var model
    let event: AgendaEvent
    var showsDate = false
    @State private var expanded = false
    @State private var exportingToCalendar = false

    private var isDone: Bool { model.preferences.isCompleted(event) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    SubjectTag(name: event.title, id: event.subjectId)
                    Spacer(minLength: 6)
                    if event.kind == .test {
                        Text("Verifica")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.14), in: .capsule)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(event.notes.isEmpty ? "Nessuna descrizione" : event.notes)
                    .font(.body)
                    .foregroundStyle(isDone ? Theme.secondaryInk : Theme.ink)
                    .strikethrough(isDone, color: Theme.secondaryInk)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .contextMenu {
            if event.kind != .event {
                Button(isDone ? "Segna come da fare" : "Segna come fatto",
                       systemImage: isDone ? "arrow.uturn.backward" : "checkmark.circle") { toggle() }
            }
            Button("Aggiungi al Calendario", systemImage: "calendar.badge.plus") { exportingToCalendar = true }
            ShareLink(item: shareText) { Label("Condividi", systemImage: "square.and.arrow.up") }
            Button("Copia testo", systemImage: "doc.on.doc") { UIPasteboard.general.string = event.notes }
        }
        .sheet(isPresented: $exportingToCalendar) {
            EventEditor(event: event).ignoresSafeArea()
        }
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

/// Editor nativo di Calendario: dal iOS 17 non richiede permessi di accesso.
struct EventEditor: UIViewControllerRepresentable {
    let event: AgendaEvent
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        let ekEvent = EKEvent(eventStore: store)
        let prefix = event.kind == .test ? "Verifica" : (event.kind == .homework ? "Compiti" : "")
        ekEvent.title = [prefix, event.title].filter { !$0.isEmpty }.joined(separator: " · ")
        ekEvent.notes = event.notes
        ekEvent.startDate = event.begin
        ekEvent.endDate = max(event.end, event.begin.addingTimeInterval(3600))
        ekEvent.isAllDay = event.isFullDay || event.kind == .homework
        controller.event = ekEvent
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
