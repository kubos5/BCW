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
                        FilterChip(title: c.title, icon: c.icon, isSelected: category == c) {
                            category = category == c ? nil : c
                        }
                    }
                }

                if filtered.isEmpty {
                    EmptyState("Nessuna nota", icon: "thumbsUp", description: "Continua così!")
                } else {
                    ListGroup {
                        ForEach(filtered) { note in
                            NoteCard(note: note)
                        }
                    }
                }
            }
            // Sull'iPad largo larga al massimo 860 punti (come la versione web).
            .readableWidth()
            .pagePadding()
            .padding(.bottom, 32)
            .animation(Motion.spatial, value: category)
        }
        .tracksPageScroll()
        .themedBackground()
        .refreshable { await model.loadNotes() }
        .pageChrome("Note", style: .inline)
    }

    private var summary: some View {
        HStack(spacing: 2) {
            ForEach([DisciplinaryNote.Category.annotation, .disciplinary]) { c in
                StatTile(title: c.title, value: "\(model.notes.filter { $0.category == c }.count)",
                         icon: c.icon, tint: c == .annotation ? Theme.neutral : Theme.poor,
                         shape: c == .annotation ? .cookie4Sided : .clover4Leaf,
                         corners: c == .annotation ? .leading : .trailing, vertical: true)
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
                HStack(spacing: 8) {
                    Icon(note.category.icon, size: 20)
                    Text(note.category.singular)
                        .font(.m3(14, weight: 650))
                }
                .foregroundStyle(tint)
                Spacer()
                if !note.isRead {
                    Pill(text: "Nuova", filled: true, small: true)
                }
            }
            Text(note.text.isEmpty ? "Tocca per leggere il contenuto." : note.text)
                .font(.m3(15))
                .lineSpacing(3)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
            Text("\(note.authorName) · \(note.date.longDay)")
                .font(.m3(12))
                .foregroundStyle(Theme.secondaryInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
