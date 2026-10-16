import SwiftUI

/// Ricerca globale su compiti, voti, comunicazioni, materiale e note.
struct SearchView: View {
    static let prompt = "Compiti, voti, altro…"

    @Environment(AppModel.self) private var model
    /// Testo cercato (appartiene a chi mostra la pagina).
    @Binding var query: String

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    @FocusState private var fieldFocused: Bool

    /// Risultati della ricerca, calcolati una volta per aggiornamento (a ogni lettera digitata):
    /// prima ogni elenco veniva rifiltrato e riordinato più volte, anche una per ogni riga.
    private struct Results {
        let agenda: [AgendaEvent]
        let grades: [Grade]
        let notices: [Notice]
        let notes: [DisciplinaryNote]
        let files: [(DidacticTeacher, DidacticContent)]

        var isEmpty: Bool {
            agenda.isEmpty && grades.isEmpty && notices.isEmpty && notes.isEmpty && files.isEmpty
        }

        init(model: AppModel, query trimmed: String) {
            let now = Date()
            agenda = model.agenda.filter { $0.notes.localizedCaseInsensitiveContains(trimmed)
                || ($0.subjectName ?? "").localizedCaseInsensitiveContains(trimmed) }
                .sorted { abs($0.begin.timeIntervalSince(now)) < abs($1.begin.timeIntervalSince(now)) }
            grades = model.grades.filter { $0.subjectName.localizedCaseInsensitiveContains(trimmed)
                || ($0.notes ?? "").localizedCaseInsensitiveContains(trimmed) }
            notices = model.notices.filter { $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.category.localizedCaseInsensitiveContains(trimmed) }
            notes = model.notes.filter { $0.text.localizedCaseInsensitiveContains(trimmed)
                || $0.authorName.localizedCaseInsensitiveContains(trimmed) }
            files = model.didactics.flatMap { teacher in
                teacher.folders.flatMap(\.contents)
                    .filter { $0.name.localizedCaseInsensitiveContains(trimmed) || teacher.name.localizedCaseInsensitiveContains(trimmed) }
                    .map { (teacher, $0) }
            }
        }
    }

    var body: some View {
        PlatformNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !ThemeStore.shared.liquidGlass {
                        PageLargeTitle()
                            .padding(.bottom, -4)
                        M3SearchBar(text: $query, prompt: Self.prompt, focus: $fieldFocused)
                            .padding(.bottom, 4)
                    }
                    if trimmed.isEmpty {
                        suggestions
                    } else {
                        let results = Results(model: model, query: trimmed)
                        if results.isEmpty {
                            EmptyState("Nessun risultato per \"\(trimmed)\"", icon: "search",
                                       description: "Controlla l'ortografia o prova con un'altra ricerca.")
                        } else {
                            CardGrid(minWidth: 400, spacing: 12) {
                                resultCards(results)
                            }
                        }
                    }
                }
                .pagePadding()
                .padding(.bottom, 32)
            }
            .tracksPageScroll()
            .scrollDismissesKeyboard(.immediately)
            .themedBackground()
            .pageChrome("Cerca")
            .modifier(SystemSearch(query: $query))
            .task { if model.didactics.isEmpty { await model.loadDidactics() } }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Suggerimenti")
            FlowChips(items: ["Verifica", "Interrogazione"] + Array(Set(model.grades.map(\.subjectName))).sorted().prefix(8)) {
                query = $0
                fieldFocused = true
            }
        }
    }

    @ViewBuilder
    private func resultCards(_ results: Results) -> some View {
        let agenda = results.agenda
        let grades = results.grades
        let notices = results.notices
        let notes = results.notes
        let files = results.files
        if !agenda.isEmpty {
            let shown = Array(agenda.prefix(15))
            let lastID = shown.last?.id
            group("Agenda", count: agenda.count) {
                ForEach(shown) { event in
                    AgendaEventRow(event: event, showsDate: true)
                    if event.id != lastID { M3Divider() }
                }
            }
        }
        if !grades.isEmpty {
            group("Voti", count: grades.count) {
                ForEach(grades.prefix(15)) { grade in
                    HStack(spacing: 12) {
                        GradeBadge(grade: grade, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            SubjectTag(name: grade.subjectName, id: grade.subjectId)
                            Text("\(grade.kind) · \(grade.date.shortDay)\(grade.notes.map { " · \($0)" } ?? "")")
                                .font(.m3(12))
                                .foregroundStyle(Theme.secondaryInk)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        if !notices.isEmpty {
            group("Bacheca", count: notices.count) {
                ForEach(notices.prefix(10)) { notice in
                    NavigationLink {
                        NoticeDetailView(notice: notice)
                            .pageChrome("", style: .inline)
                    } label: {
                        HStack(spacing: 12) {
                            Text(notice.title)
                                .font(.m3(15))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Icon("chevronRight", size: 22)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable(radius: Theme.radii.m, pressed: Theme.radii.m))
                    .padding(.horizontal, -8)
                }
            }
        }
        if !files.isEmpty {
            group("Materiale didattico", count: files.count) {
                ForEach(files.prefix(10), id: \.1.id) { teacher, content in
                    NavigationLink {
                        DidacticsView()
                    } label: {
                        HStack(spacing: 12) {
                            Icon(content.icon).foregroundStyle(Theme.primary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(content.name).font(.m3(15)).foregroundStyle(Theme.ink)
                                Text(teacher.name).font(.m3(12)).foregroundStyle(Theme.secondaryInk)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable(radius: Theme.radii.m, pressed: Theme.radii.m))
                    .padding(.horizontal, -8)
                }
            }
        }
        if !notes.isEmpty {
            group("Note", count: notes.count) {
                ForEach(notes.prefix(10)) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.text).font(.m3(15)).foregroundStyle(Theme.ink)
                        Text("\(note.category.singular) · \(note.date.shortDay)")
                            .font(.m3(12))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: title, color: Theme.primary)
                Spacer()
                Text("\(count)")
                    .font(.m3(12).monospacedDigit())
                    .foregroundStyle(Theme.secondaryInk)
            }
            content()
        }
        .card()
    }
}

/// Con Liquid Glass il campo di ricerca è quello di sistema (nella barra delle schede);
/// altrimenti è la barra di ricerca di Material 3 nel contenuto.
private struct SystemSearch: ViewModifier {
    @Binding var query: String

    func body(content: Content) -> some View {
        if ThemeStore.shared.liquidGlass {
            content
                .searchable(text: $query, prompt: SearchView.prompt)
                // Con la tastiera aperta il titolo "Cerca" resta visibile.
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content
        }
    }
}

/// Chip che vanno a capo automaticamente.
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                FilterChip(title: item, isSelected: false) { onTap(item) }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
