import QuickLook
import SwiftUI

struct PreviousYearView: View {
    @Environment(AppModel.self) private var model
    @State private var archive = ArchiveModel()
    @State private var section: Section = .grades
    @State private var previewURL: URL?
    @State private var downloading: String?
    @State private var error: String?

    enum Section: String, CaseIterable, Identifiable {
        case grades, absences, notes, documents
        var id: String { rawValue }
        var title: String {
            switch self {
            case .grades: "Voti"
            case .absences: "Assenze"
            case .notes: "Note"
            case .documents: "Pagelle"
            }
        }
    }

    var body: some View {
        Group {
            switch archive.state {
            case .idle, .loading:
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Accesso all'archivio \(archive.title)…")
                        .foregroundStyle(Theme.secondaryInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Archivio non disponibile", systemImage: "archivebox")
                } description: {
                    Text(message)
                } actions: {
                    Button("Riprova") {
                        archive.state = .idle
                        Task { await load() }
                    }
                    .buttonStyle(.glass)
                }
            case .loaded:
                content
            }
        }
        .themedBackground()
        .navigationTitle("Anno \(archive.title)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SubjectSummary.self) { summary in
            SubjectDetailView(subjectId: summary.subjectId, book: book)
        }
        .quickLookPreview($previewURL)
        .task { await load() }
    }

    private var book: GradeBook {
        GradeBook(grades: archive.grades, periods: archive.periods,
                  mode: model.preferences.averageMode, weighted: model.preferences.weightedAverage)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            Picker("Sezione", selection: $section) {
                ForEach(Section.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch section {
            case .grades:
                GradeBookView(book: book)
            case .absences:
                list {
                    if archive.absences.isEmpty {
                        ContentUnavailableView("Nessuna assenza", systemImage: "checkmark.circle")
                    }
                    ForEach(archive.absences) { absence in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(absence.date.longDay + " " + absence.date.it("yyyy"))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryInk)
                            AbsenceRow(absence: absence)
                        }
                        .card(padding: 14)
                    }
                }
            case .notes:
                list {
                    if archive.notes.isEmpty {
                        ContentUnavailableView("Nessuna nota", systemImage: "hand.thumbsup")
                    }
                    ForEach(archive.notes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(note.category.singular, systemImage: note.category.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(note.text).foregroundStyle(Theme.ink)
                            Text("\(note.authorName) · \(note.date.shortDayWithYear)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        .card(padding: 14)
                    }
                }
            case .documents:
                list {
                    if let error { StatusBanner(message: error, symbol: "exclamationmark.triangle") }
                    if archive.documents.isEmpty {
                        ContentUnavailableView("Nessun documento", systemImage: "doc.text")
                    }
                    ForEach(archive.documents) { doc in
                        DocumentButton(title: doc.title, isLoading: downloading == doc.id) {
                            Task { await open(doc) }
                        }
                    }
                }
            }
        }
    }

    private func list<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) { content() }
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
    }

    private func load() async {
        await archive.load(credentials: model.credentialsForArchive, demo: model.isDemo)
    }

    private func open(_ doc: ReportDocument) async {
        downloading = doc.id
        defer { downloading = nil }
        do {
            previewURL = try await archive.downloadDocument(doc)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
