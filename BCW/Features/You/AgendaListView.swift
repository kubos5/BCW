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
        // Calcolato una volta per aggiornamento (a ogni lettera della ricerca).
        let grouped = grouped
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageSearchBar(text: $search, prompt: Self.searchPrompt)
                HStack(spacing: 12) {
                    SegmentedButtons(selection: $showPast, options: [(false, "In arrivo", nil), (true, "Passati", nil)],
                                     compact: Platform.isMac)
                    #if os(macOS)
                    Spacer(minLength: 0)
                    LocalSearchField(text: $search, prompt: Self.searchPrompt)
                    #endif
                }

                ChipRow {
                    FilterChip(title: "Da fare", icon: "circle", isSelected: onlyPending) { onlyPending.toggle() }
                    FilterChip(title: "Tutto", isSelected: kind == nil) { kind = nil }
                    ForEach(AgendaEvent.Kind.allCases) { k in
                        FilterChip(title: k.title, icon: k.icon, isSelected: kind == k) {
                            kind = kind == k ? nil : k
                        }
                    }
                }

                if grouped.isEmpty {
                    EmptyState("Niente da mostrare", icon: "checklist", description: "Nessun elemento corrisponde ai filtri.")
                }

                CardGrid(minWidth: 380, spacing: 12) {
                    ForEach(grouped, id: \.0) { day, events in
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: day.relativeDayName, color: Theme.primary)
                            let lastID = events.last?.id
                            ForEach(events) { event in
                                AgendaEventRow(event: event)
                                if event.id != lastID { M3Divider() }
                            }
                        }
                        .card()
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, 32)
            .animation(Motion.spatial, value: kind)
            .animation(Motion.spatial, value: showPast)
        }
        .tracksPageScroll()
        .themedBackground()
        .modifier(GlassLocalSearch(text: $search, prompt: Self.searchPrompt))
        .refreshable { await model.loadAgenda() }
        .pageChrome("Agenda", style: .inline) {
            ShareLink(item: AgendaCalendarFile(events: model.agenda.filter { $0.begin >= Date().startOfDay },
                                               reminderHour: model.preferences.homeworkReminders ? model.preferences.reminderHour : nil),
                      preview: SharePreview("Agenda di BCW")) {
                Label { Text("Esporta nel calendario") } icon: { ThemeStore.shared.liquidGlass ? AnyView(Image.m("calendarPlus")) : AnyView(Icon("calendarPlus")) }
            }
            .help("Esporta nel calendario")
        }
    }
}
