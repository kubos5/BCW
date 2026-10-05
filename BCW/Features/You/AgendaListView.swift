import SwiftUI

struct AgendaListView: View {
    private static let searchPrompt = "Cerca compiti ed eventi"
    @Environment(AppModel.self) private var model
    @State private var kind: AgendaEvent.Kind?
    @State private var showPast = false
    @State private var onlyPending = false
    @State private var search = ""

    private var grouped: [(Date, [AgendaEvent])] {
        let today = Date().startOfDay
        let items = model.agenda.filter { e in
            (showPast ? e.begin < today : e.begin >= today)
                && (kind == nil || e.kind == kind)
                && (!onlyPending || !model.preferences.isCompleted(e))
                && (search.isEmpty || e.notes.localizedCaseInsensitiveContains(search)
                    || (e.subjectName ?? "").localizedCaseInsensitiveContains(search))
        }
        return Dictionary(grouping: items, by: \.day)
            .sorted { showPast ? $0.key > $1.key : $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Picker("Periodo", selection: $showPast) {
                        Text("In arrivo").tag(false)
                        Text("Passati").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .compactOnMac()
                    #if os(macOS)
                    Spacer(minLength: 0)
                    LocalSearchField(text: $search, prompt: Self.searchPrompt)
                    #endif
                }

                ChipRow {
                    FilterChip(title: "Da fare", symbol: "circle", isSelected: onlyPending) { onlyPending.toggle() }
                    FilterChip(title: "Tutto", isSelected: kind == nil) { kind = nil }
                    ForEach(AgendaEvent.Kind.allCases) { k in
                        FilterChip(title: k.title, symbol: k.symbol, isSelected: kind == k) {
                            kind = kind == k ? nil : k
                        }
                    }
                }

                if grouped.isEmpty {
                    ContentUnavailableView("Niente da mostrare", systemImage: "checklist",
                                           description: Text("Nessun elemento corrisponde ai filtri."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }

                CardGrid(minWidth: 380, spacing: 14) {
                    ForEach(grouped, id: \.0) { day, events in
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: day.relativeDayName, color: Theme.accent)
                            ForEach(events) { event in
                                AgendaEventRow(event: event)
                                if event.id != events.last?.id { Divider().overlay(Theme.separator) }
                            }
                        }
                        .card()
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, 24)
            .animation(.snappy, value: kind)
            .animation(.snappy, value: showPast)
        }
        .themedBackground()
        .screenTitle("Agenda")
        .localSearchable(text: $search, prompt: Self.searchPrompt)
        .refreshable { await model.loadAgenda() }
    }
}
