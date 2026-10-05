import SwiftUI

struct NotesView: View {
    @Environment(AppModel.self) private var model
    @State private var category: DisciplinaryNote.Category?

    private var filtered: [DisciplinaryNote] {
        model.notes.filter { category == nil || $0.category == category }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary

                ChipRow {
                    FilterChip(title: "Tutte", isSelected: category == nil) { category = nil }
                    ForEach(DisciplinaryNote.Category.allCases) { c in
                        FilterChip(title: c.title, symbol: c.symbol, isSelected: category == c) {
                            category = category == c ? nil : c
                        }
                    }
                }

                if filtered.isEmpty {
                    ContentUnavailableView("Nessuna nota", systemImage: "hand.thumbsup",
                                           description: Text("Continua così!"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    CardGrid(minWidth: 360) {
                        ForEach(filtered) { note in
                            NoteCard(note: note)
                        }
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, 24)
            .animation(.snappy, value: category)
        }
        .themedBackground()
        .screenTitle("Note")
        .refreshable { await model.loadNotes() }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            ForEach([DisciplinaryNote.Category.annotation, .disciplinary]) { c in
                StatTile(title: c.title, value: "\(model.notes.filter { $0.category == c }.count)",
                         symbol: c.symbol, tint: c == .annotation ? Theme.neutral : Theme.poor)
            }
        }
    }
}

private struct NoteCard: View {
    @Environment(AppModel.self) private var model
    let note: DisciplinaryNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(note.category.singular, systemImage: note.category.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                if !note.isRead {
                    Pill(text: "Nuova", filled: true, font: .caption2.weight(.bold))
                }
            }
            Text(note.text.isEmpty ? "Tocca per leggere il contenuto." : note.text)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
            Text("\(note.authorName) · \(note.date.longDay)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryInk)
        }
        .card(padding: 14)
        .task { await model.readNote(note) }
    }

    private var tint: Color {
        switch note.category {
        case .annotation: Theme.neutral
        case .disciplinary, .sanction: Theme.poor
        case .warning: Theme.fair
        }
    }
}
