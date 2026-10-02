import SwiftUI

/// Ricerca globale su compiti, voti, comunicazioni, materiale e note.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var agenda: [AgendaEvent] {
        model.agenda.filter { $0.notes.localizedCaseInsensitiveContains(trimmed)
            || ($0.subjectName ?? "").localizedCaseInsensitiveContains(trimmed) }
            .sorted { abs($0.begin.timeIntervalSinceNow) < abs($1.begin.timeIntervalSinceNow) }
    }

    private var grades: [Grade] {
        model.grades.filter { $0.subjectName.localizedCaseInsensitiveContains(trimmed)
            || ($0.notes ?? "").localizedCaseInsensitiveContains(trimmed) }
    }

    private var notices: [Notice] {
        model.notices.filter { $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.category.localizedCaseInsensitiveContains(trimmed) }
    }

    private var notes: [DisciplinaryNote] {
        model.notes.filter { $0.text.localizedCaseInsensitiveContains(trimmed)
            || $0.authorName.localizedCaseInsensitiveContains(trimmed) }
    }

    private var files: [(DidacticTeacher, DidacticContent)] {
        model.didactics.flatMap { teacher in
            teacher.folders.flatMap(\.contents)
                .filter { $0.name.localizedCaseInsensitiveContains(trimmed) || teacher.name.localizedCaseInsensitiveContains(trimmed) }
                .map { (teacher, $0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if trimmed.isEmpty {
                        suggestions
                    } else if agenda.isEmpty && grades.isEmpty && notices.isEmpty && notes.isEmpty && files.isEmpty {
                        ContentUnavailableView.search(text: trimmed)
                            .padding(.top, 40)
                    } else {
                        results
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationTitle("Cerca")
            .searchable(text: $query, prompt: "Compiti, voti, comunicazioni…")
            .task { if model.didactics.isEmpty { await model.loadDidactics() } }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Suggerimenti")
            FlowChips(items: ["Verifica", "Interrogazione"] + Array(Set(model.grades.map(\.subjectName))).sorted().prefix(8)) {
                query = $0
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if !agenda.isEmpty {
            group("Agenda", count: agenda.count) {
                ForEach(agenda.prefix(15)) { event in
                    AgendaEventRow(event: event, showsDate: true)
                    if event.id != agenda.prefix(15).last?.id { Divider().overlay(Theme.separator) }
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
                                .font(.caption)
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
                    } label: {
                        HStack {
                            Text(notice.title)
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !files.isEmpty {
            group("Materiale didattico", count: files.count) {
                ForEach(files.prefix(10), id: \.1.id) { teacher, content in
                    NavigationLink {
                        DidacticsView()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: content.symbol).foregroundStyle(Theme.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(content.name).foregroundStyle(Theme.ink)
                                Text(teacher.name).font(.caption).foregroundStyle(Theme.secondaryInk)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !notes.isEmpty {
            group("Note", count: notes.count) {
                ForEach(notes.prefix(10)) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.text).foregroundStyle(Theme.ink)
                        Text("\(note.category.singular) · \(note.date.shortDay)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: title, color: Theme.accent)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryInk)
            }
            content()
        }
        .card()
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
